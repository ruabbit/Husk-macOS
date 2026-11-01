/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * Optional AOSP framework.jar on the boot class path, plus a native slice of
 * system_server (ServiceManager + the named services ActivityThread looks up).
 */
#include "husk-tl-aosp.h"
#include "husk-tl-binder.h"
#include "husk-tl-servicemanager.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>

void tl_log_line(const char *fmt, ...);

static bool g_using;

static bool readable(const char *p) { struct stat st; return p && p[0] && !lstat(p, &st) && S_ISREG(st.st_mode) && access(p, R_OK) == 0; }

const char *husk_aosp_framework_path(const char *java_root, char *out, int cap)
{
    if (!java_root || !out || cap < 8) return NULL;
    snprintf(out, (size_t)cap, "%s/aosp/framework.jar", java_root);
    if (readable(out)) return out;
    snprintf(out, (size_t)cap, "%s/framework.jar", java_root);
    if (readable(out)) return out;
    out[0] = 0;
    return NULL;
}

bool husk_aosp_present(const char *java_root)
{
    char p[1200];
    return husk_aosp_framework_path(java_root, p, sizeof(p)) != NULL;
}

bool husk_aosp_using(void) { return g_using; }

static bool add_path(const char *root, const char *name, char (*paths)[1200], int max, const char **boot, int *count)
{
    if (*count >= max || snprintf(paths[*count], 1200, "%s/%s", root, name) >= 1200 || !readable(paths[*count])) return false;
    boot[*count] = paths[*count]; (*count)++; return true;
}

int husk_aosp_boot_jars(const char *root, char (*paths)[1200], int max, const char **boot)
{
    g_using = false;
    if (!root || !paths || !boot || max < 9) return -1;
    static const char *const common[] = {
        "com.android.art/javalib/core-oj.jar", "com.android.art/javalib/core-libart.jar",
        "com.android.art/javalib/okhttp.jar", "com.android.art/javalib/bouncycastle.jar",
        "com.android.art/javalib/apache-xml.jar", "com.android.i18n/javalib/core-icu4j.jar",
        "com.android.conscrypt/javalib/conscrypt.jar"
    };
    int count = 0;
    for (int i = 0; i < 7; ++i) if (!add_path(root, common[i], paths, max, boot, &count)) return -1;
    bool aosp = husk_aosp_present(root);
    if (!add_path(root, aosp ? "husk-framework-core.dex" : "husk-framework.dex", paths, max, boot, &count)) return -1;
    if (aosp) {
        static const char *const names[] = { "framework.jar", "framework-graphics.jar", "ext.jar", "telephony-common.jar", "voip-common.jar", "ims-common.jar", "services.jar" };
        for (int i = 0; i < 7; ++i) {
            char name[100], check[1200];
            snprintf(name, sizeof(name), "aosp/%s", names[i]);
            if (snprintf(check, sizeof(check), "%s/%s", root, name) >= (int)sizeof(check)) return -1;
            if (!readable(check)) snprintf(name, sizeof(name), "%s", names[i]);
            if (snprintf(check, sizeof(check), "%s/%s", root, name) >= (int)sizeof(check)) return -1;
            if (readable(check) && !add_path(root, name, paths, max, boot, &count)) return -1;
        }
    }
    if (!add_path(root, "org.apache.http.legacy.jar", paths, max, boot, &count)) return -1;
    g_using = aosp;
    return count;
}

static void svc_txn(uint32_t code, uint32_t flags, const uint8_t *data, size_t data_size,
                    const uint64_t *offsets, size_t n_offsets, husk_binder_reply *reply, void *cookie)
{
    (void)code; (void)flags; (void)data; (void)data_size; (void)offsets; (void)n_offsets; (void)cookie;
    /* Unsupported framework transactions must not look like successful AMS,
     * account, permission or graphics service replies. Parcel EX_UNSUPPORTED_OPERATION. */
    size_t n = 8;
    uint8_t *buf = calloc(1, n);
    if (!buf) return;
    int32_t unsupported = -7;
    memcpy(buf, &unsupported, sizeof(unsupported));
    reply->data = buf;
    reply->data_size = n;
}

static void add_svc(const char *name)
{
    uint32_t h = husk_binder_add_local(svc_txn, (void *)name);
    if (h) husk_sm_add(name, h);
}

void husk_aosp_start_system(void)
{
    husk_sm_start();
    static const char *const names[] = {
        "activity", "activity_task", "package", "window", "display", "input",
        "input_method", "alarm", "power", "batterystats", "clipboard",
        "notification", "connectivity", "wifi", "audio", "sensorservice",
        "SurfaceFlinger", "permission", "permissionmgr", "mount", "user",
        "account", "device_policy", "lock_settings", "graphicsstats",
        "appops", "jobscheduler", "location", "phone", "telecom",
        "content", "settings", "deviceidle", "vibrator", "uimode",
        "usagestats", "backup", "media.audio_flinger", "media.player",
        NULL
    };
    for (int i = 0; names[i]; i++) add_svc(names[i]);
    tl_log_line("aosp: service names registered; framework transactions are unsupported");
}
