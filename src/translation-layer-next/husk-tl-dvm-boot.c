/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-dvm-boot.h"
#include "husk-tl-dvm.h"
#include "husk-tl-jni.h"
#include "husk-tl-ld.h"
#include "husk-tl-aosp.h"
#include "husk-tl-servicemanager.h"
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

bool tl_dvm_boot(const char *root, const char *data)
{
    /* Complete checked boot path: never silently omit a required jar. Mac's
     * resource verifier admits only manifest-listed files before reaching here. */
    char paths[20][1200], value[1200]; const char *boot[20];
    if (!root || !data) return false;
    int count = husk_aosp_boot_jars(root, paths, 20, boot);
    if (count < 0) return false;
    static const char *modules[] = {"art", "i18n", "tzdata"};
    static const char *vars[] = {"ANDROID_ART_ROOT", "ANDROID_I18N_ROOT", "ANDROID_TZDATA_ROOT"};
    for (int i = 0; i < 3; ++i) {
        if (snprintf(value, sizeof(value), "%s/com.android.%s", root, modules[i]) >= (int)sizeof(value) || setenv(vars[i], value, 1)) return false;
    }
    if (setenv("ANDROID_ROOT", data, 1) || setenv("ANDROID_DATA", data, 1)) return false;
    tl_jni_init();
    husk_sm_start();
    if (husk_aosp_using()) husk_aosp_start_system();
    if (!tl_dvm_start(boot, count)) return false;
    snprintf(value, sizeof(value), "%s/com.android.i18n/lib64", root); tl_ld_add_search_dir(value);
    snprintf(value, sizeof(value), "%s/com.android.conscrypt/lib64", root); tl_ld_add_search_dir(value);
    snprintf(value, sizeof(value), "%s/com.android.art/lib64", root);
    return tl_dvm_load_natives(value);
}
