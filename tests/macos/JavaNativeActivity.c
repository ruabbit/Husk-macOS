/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-dvm-boot.h"
#include "husk-tl-dvm-javaapp.h"
#include "husk-tl-dvm.h"
#include "husk-tl-egl.h"
#include "husk-tl-ld.h"
#include "husk-tl-gamepad.h"
#include "MacDiagnostics.h"
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
static char **args; static int failed;
#define CHECK(c) do { if (!(c)) { fprintf(stderr,"FAIL Java NativeActivity line %d: %s state=%d\n",__LINE__,#c,tl_javaapp_get_state()); failed=1; return NULL; } } while(0)
static bool wait_state(tl_javaapp_state s) { for(int i=0;i<5000;i++){if(tl_javaapp_get_state()==s)return true;if(tl_javaapp_get_state()==TL_JAVA_FAILED)return false;usleep(1000);}return false; }
static int result(void) { jvalue r={0};return tl_dvm_call_static("org/husk/nativeboot/Game","result","()I",NULL,&r)?r.i:-1; }
static void *run(void *unused) {
    (void)unused;mac_runtime_diagnostics_install();
    char data[1400],fw[1400];snprintf(data,sizeof(data),"%s/run-XXXXXX",args[5]);CHECK(mkdtemp(data));
    snprintf(fw,sizeof(fw),"%s/framework-res.apk",args[1]);setenv("HUSK_NATIVE_ACTIVITY_CASE",args[6],1);
    CHECK(tl_dvm_boot(args[1],data));tl_ld_queue_split(args[3]);tl_egl_offscreen_windows(true);
    tl_javaapp_config cfg={.apk_path=args[2],.data_dir=data,.width=320,.height=240,.density=1,.angle_egl=args[4],.framework_res=fw};
    CHECK(tl_javaapp_start(&cfg));
    bool create_failed=strstr(args[6],"create-failed")!=NULL;
    if(create_failed){
        for(int i=0;i<5000&&tl_javaapp_get_state()!=TL_JAVA_FAILED;i++)usleep(1000);
        CHECK(tl_javaapp_get_state()==TL_JAVA_FAILED);CHECK(!tl_javaapp_stop());CHECK(result()==135);
        printf("PASS Java NativeActivity %s: same-thread native cleanup, no started lifecycle or close receipt\n",args[6]);return NULL;
    }
    CHECK(wait_state(TL_JAVA_RUNNING));
    for(int i=0;i<3000&&(result()&4096)==0;i++)usleep(1000);
    CHECK((result()&4096)!=0);
    tl_javaapp_touch(0,0,30,40);tl_javaapp_touch(2,0,30,40);tl_javaapp_key(29,true);tl_javaapp_key(29,false);
    tl_pad_connect(0,"NativeActivity fixture");tl_pad_state pad={.buttons=1u<<TL_PAD_A,.lx=.5f};tl_pad_update(0,&pad);
    for(int i=0;i<3000&&(result()&245760)!=245760;i++)usleep(1000);
    CHECK((result()&245760)==245760);
    tl_javaapp_set_paused(true);CHECK(wait_state(TL_JAVA_PAUSED));tl_javaapp_set_paused(false);CHECK(wait_state(TL_JAVA_RUNNING));
    if(!strcmp(args[6],"guest-finish")){
        jvalue r;CHECK(tl_dvm_call_static("org/husk/nativeboot/Game","finishNative","()V",NULL,&r));
        CHECK(wait_state(TL_JAVA_STOPPING));
    }
    bool success=strcmp(args[6],"missing-destroy")!=0;
    CHECK(tl_javaapp_stop()==success);CHECK(tl_javaapp_get_state()==(success?TL_JAVA_DESTROYED:TL_JAVA_FAILED));
    CHECK(result()==(success?262143:262015));
    if(success){char path[1500],text[500]={0};snprintf(path,sizeof(path),"%s/shared_prefs/nativeboot.xml",data);FILE *f=fopen(path,"r");CHECK(f);fread(text,1,sizeof(text)-1,f);fclose(f);CHECK(strstr(text,"i destroyed 1"));}
    printf("PASS Java NativeActivity %s: Application/loader/provider/JNI/ELF order, actual activity, input, lifecycle and save\n",args[6]);return NULL;
}
int main(int argc,char **argv){if(argc!=7)return 64;args=argv;mkdir(argv[5],0700);pthread_attr_t a;pthread_attr_init(&a);pthread_attr_setstacksize(&a,256u<<20);pthread_t t;if(pthread_create(&t,&a,run,NULL))return 1;pthread_attr_destroy(&a);pthread_join(t,NULL);return failed;}
