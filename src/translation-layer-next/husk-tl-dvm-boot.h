/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef HUSK_TL_DVM_BOOT_H
#define HUSK_TL_DVM_BOOT_H
#include <stdbool.h>
/* One isolated process per app. Call on a thread with at least a 64 MiB stack. */
bool tl_dvm_boot(const char *runtime_root, const char *data_dir);
#endif
