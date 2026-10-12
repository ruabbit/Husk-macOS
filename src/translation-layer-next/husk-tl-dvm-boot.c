/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-dvm-boot.h"
#include "husk-tl-dvm.h"
#include "husk-tl-jni.h"
#include "husk-tl-ld.h"
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

bool tl_dvm_boot(const char *root, const char *data)
{
    /* Keep the same order as the iOS Java host and java-runtime.lock.json. */
    static const char *names[] = {
        "com.android.art/javalib/core-oj.jar", "com.android.art/javalib/core-libart.jar",
        "com.android.art/javalib/okhttp.jar", "com.android.art/javalib/bouncycastle.jar",
        "com.android.art/javalib/apache-xml.jar", "com.android.i18n/javalib/core-icu4j.jar",
        "com.android.conscrypt/javalib/conscrypt.jar", "husk-framework.dex", "org.apache.http.legacy.jar"
    };
    char paths[9][1200], value[1200]; const char *boot[9];
    if (!root || !data) return false;
    for (int i = 0; i < 9; ++i) {
        if (snprintf(paths[i], sizeof(paths[i]), "%s/%s", root, names[i]) >= (int)sizeof(paths[i]) || access(paths[i], R_OK)) return false;
        boot[i] = paths[i];
    }
    static const char *modules[] = {"art", "i18n", "tzdata"};
    static const char *vars[] = {"ANDROID_ART_ROOT", "ANDROID_I18N_ROOT", "ANDROID_TZDATA_ROOT"};
    for (int i = 0; i < 3; ++i) {
        if (snprintf(value, sizeof(value), "%s/com.android.%s", root, modules[i]) >= (int)sizeof(value) || setenv(vars[i], value, 1)) return false;
    }
    if (setenv("ANDROID_ROOT", data, 1) || setenv("ANDROID_DATA", data, 1)) return false;
    tl_jni_init();
    if (!tl_dvm_start(boot, 9)) return false;
    snprintf(value, sizeof(value), "%s/com.android.i18n/lib64", root); tl_ld_add_search_dir(value);
    snprintf(value, sizeof(value), "%s/com.android.conscrypt/lib64", root); tl_ld_add_search_dir(value);
    snprintf(value, sizeof(value), "%s/com.android.art/lib64", root);
    return tl_dvm_load_natives(value);
}
