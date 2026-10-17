/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-nativeactivity-abi.h"
extern int bootstrap_ready(void);
extern unsigned long pthread_self(void);
extern char *getenv(const char *);
extern int strcmp(const char *,const char *);
extern void *ALooper_forThread(void);
extern void AInputQueue_attachLooper(void *,void *,int,void *,void *);
extern void AInputQueue_detachLooper(void *);
extern int AInputQueue_getEvent(void *,void **);
extern void AInputQueue_finishEvent(void *,void *,int);
extern int AInputEvent_getType(void *), AInputEvent_getDeviceId(void *), AKeyEvent_getKeyCode(void *);
extern void ANativeActivity_finish(ANativeActivity *);
static unsigned mask; static unsigned long owner; static ANativeActivity *activity;
static void *queue;
static int is(const char *s) { const char *v=getenv("HUSK_NATIVE_ACTIVITY_CASE"); return v&&!strcmp(v,s); }
static void mark(unsigned bit) { if (owner && owner != pthread_self()) mask |= 1u<<20; mask |= bit; }
__attribute__((constructor)) static void init(void) { if (bootstrap_ready()) mask=1; else mask=1u<<21; }
int JNI_OnLoad(void *vm,void *r) { (void)r; if(vm)mask|=2; return 0x10006; }
static void start(ANativeActivity *a) { mark(8); }
static void resume(ANativeActivity *a) { mark(16); }
static void pause_game(ANativeActivity *a) { mark(32); }
static void stop(ANativeActivity *a) { mark(64); }
static void destroy(ANativeActivity *a) { mark(128); }
static void focus(ANativeActivity *a,int f) { mark(f?256:512); }
static void window(ANativeActivity *a,void *w) { if(w)mark(1024); }
static void window_gone(ANativeActivity *a,void *w) { mark(2048); }
static int input(int fd,int events,void *data) {
    void *e;
    while (!AInputQueue_getEvent(queue,&e)) {
        int t=AInputEvent_getType(e),d=AInputEvent_getDeviceId(e);
        if(t==2&&d==1)mark(16384);
        if(t==1&&AKeyEvent_getKeyCode(e)==29)mark(32768);
        if(d==41)mark(t==1?65536:131072);
        AInputQueue_finishEvent(queue,e,1);
    }
    return 1;
}
static void queue_created(ANativeActivity *a,void *q) { queue=q; mark(4096); AInputQueue_attachLooper(q,ALooper_forThread(),0,(void *)input,0); }
static void queue_gone(ANativeActivity *a,void *q) { mark(8192); AInputQueue_detachLooper(q); }
void ANativeActivity_onCreate(ANativeActivity *a,void *s,size_t n) {
    activity=a; owner=pthread_self(); mark(4);
    *a->callbacks=(ANativeActivityCallbacks){.onStart=start,.onResume=resume,.onPause=pause_game,.onStop=stop,
        .onDestroy=is("missing-destroy")?0:destroy,.onWindowFocusChanged=focus,.onNativeWindowCreated=window,
        .onNativeWindowDestroyed=window_gone,.onInputQueueCreated=queue_created,.onInputQueueDestroyed=queue_gone};
    if(is("native-create-failed")) {
        void **jni=*(void ***)a->env;
        void *cls=((void *(*)(void *,const char *))jni[6])(a->env,"java/lang/IllegalStateException");
        ((int (*)(void *,void *,const char *))jni[14])(a->env,cls,"fixture native onCreate");
    }
}
int Java_org_husk_nativeboot_Game_result(void *e,void *c) { return (int)__atomic_load_n(&mask,__ATOMIC_ACQUIRE); }
void Java_org_husk_nativeboot_Game_finishNative(void *e,void *c) { ANativeActivity_finish(activity); }
