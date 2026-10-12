/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-dvm-boot.h"
#include "husk-tl-dvm.h"
#include "husk-tl-jni.h"
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include "MacDiagnostics.h"

static char **arguments;
static int failure;
#define CHECK(c) do { if (!(c)) { fprintf(stderr,"FAIL Java boot line %d: %s\n",__LINE__,#c); failure=1; return NULL; } } while(0)
static void *run(void *unused)
{
    (void)unused;
    mac_runtime_diagnostics_install();
    mkdir(arguments[2],0700);
    CHECK(tl_dvm_boot(arguments[1], arguments[2]));
    jvalue a={.l=tl_jni_new_string("123456")}, result;
    CHECK(tl_dvm_call_static("java/lang/Integer","parseInt","(Ljava/lang/String;)I",&a,&result) && result.i==123456);
    CHECK(tl_dvm_call_static("java/util/TimeZone","getDefault","()Ljava/util/TimeZone;",NULL,&result) && result.l);
    CHECK(tl_dvm_call_static("javax/net/ssl/SSLContext","getDefault","()Ljavax/net/ssl/SSLContext;",NULL,&result) && result.l);
    a.l=tl_jni_new_string("husk.AppRunner");
    CHECK(tl_dvm_call_static("java/lang/Class","forName","(Ljava/lang/String;)Ljava/lang/Class;",&a,&result) && result.l);
    CHECK(!tl_jni_pending());
    puts("PASS real Dalvik boot, libcore, ICU/time zones, Conscrypt and source-built framework");
    return NULL;
}
int main(int argc,char **argv)
{
    if(argc!=3)return 64;
    arguments=argv;
    pthread_attr_t attr;pthread_attr_init(&attr);pthread_attr_setstacksize(&attr,256u<<20);
    pthread_t thread;
    if(pthread_create(&thread,&attr,run,NULL))return 1;
    pthread_attr_destroy(&attr);pthread_join(thread,NULL);
    return failure;
}
