/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef HUSK_TL_DVM_NATIVEACTIVITY_H
#define HUSK_TL_DVM_NATIVEACTIVITY_H
#include "husk-tl-dvm-internal.h"
dvm_native_fn tl_dvm_nativeactivity_native(const char *name, const char *sig);
void tl_dvm_nativeactivity_poll(void);
void tl_dvm_nativeactivity_abort(void);
bool tl_dvm_nativeactivity_closed(void);
#endif
