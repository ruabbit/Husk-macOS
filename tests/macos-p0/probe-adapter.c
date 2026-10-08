/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-internal.h"
/* Parser regression host: macOS has no iOS StikDebug prewarmed region. */
tl_dual_mapping *tl_find_stikdebug_prewarmed(void) { return NULL; }
