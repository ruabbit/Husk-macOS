/* SPDX-License-Identifier: GPL-2.0-or-later */
#include <stdbool.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
extern void *mac_graphics_symbol(const char *name);
void tl_log_line(const char *format, ...)
{ va_list args;va_start(args,format);vfprintf(stderr,format,args);fputc('\n',stderr);va_end(args); }
void *tl_bionic_find(const char *name)
{
    const char *allowed[]={"glClearColor","glClear","glEnable","glDisable","glScissor"};
    for(unsigned i=0;i<sizeof(allowed)/sizeof(allowed[0]);i++)if(!strcmp(name,allowed[i]))return mac_graphics_symbol(name);
    if(!strcmp(name,"memcpy"))return memcpy;
    if(!strcmp(name,"memmove"))return memmove;
    if(!strcmp(name,"memset"))return memset;
    return NULL;
}
bool tl_bionic_is_system_lib(const char *name) {(void)name;return false;}
long tl_linux_syscall(long a,long b,long c,long d,long e,long f,long nr)
{(void)a;(void)b;(void)c;(void)d;(void)e;(void)f;(void)nr;return -38;}
