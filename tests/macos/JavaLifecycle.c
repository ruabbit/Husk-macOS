/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-dvm-boot.h"
#include "husk-tl-dvm-javaapp.h"
#include "husk-tl-dvm.h"
#include "husk-tl-egl.h"
#include "husk-tl-gamepad.h"
#include "MacDiagnostics.h"
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <sqlite3.h>

static char **args;
static int failed;
#define CHECK(c) do { if (!(c)) { fprintf(stderr,"FAIL Java lifecycle line %d: %s (state %d)\n",__LINE__,#c,tl_javaapp_get_state()); failed=1; return NULL; } } while(0)
static bool wait_state(tl_javaapp_state state) {
    for(int i=0;i<5000;i++) { if(tl_javaapp_get_state()==state)return true;if(tl_javaapp_get_state()==TL_JAVA_FAILED)return false;usleep(1000); } return false;
}
static int controller_result(void) {
    jvalue result;
    return tl_dvm_call_static("org/husk/lifecycle/LifecycleActivity","controllerResult","()I",NULL,&result)?result.i:-1;
}
static bool wait_controller(int bits) {
    for(int i=0;i<3000;i++){int value=controller_result();if(value<0)return false;if((value&bits)==bits)return true;usleep(1000);}return false;
}
static void *run(void *unused)
{
    (void)unused;mac_runtime_diagnostics_install();
    char data[1200],fw[1200],frames[1200];
    snprintf(data,sizeof(data),"%s/run-XXXXXX",args[4]);CHECK(mkdtemp(data));
    snprintf(fw,sizeof(fw),"%s/framework-res.apk",args[1]);snprintf(frames,sizeof(frames),"%s/frames",data);mkdir(frames,0700);
    setenv("TL_AUDIO_MUTE","1",1);setenv("HUSK_JAVA_CASE",args[5],1);
    if(!strcmp(args[5],"storage-failed")) { char p[1400];snprintf(p,sizeof(p),"%s/shared_prefs",data);FILE *f=fopen(p,"w");CHECK(f);fclose(f); }
    CHECK(tl_dvm_boot(args[1],data));
    tl_egl_offscreen_windows(true);
    tl_javaapp_config config={.apk_path=args[2],.data_dir=data,.package_name="org.husk.lifecycle",.width=320,.height=240,
        .density=1,.angle_egl=args[3],.framework_res=fw,.frame_dir=frames,.frame_every=-1};
    CHECK(tl_javaapp_start(&config));CHECK(wait_state(TL_JAVA_RUNNING));
    for(int i=0;i<3000&&!tl_javaapp_frames();i++)usleep(1000);
    CHECK(tl_javaapp_frames()>0);
    tl_javaapp_touch(0,0,80,180);tl_javaapp_touch(2,0,80,180);tl_javaapp_key(29,true);tl_javaapp_key(29,false);
    bool controller=!strcmp(args[5],"controller");
    if(controller){
        tl_pad_connect(0,"Fixture One");tl_pad_connect(1,"Fixture Two");CHECK(wait_controller(64));
        tl_pad_state first={.buttons=(1<<TL_PAD_A)|(1<<TL_PAD_DPAD_RIGHT),.lx=.25f,.ly=-.5f,.rx=.75f,.ry=-.25f,.lt=.8f,.rt=.6f};
        tl_pad_update(0,&first);CHECK(wait_controller(5));
        tl_pad_state second={.buttons=1<<TL_PAD_B};tl_pad_update(1,&second);CHECK(wait_controller(16));
        tl_pad_disconnect(1);CHECK(wait_controller(32|128));
    }
    tl_javaapp_set_paused(true);CHECK(tl_javaapp_get_state()==TL_JAVA_RUNNING);CHECK(wait_state(TL_JAVA_PAUSED));
    if(controller){
        CHECK(controller_result()==255);
        tl_pad_state forbidden={.buttons=1<<TL_PAD_X};tl_pad_update(0,&forbidden);usleep(50000);CHECK(controller_result()==255);
    }
    tl_javaapp_set_paused(false);CHECK(wait_state(TL_JAVA_RUNNING));
    if(controller){
        tl_pad_state held={.buttons=1<<TL_PAD_A};tl_pad_update(0,&held);
        jvalue result={0};
        for(int i=0;i<3000;i++){
            CHECK(tl_dvm_call_static("org/husk/lifecycle/LifecycleActivity","controllerHeld","()I",NULL,&result));
            if(result.i==1)break;usleep(1000);
        }
        CHECK(result.i==1);
    }
    bool ok=tl_javaapp_stop(), success=!strcmp(args[5],"normal")||!strcmp(args[5],"preferences-idle")||controller;
    CHECK(ok==success);CHECK(tl_javaapp_get_state()==(success?TL_JAVA_DESTROYED:TL_JAVA_FAILED));
    if(success){
        if(controller)CHECK(controller_result()==255);
        jvalue result;CHECK(tl_dvm_call_static("org/husk/lifecycle/LifecycleActivity","result","()I",NULL,&result));CHECK(result.i==63);
        char p[1400],text[512]={0};snprintf(p,sizeof(p),"%s/shared_prefs/lifecycle.xml",data);FILE *f=fopen(p,"r");CHECK(f);fread(text,1,sizeof(text)-1,f);fclose(f);CHECK(strstr(text,"i destroyed 1"));
        snprintf(p,sizeof(p),"%s/files/lifecycle.db",data);sqlite3 *db=NULL;sqlite3_stmt *st=NULL;
        CHECK(sqlite3_open_v2(p,&db,SQLITE_OPEN_READONLY,NULL)==SQLITE_OK);
        CHECK(sqlite3_prepare_v2(db,"SELECT sum(value) FROM lifecycle",-1,&st,NULL)==SQLITE_OK);
        CHECK(sqlite3_step(st)==SQLITE_ROW&&sqlite3_column_int(st,0)==1);sqlite3_finalize(st);CHECK(sqlite3_close(db)==SQLITE_OK);
    }
    printf("PASS Java lifecycle %s: real DEX callbacks, frame, input and close outcome; data %s\n",args[5],data);
    return NULL;
}
int main(int argc,char **argv)
{
    if(argc!=6)return 64;
    args=argv;mkdir(argv[4],0700);
    pthread_attr_t attr;pthread_attr_init(&attr);pthread_attr_setstacksize(&attr,256u<<20);
    pthread_t t;if(pthread_create(&t,&attr,run,NULL))return 1;
    pthread_attr_destroy(&attr);pthread_join(t,NULL);return failed;
}
