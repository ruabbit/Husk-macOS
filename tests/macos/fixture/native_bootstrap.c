/* SPDX-License-Identifier: GPL-2.0-or-later */
static int ready;
int bootstrap_ready(void) { return ready; }
int JNI_OnLoad(void *vm, void *reserved) { (void)reserved; ready = vm != 0; return 0x10006; }
