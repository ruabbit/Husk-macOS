/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Explicit real-APK probe with isolated data, offscreen rendering and muted
 * output. Uses the production driver while the candidate UI stays untouched. */
#import <Foundation/Foundation.h>
#include "husk-tl-nativeactivity.h"
#include "husk-tl-audio.h"
#include "husk-tl-bionic.h"
#include "husk-tl-jni.h"
#include "husk-tl-ld.h"
#include "husk-tl-egl.h"
#include "MacDiagnostics.h"
#include <stdatomic.h>
#include <unistd.h>
static atomic_int result = -1;
static void guest_exit(int status) { tl_log_line("probe: guest exited with %d",status); _exit(70); }
static bool wait_state(tl_na_state state, int seconds) {
    for(int i=0;i<seconds*100;i++) {
        if(tl_na_get_state()==state)return true;
        if(tl_na_get_state()==TL_NA_FAILED)return false;
        usleep(10000);
    }
    return false;
}
int main(int argc, char **argv) { @autoreleasepool {
    if(argc<9 || argc>40) { fprintf(stderr,"usage: NativeActivityProbe DATA ANGLE FRAMES PACKAGE LIBRARY SECONDS PORTRAIT BASE [SPLITS...]\n");return 64; }
    int seconds=atoi(argv[6]);if(seconds<1||seconds>60)return 64;
    mac_runtime_diagnostics_install();tl_guest_exit_hook=guest_exit;
    setenv("TL_XMEM_MIB","1024",1);setenv("TL_GAME_DIAGNOSTICS","1",1);
    tl_ld_set_verbosity(2);tl_jni_set_trace(1);tl_audio_set_muted(true);tl_audio_install();
    tl_egl_offscreen_windows(true);
    for(int i=9;i<argc;i++)tl_ld_queue_split(argv[i]);
    BOOL portrait=atoi(argv[7])!=0;
    tl_ga_config cfg={.apk_path=argv[8],.data_dir=argv[1],.package_name=argv[4],
        .width=portrait?720:1280,.height=portrait?1280:720,.angle_egl=argv[2],.frame_dir=argv[3],.frame_every=-60};
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{ @autoreleasepool {
        tl_na_set_library(argv[5]);
        if(!tl_na_start(&cfg)||!tl_na_run()) { tl_log_line("probe: native load failed");atomic_store(&result,70);return; }
        if(!wait_state(TL_NA_RUNNING,30)) { tl_log_line("probe: no running activity");atomic_store(&result,71);return; }
        for(int i=0;i<seconds;i++){sleep(1);tl_log_line("probe: second=%d state=%d frames=%lu",i+1,tl_na_get_state(),tl_na_frames());}
        BOOL frames=tl_na_frames()>0;
        tl_na_set_paused(true);BOOL paused=wait_state(TL_NA_PAUSED,5);
        tl_na_set_paused(false);BOOL resumed=wait_state(TL_NA_RUNNING,5);
        tl_na_stop();BOOL destroyed=tl_na_get_state()==TL_NA_DESTROYED;
        tl_log_line("probe: frames=%d pause=%d resume=%d destroyed=%d",frames,paused,resumed,destroyed);
        atomic_store(&result,frames&&paused&&resumed&&destroyed?0:72);
    }});
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:seconds+90];
    while(atomic_load(&result)<0&&deadline.timeIntervalSinceNow>0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
    int status=atomic_load(&result);
    if(status<0){tl_log_line("probe: deadline exceeded");status=124;}
    return status;
} }
