/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-ld.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
void tl_log_line(const char *format, ...) { (void)format; }
int main(int argc,char **argv) {
    assert(argc==2);char base[1024],split[1024];
    snprintf(base,sizeof(base),"%s/base-v1.apk",argv[1]);
    for(int i=0;i<6;i++){snprintf(split,sizeof(split),"%s/split%d-v1.apk",argv[1],i);tl_ld_queue_split(split);}
    assert(tl_ld_add_apk(base));
    for(int i=0;i<7;i++)assert(tl_ld_apk_at(i));
    assert(!tl_ld_apk_at(7));
    assert(tl_ld_queued_split(5));
    puts("Native loader retains all seven APKs, including splits beyond the old limit");return 0;
}
