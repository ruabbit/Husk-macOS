/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-dvm-boot.h"
#include "husk-tl-dvm-javaapp.h"
#include "husk-tl-dvm.h"
#include "husk-tl-egl.h"
#include "MacDiagnostics.h"
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static char **args;
static int failed;
#define CHECK(c) do { if (!(c)) { fprintf(stderr,"FAIL KeyStore line %d: %s\n",__LINE__,#c); failed=1; return NULL; } } while(0)
static void *run(void *unused) {
    (void)unused; mac_runtime_diagnostics_install();
    setenv("TL_AUDIO_MUTE", "1", 1); setenv("HUSK_KEYSTORE_PHASE", args[5], 1);
    CHECK(tl_dvm_boot(args[1], args[4])); tl_egl_offscreen_windows(true);
    char framework[1200]; snprintf(framework,sizeof(framework),"%s/framework-res.apk",args[1]);
    tl_javaapp_config config = {.apk_path=args[2], .data_dir=args[4], .package_name="org.husk.keystore",
        .width=32,.height=32,.density=1,.angle_egl=args[3],.framework_res=framework,.frame_every=-1};
    CHECK(tl_javaapp_start(&config));
    for(int i=0;i<10000 && tl_javaapp_get_state()!=TL_JAVA_RUNNING && tl_javaapp_get_state()!=TL_JAVA_FAILED;i++) usleep(1000);
    CHECK(tl_javaapp_get_state()==TL_JAVA_RUNNING);
    jvalue result={0};
    bool called=tl_dvm_call_static("org/husk/keystore/KeyStoreActivity","result","()I",NULL,&result);
    CHECK(tl_javaapp_stop()); // Always collect lifecycle closure before reporting a test assertion.
    CHECK(called && result.i==1);
    printf("PASS KeyStore %s: real DEX/provider and confirmed Java close\n",args[5]); return NULL;
}
int main(int argc,char **argv) {
    if(argc!=6)return 64; args=argv;
    pthread_attr_t attr;pthread_attr_init(&attr);pthread_attr_setstacksize(&attr,256u<<20);
    pthread_t t;if(pthread_create(&t,&attr,run,NULL))return 1;
    pthread_attr_destroy(&attr);pthread_join(t,NULL);return failed;
}
