/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-dvm-boot.h"
#include "husk-tl-dvm.h"
#include "husk-tl-jni.h"
#include "husk-tl-ld.h"
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include "MacDiagnostics.h"

static char **arguments;
static int failure;
static int argument_count;
#define CHECK(c) do { if (!(c)) { fprintf(stderr,"FAIL Java boot line %d: %s\n",__LINE__,#c); failure=1; return NULL; } } while(0)
static void *run(void *unused)
{
    (void)unused;
    mac_runtime_diagnostics_install();
    mkdir(arguments[2],0700);
    bool collision = argument_count == 5;
    tl_lib *app_crypto = NULL;
    if (collision) {
        CHECK(tl_ld_add_apk(arguments[3]));
        if (!strcmp(arguments[4],"app-first")) {
            app_crypto = tl_ld_load("libcrypto.so"); CHECK(app_crypto && tl_ld_init(app_crypto));
        }
    }
    CHECK(tl_dvm_boot(arguments[1], arguments[2]));
    jvalue a={.l=tl_jni_new_string("123456")}, result;
    CHECK(tl_dvm_call_static("java/lang/Integer","parseInt","(Ljava/lang/String;)I",&a,&result) && result.i==123456);
    CHECK(tl_dvm_call_static("java/util/TimeZone","getDefault","()Ljava/util/TimeZone;",NULL,&result) && result.l);
    CHECK(tl_dvm_call_static("javax/net/ssl/SSLContext","getDefault","()Ljavax/net/ssl/SSLContext;",NULL,&result) && result.l);
    if (collision) {
        tl_lib *library = tl_ld_load("libcrypto.so"); CHECK(library && (!app_crypto || library == app_crypto));
        int (*origin)(void) = tl_ld_sym(library,"namespace_origin"); CHECK(origin && origin() == 11);
        CHECK(tl_dvm_call_static("javax/net/ssl/SSLContext","getDefault","()Ljavax/net/ssl/SSLContext;",NULL,&result) && result.l);
        puts("PASS real Conscrypt remains usable with the app's conflicting libcrypto.so");
    }
    a.l=tl_jni_new_string("husk.AppRunner");
    CHECK(tl_dvm_call_static("java/lang/Class","forName","(Ljava/lang/String;)Ljava/lang/Class;",&a,&result) && result.l);
    /* Unity resolves this on InputEvent, before it knows whether the incoming
       object is a MotionEvent or KeyEvent. A method only on a subclass fails. */
    void *env=tl_jni_env(); const void **jni=*(const void ***)env;
    void *(*method)(void *,void *,const char *,const char *)=(void *)jni[33];
    void *(*call_object)(void *,void *,void *,const jvalue *)=(void *)jni[36];
    int (*call_int)(void *,void *,void *,const jvalue *)=(void *)jni[51];
    void *get_device=method(env,tl_jni_class_object("android/view/InputEvent"),"getDevice","()Landroid/view/InputDevice;");
    CHECK(get_device && !tl_jni_pending());
    jvalue touch[]={{.j=100},{.j=110},{.i=0},{.f=80},{.f=180},{.i=0}};
    CHECK(tl_dvm_call_static("android/view/MotionEvent","obtain","(JJIFFI)Landroid/view/MotionEvent;",touch,&result) && result.l);
    void *device=call_object(env,result.l,get_device,NULL); CHECK(device && !tl_jni_pending());
    void *get_id=method(env,tl_jni_class_object("android/view/InputDevice"),"getId","()I");
    CHECK(get_id && call_int(env,device,get_id,NULL)==1);
    CHECK(!tl_jni_pending());
    puts("PASS real Dalvik boot, libcore, ICU/time zones, Conscrypt, framework and InputEvent JNI dispatch");
    return NULL;
}
int main(int argc,char **argv)
{
    if(argc!=3&&argc!=5)return 64;
    arguments=argv;argument_count=argc;
    pthread_attr_t attr;pthread_attr_init(&attr);pthread_attr_setstacksize(&attr,256u<<20);
    pthread_t thread;
    if(pthread_create(&thread,&attr,run,NULL))return 1;
    pthread_attr_destroy(&attr);pthread_join(thread,NULL);
    return failure;
}
