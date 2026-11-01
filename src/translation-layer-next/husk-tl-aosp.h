/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef HUSK_TL_AOSP_H
#define HUSK_TL_AOSP_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Optional AOSP userland next to the bundled java-runtime (framework.jar, not
 * copied into Husk's sources). When present it is on the boot path *after*
 * husk-framework-core.dex. Missing required jars fail; this is not a working
 * Android system_server. The Mac product retains its pinned full framework.
 */
bool husk_aosp_present(const char *java_root);
/* Complete ordered boot path, or -1 for missing resources/capacity. */
int husk_aosp_boot_jars(const char *java_root, char (*paths)[1200], int max, const char **boot);
void husk_aosp_start_system(void);
bool husk_aosp_using(void);
const char *husk_aosp_framework_path(const char *java_root, char *out, int cap);
/* Session metadata for future version-pinned AOSP method handlers. */
void husk_aosp_set_session(const char *package, int width, int height);

#ifdef __cplusplus
}
#endif

#endif
