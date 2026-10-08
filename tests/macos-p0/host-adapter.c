/* SPDX-License-Identifier: GPL-2.0-or-later */
#include <stdbool.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
void tl_log_line(const char *fmt, ...)
{
    va_list ap; va_start(ap, fmt);
    vfprintf(stderr, fmt, ap); fputc('\n', stderr); va_end(ap);
}
static int p0_import(int value) { return value * 2; }
void *tl_bionic_find(const char *name)
{ return !strcmp(name, "p0_import") ? (void *)p0_import : NULL; }
bool tl_bionic_is_system_lib(const char *name) { (void)name; return false; }
/* The standalone loader fixture uses host paths, without Android remapping. */
const char *tl_path_resolve(const char *path, char *buffer, size_t capacity)
{ (void)buffer; (void)capacity; return path; }
/* This fixture has no syscalls. Fail closed if one appears. */
long tl_linux_syscall(long a, long b, long c, long d, long e, long f, long nr)
{ (void)a; (void)b; (void)c; (void)d; (void)e; (void)f; (void)nr; return -38; }
