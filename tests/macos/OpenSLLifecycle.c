/* SPDX-License-Identifier: GPL-2.0-or-later */
/* A blocked sink/callback exposes stop/clear races without a game or speakers. */
#include "husk-tl-bionic.h"
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

void tl_log_line(const char *format, ...) { (void)format; }
extern void (*tl_cocos_audio_hook)(const int16_t *, int, int, int);
typedef const void *const *const *Itf;
typedef struct { Itf engine, mix, object, play, queue; } Player;
static Player player;
static pthread_mutex_t gate = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static bool block_sink, release_sink, block_callback, release_callback, stop_in_callback, refill_once;
static atomic_int sinks, callbacks, operation_done;
static int16_t pcm[64];
#define CHECK(c) do { if (!(c)) { fprintf(stderr,"FAIL OpenSL line %d: %s\n",__LINE__,#c); exit(1); } } while (0)
#define METHOD(itf, slot, type) ((type)(*(itf))[slot])
static uint32_t state(Itf play, uint32_t value) { return METHOD(play,0,uint32_t(*)(const void *,uint32_t))(play,value); }
static uint32_t clear(Itf queue) { return METHOD(queue,1,uint32_t(*)(const void *))(queue); }
static uint32_t enqueue(Itf queue) { return METHOD(queue,0,uint32_t(*)(const void *,const void *,uint32_t))(queue,pcm,sizeof(pcm)); }
static uint32_t get_state(Itf itf, int slot) {
    uint32_t value[2] = {0};
    CHECK(!METHOD(itf,slot,uint32_t(*)(const void *,uint32_t *))(itf,value));
    return value[0];
}
static void wait_count(atomic_int *value, int minimum) {
    for (int i=0;i<2000 && atomic_load(value)<minimum;i++) usleep(1000);
    CHECK(atomic_load(value)>=minimum);
}
static void sink(const int16_t *p, int frames, int channels, int rate) {
    CHECK(p==pcm && frames==32 && channels==2 && rate==44100);
    pthread_mutex_lock(&gate); atomic_fetch_add(&sinks,1);
    while (block_sink && !release_sink) pthread_cond_wait(&changed,&gate);
    pthread_mutex_unlock(&gate);
}
static void callback(void *caller, void *context) {
    CHECK(caller==player.queue && context==&player);
    if (stop_in_callback) { CHECK(!state(player.play,1)); CHECK(!clear(player.queue)); }
    if (refill_once) { refill_once=false; CHECK(!enqueue(player.queue)); }
    pthread_mutex_lock(&gate); atomic_fetch_add(&callbacks,1);
    while (block_callback && !release_callback) pthread_cond_wait(&changed,&gate);
    pthread_mutex_unlock(&gate);
}
static Itf interface(Itf object, const char *name) {
    const void **symbol=tl_bionic_find(name); CHECK(symbol);
    Itf result=NULL;
    CHECK(!METHOD(object,3,uint32_t(*)(const void *,const void *,Itf *))(object,*symbol,&result));
    CHECK(result); return result;
}
static void make_player(void) {
    block_sink=release_sink=block_callback=release_callback=stop_in_callback=refill_once=false;
    atomic_store(&sinks,0); atomic_store(&callbacks,0); atomic_store(&operation_done,0);
    uint32_t (*create)(Itf *,uint32_t,const void *,uint32_t,const void *,const void *)=tl_bionic_find("slCreateEngine");
    CHECK(create && !create(&player.engine,0,NULL,0,NULL,NULL));
    CHECK(!METHOD(player.engine,0,uint32_t(*)(const void *,uint32_t))(player.engine,0));
    Itf engine=interface(player.engine,"SL_IID_ENGINE");
    CHECK(!METHOD(engine,7,uint32_t(*)(const void *,Itf *,uint32_t,const void *,const void *))(engine,&player.mix,0,NULL,NULL));
    uint32_t locator[]={0x800007bd,2}, format[]={2,2,44100000,16,16,3,2};
    struct { void *locator,*format; } source={locator,format};
    CHECK(!METHOD(engine,2,uint32_t(*)(const void *,Itf *,const void *,const void *,uint32_t,const void *,const void *))
        (engine,&player.object,&source,NULL,0,NULL,NULL));
    CHECK(!METHOD(player.object,0,uint32_t(*)(const void *,uint32_t))(player.object,0));
    player.play=interface(player.object,"SL_IID_PLAY");
    player.queue=interface(player.object,"SL_IID_ANDROIDSIMPLEBUFFERQUEUE");
    CHECK(!METHOD(player.queue,3,uint32_t(*)(const void *,void(*)(void *,void *),void *))(player.queue,callback,&player));
}
static void destroy_player(void) {
    METHOD(player.object,6,void(*)(const void *))(player.object);
    METHOD(player.mix,6,void(*)(const void *))(player.mix);
    METHOD(player.engine,6,void(*)(const void *))(player.engine);
}
static void *stopper(void *arg) {
    CHECK(!(arg?clear(player.queue):state(player.play,1)));
    atomic_store(&operation_done,1); return NULL;
}
static void release_gate(void) {
    pthread_mutex_lock(&gate); release_sink=release_callback=true;
    pthread_cond_broadcast(&changed); pthread_mutex_unlock(&gate);
}
static void wait_operation_started(bool clearing) {
    for (int i=0;i<2000;i++) {
        if (get_state(clearing?player.queue:player.play,clearing?2:1)==(clearing?0:1)) {
            CHECK(!atomic_load(&operation_done)); return;
        }
        usleep(1000);
    }
    CHECK(false);
}
int main(void) {
    tl_cocos_audio_hook=sink;
    pthread_t operation;
    make_player(); block_sink=true;
    CHECK(!enqueue(player.queue) && !state(player.play,3)); wait_count(&sinks,1);
    CHECK(!pthread_create(&operation,NULL,stopper,NULL)); wait_operation_started(false);
    release_gate(); pthread_join(operation,NULL);
    CHECK(!atomic_load(&callbacks) && atomic_load(&operation_done));
    /* Restart remains usable after a stop, with no stale completion. */
    CHECK(!enqueue(player.queue) && !state(player.play,3)); wait_count(&callbacks,1);
    CHECK(!state(player.play,1)); destroy_player();

    make_player(); block_callback=true;
    CHECK(!enqueue(player.queue) && !state(player.play,3)); wait_count(&callbacks,1);
    CHECK(!pthread_create(&operation,NULL,stopper,NULL)); wait_operation_started(false);
    release_gate(); pthread_join(operation,NULL); CHECK(atomic_load(&callbacks)==1); destroy_player();

    make_player(); block_sink=true;
    CHECK(!enqueue(player.queue) && !state(player.play,3)); wait_count(&sinks,1);
    CHECK(!pthread_create(&operation,NULL,stopper,&player)); wait_operation_started(true);
    CHECK(!enqueue(player.queue)); release_gate(); pthread_join(operation,NULL);
    wait_count(&callbacks,1); CHECK(!state(player.play,1));
    CHECK(atomic_load(&sinks)==2 && atomic_load(&callbacks)==1); destroy_player();

    make_player(); stop_in_callback=true;
    CHECK(!enqueue(player.queue) && !state(player.play,3)); wait_count(&callbacks,1);
    CHECK(get_state(player.play,1)==1 && get_state(player.queue,2)==0); destroy_player();

    make_player(); block_sink=true; refill_once=true;
    CHECK(!enqueue(player.queue) && !state(player.play,3)); wait_count(&sinks,1);
    CHECK(!state(player.play,2)); release_gate(); wait_count(&callbacks,1);
    CHECK(get_state(player.queue,2)==1 && atomic_load(&sinks)==1);
    CHECK(!state(player.play,3)); wait_count(&callbacks,2);
    CHECK(!state(player.play,1) && atomic_load(&sinks)==2); destroy_player();
    puts("PASS OpenSL stop/clear drain host reads and callbacks, fresh queue survives, pause/refill/resume and callback stop");
    return 0;
}
