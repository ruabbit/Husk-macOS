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

#define PING_TRANSACTION 0x5f504e47u
#define INTERFACE_TRANSACTION 0x5f4e5446u
static bool g_using;
static char g_pkg[200];
static int g_width = 1080, g_height = 1920;

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

void husk_aosp_set_session(const char *package, int width, int height)
{
    if (package && package[0]) snprintf(g_pkg, sizeof(g_pkg), "%s", package);
    if (width > 0) g_width = width;
    if (height > 0) g_height = height;
}


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
        static const char *const names[] = { "framework.jar", "framework-graphics.jar", "ext.jar", "telephony-common.jar", "voip-common.jar", "ims-common.jar", "services.jar", "framework-connectivity.jar", "tethering.jar" };
        for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); ++i) {
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

static const char *iface_for(const char *name)
{
    if (!name) return "android.os.IBinder";
    if (!strcmp(name, "activity")) return "android.app.IActivityManager";
    if (!strcmp(name, "activity_task")) return "android.app.IActivityTaskManager";
    if (!strcmp(name, "package")) return "android.content.pm.IPackageManager";
    if (!strcmp(name, "window")) return "android.view.IWindowManager";
    if (!strcmp(name, "display")) return "android.hardware.display.IDisplayManager";
    if (!strcmp(name, "input")) return "android.hardware.input.IInputManager";
    if (!strcmp(name, "input_method")) return "com.android.internal.view.IInputMethodManager";
    if (!strcmp(name, "alarm")) return "android.app.IAlarmManager";
    if (!strcmp(name, "power")) return "android.os.IPowerManager";
    if (!strcmp(name, "clipboard")) return "android.content.IClipboard";
    if (!strcmp(name, "notification")) return "android.app.INotificationManager";
    if (!strcmp(name, "connectivity")) return "android.net.IConnectivityManager";
    if (!strcmp(name, "wifi")) return "android.net.wifi.IWifiManager";
    if (!strcmp(name, "audio")) return "android.media.IAudioService";
    if (!strcmp(name, "sensorservice")) return "android.gui.SensorServer";
    if (!strcmp(name, "SurfaceFlinger")) return "android.ui.ISurfaceComposer";
    if (!strcmp(name, "permission") || !strcmp(name, "permissionmgr")) return "android.permission.IPermissionManager";
    if (!strcmp(name, "mount")) return "android.os.storage.IStorageManager";
    if (!strcmp(name, "user")) return "android.os.IUserManager";
    if (!strcmp(name, "account")) return "android.accounts.IAccountManager";
    if (!strcmp(name, "appops")) return "com.android.internal.app.IAppOpsService";
    if (!strcmp(name, "jobscheduler")) return "android.app.job.IJobScheduler";
    if (!strcmp(name, "location")) return "android.location.ILocationManager";
    if (!strcmp(name, "phone")) return "com.android.internal.telephony.ITelephony";
    if (!strcmp(name, "content")) return "android.content.IContentService";
    if (!strcmp(name, "battery")) return "android.os.IBatteryPropertiesRegistrar";
    if (!strcmp(name, "batterystats")) return "com.android.internal.app.IBatteryStats";
    if (!strcmp(name, "vibrator")) return "android.os.IVibratorService";
    if (!strcmp(name, "uimode")) return "android.app.IUiModeManager";
    if (!strcmp(name, "usagestats")) return "android.app.usage.IUsageStatsManager";
    if (!strcmp(name, "deviceidle")) return "android.os.IDeviceIdleController";
    if (!strcmp(name, "media.audio_flinger")) return "android.media.IAudioFlinger";
    if (!strcmp(name, "media.player")) return "android.media.IMediaPlayerService";
    return "android.os.IBinder";
}


static void svc_txn(uint32_t code, uint32_t flags, const uint8_t *data, size_t data_size,
                    const uint64_t *offsets, size_t n_offsets, husk_binder_reply *reply, void *cookie)
{
    (void)flags; (void)data; (void)data_size; (void)offsets; (void)n_offsets;
    if (code == PING_TRANSACTION) return;
    if (code == INTERFACE_TRANSACTION) {
        const char *descriptor = iface_for(cookie);
        int32_t chars = (int32_t)strlen(descriptor);
        size_t bytes = 4 + (((size_t)chars + 1) * 2 + 3) / 4 * 4;
        uint8_t *buf = calloc(1, bytes);
        if (!buf) { reply->data_size = bytes; return; } /* transport rejects allocation failure */
        memcpy(buf, &chars, 4);
        for (int32_t i = 0; i < chars; ++i) {
            uint16_t ch = (unsigned char)descriptor[i]; memcpy(buf + 4 + i * 2, &ch, 2);
        }
        reply->data = buf; reply->data_size = bytes; return;
    }
    /* The service name alone cannot identify a method's reply schema. In
     * particular, never grant every permission or return a Point for every WMS
     * code. Session metadata is retained for future version-pinned handlers. */
    size_t n = 8;
    uint8_t *buf = calloc(1, n);
    if (!buf) { reply->data_size = n; return; }
    int32_t unsupported = -7; /* Parcel EX_UNSUPPORTED_OPERATION */
    memcpy(buf, &unsupported, sizeof(unsupported));
    reply->data = buf; reply->data_size = n;
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
        "input_method", "alarm", "power", "batterystats", "battery", "clipboard",
        "notification", "connectivity", "wifi", "audio", "sensorservice",
        "SurfaceFlinger", "permission", "permissionmgr", "mount", "user",
        "account", "device_policy", "lock_settings", "graphicsstats",
        "appops", "jobscheduler", "location", "phone", "telecom",
        "content", "settings", "deviceidle", "vibrator", "uimode",
        "usagestats", "backup", "media.audio_flinger", "media.player",
        "media.camera", "webviewupdate", "package_native", "overlay",
        "statusbar", "accessibility", "wallpaper", "search", "country_detector",
        "network_management", "netpolicy", "storagestats", "usb", "serial",
        NULL
    };
    for (int i = 0; names[i]; i++) add_svc(names[i]);
    tl_log_line("aosp: service descriptors and PING ready; framework method transactions are unsupported");
}
