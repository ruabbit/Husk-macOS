/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-bionic.h"
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
void tl_log_line(const char *format,...) {(void)format;}
extern void (*tl_cocos_audio_hook)(const int16_t *,int,int,int);
static atomic_int calls;
static void discard(const int16_t *p,int frames,int channels,int rate){(void)p;(void)frames;(void)channels;(void)rate;}
static int callback(void *s,void *u,void *data,int frames)
{(void)s;(void)u;(void)data;(void)frames;atomic_fetch_add(&calls,1);return 1;}
#define CHECK(x) do{if(!(x)){fprintf(stderr,"AAudio lifecycle check failed: %s\n",#x);return 1;}}while(0)
int main(void)
{
    int (*builder)(void **)=tl_bionic_find("AAudio_createStreamBuilder");
    void (*set_callback)(void *,void *,void *)=tl_bionic_find("AAudioStreamBuilder_setDataCallback");
    int (*open_stream)(void *,void **)=tl_bionic_find("AAudioStreamBuilder_openStream");
    int (*delete_builder)(void *)=tl_bionic_find("AAudioStreamBuilder_delete");
    int (*start)(void *)=tl_bionic_find("AAudioStream_requestStart");
    int (*state)(void *)=tl_bionic_find("AAudioStream_getState");
    int (*close_stream)(void *)=tl_bionic_find("AAudioStream_close");
    int (*rate)(void *)=tl_bionic_find("AAudioStream_getSampleRate");
    int (*channels)(void *)=tl_bionic_find("AAudioStream_getChannelCount");
    CHECK(builder&&set_callback&&open_stream&&delete_builder&&start&&state&&close_stream);
    tl_cocos_audio_hook=discard;
    void *b,*s;CHECK(builder(&b)==0);
    /* FMOD probes output configuration without installing a data callback. */
    CHECK(open_stream(b,&s)==0);CHECK(state(s)==2);CHECK(rate(s)==48000);CHECK(channels(s)==2);
    CHECK(start(s)==-899);CHECK(close_stream(s)==0);
    set_callback(b,callback,NULL);CHECK(open_stream(b,&s)==0);delete_builder(b);
    for(int i=1;i<=3;++i){
        CHECK(start(s)==0);
        for(int retry=0;retry<1000&&state(s)!=10;++retry)usleep(1000);
        CHECK(state(s)==10);CHECK(atomic_load(&calls)==i);
    }
    CHECK(close_stream(s)==0);
    puts("PASS AAudio configuration probe, callback STOP, restart, reap and close");return 0;
}
