/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Scanner-only export. Runtime/lifecycle evidence uses NativeBootstrap's real DEX and ELF. */
void ANativeActivity_onCreate(void *activity, void *saved, unsigned long length)
{ (void)activity; (void)saved; (void)length; }
