/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-bionic.h"
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
void tl_log_line(const char *format,...) {(void)format;}
extern void (*tl_cocos_audio_hook)(const int16_t *,int,int,int);
static atomic_int calls, delivered, invalid;
static int expected_frames;
static void discard(const int16_t *p,int frames,int channels,int rate){
    if(expected_frames && (frames!=expected_frames || channels!=2 || rate!=48000 ||
       p[0]!=16383 || p[1]!=-16383 || p[frames*2-2]!=16383 || p[frames*2-1]!=-16383))
        atomic_store(&invalid,1);
    atomic_fetch_add(&delivered,frames);
}
static int callback(void *s,void *u,void *data,int frames)
{(void)s;(void)u;(void)data;(void)frames;atomic_fetch_add(&calls,1);return 1;}
static int float_callback(void *s,void *u,void *data,int frames) {
    (void)s;(void)u;
    float *out=data;
    for(int i=0;i<frames;i++){out[i*2]=0.5f;out[i*2+1]=-0.5f;}
    atomic_fetch_add(&calls,1);return 1;
}
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
    void (*set_format)(void *,int)=tl_bionic_find("AAudioStreamBuilder_setFormat");
    void (*set_channels)(void *,int)=tl_bionic_find("AAudioStreamBuilder_setChannelCount");
    void (*set_frames)(void *,int)=tl_bionic_find("AAudioStreamBuilder_setFramesPerDataCallback");
    int (*format)(void *)=tl_bionic_find("AAudioStream_getFormat");
    int (*write_frames)(void *,const void *,int,int64_t)=tl_bionic_find("AAudioStream_write");
    int (*pause_stream)(void *)=tl_bionic_find("AAudioStream_requestPause");
    int64_t (*written)(void *)=tl_bionic_find("AAudioStream_getFramesWritten");
    CHECK(builder&&set_callback&&open_stream&&delete_builder&&start&&state&&close_stream);
    CHECK(set_format&&set_channels&&set_frames&&format&&write_frames&&pause_stream&&written);
    tl_cocos_audio_hook=discard;
    void *b,*s;CHECK(builder(&b)==0);
    /* FMOD probes output configuration without installing a data callback. */
    CHECK(open_stream(b,&s)==0);CHECK(state(s)==2);CHECK(rate(s)==48000);CHECK(channels(s)==2);
    /* Upstream now supports callback-free written playback, too. No speaker hook. */
    CHECK(start(s)==0);CHECK(state(s)==4);CHECK(start(s)==0);
    int16_t pcm[8]={0};CHECK(write_frames(s,pcm,4,0)==4);CHECK(written(s)==4);
    CHECK(pause_stream(s)==0);CHECK(state(s)==6);CHECK(write_frames(s,pcm,4,0)==0);
    CHECK(start(s)==0);CHECK(write_frames(s,pcm,4,0)==4);CHECK(written(s)==8);CHECK(close_stream(s)==0);
    set_callback(b,callback,NULL);CHECK(open_stream(b,&s)==0);delete_builder(b);
    for(int i=1;i<=3;++i){
        CHECK(start(s)==0);
        for(int retry=0;retry<1000&&state(s)!=10;++retry)usleep(1000);
        CHECK(state(s)==10);CHECK(atomic_load(&calls)==i);
    }
    CHECK(close_stream(s)==0);
    CHECK(builder(&b)==0);set_format(b,2);set_channels(b,2);set_frames(b,257);
    set_callback(b,float_callback,NULL);CHECK(open_stream(b,&s)==0);delete_builder(b);
    CHECK(format(s)==2&&channels(s)==2);expected_frames=257;atomic_store(&delivered,0);
    for(int i=1;i<=3;++i){
        CHECK(start(s)==0);
        for(int retry=0;retry<1000&&state(s)!=10;++retry)usleep(1000);
        CHECK(state(s)==10);CHECK(atomic_load(&calls)==3+i);
        CHECK(atomic_load(&delivered)==257*i);CHECK(!atomic_load(&invalid));CHECK(written(s)==257*i);
    }
    CHECK(close_stream(s)==0);
    puts("PASS AAudio configuration probe, written playback, float PCM, callback STOP, restart, reap and close");return 0;
}
