/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Repository-owned Android ELF callbacks. Exercises real loading, GL and lifecycle. */
#include <stdint.h>
#include <stdatomic.h>
extern void glClearColor(float,float,float,float);
extern void glClear(unsigned);
extern void *fopen(const char *,const char *);
extern unsigned long fwrite(const void *,unsigned long,unsigned long,void *);
extern int fclose(void *);
extern char *getenv(const char *);
extern unsigned long pthread_self(void);
extern int usleep(unsigned);
static unsigned mask, wrong_thread;
static unsigned long owner;
static _Atomic int quit_requested, paused, rendering;
static unsigned long event_owner;
static atomic_flag recording = ATOMIC_FLAG_INIT;
static void record_on(unsigned bit, unsigned long *expected) {
    while(atomic_flag_test_and_set(&recording))usleep(100);
    unsigned long me=pthread_self();
    if (!*expected) *expected=me;
    if (*expected!=me) wrong_thread=1;
    mask|=bit;
    const char *path=getenv("HUSK_FIXTURE_SAVE");
    void *f=fopen(path?path:"/data/user/0/org.husk.driver/callbacks.bin","wb");
    if(f){unsigned data[]={mask,wrong_thread};fwrite(data,sizeof(data),1,f);fclose(f);}
    atomic_flag_clear(&recording);
}
static void record(unsigned bit) {record_on(bit,&owner);}
static void draw(void) { glClearColor(.2f,.7f,.4f,1);glClear(0x4000); }
extern void *eglGetDisplay(void *);
extern unsigned eglInitialize(void *,int *,int *);
extern unsigned eglChooseConfig(void *,const int *,void **,int,int *);
extern void *eglCreateContext(void *,void *,void *,const int *);
extern void *eglCreateWindowSurface(void *,void *,void *,const int *);
extern unsigned eglMakeCurrent(void *,void *,void *,void *);
extern unsigned eglSwapBuffers(void *,void *);
extern unsigned eglDestroySurface(void *,void *);
extern unsigned eglDestroyContext(void *,void *);
extern void *ANativeWindow_fromSurface(void *,void *);
static void *display,*surface,*context;
static void setup_gl(void) {
    display=eglGetDisplay(0);int a,b,n;eglInitialize(display,&a,&b);
    const int want[]={0x3040,4,0x3033,4,0x3038}, attributes[]={0x3098,2,0x3038};void *cfg=0;
    eglChooseConfig(display,want,&cfg,1,&n);context=eglCreateContext(display,cfg,0,attributes);
    surface=eglCreateWindowSurface(display,cfg,ANativeWindow_fromSurface(0,0),0);eglMakeCurrent(display,surface,surface,context);
}
static void close_gl(void) {eglMakeCurrent(display,0,0,0);eglDestroySurface(display,surface);eglDestroyContext(display,context);}
int JNI_OnLoad(void *vm,void *r) {(void)vm;(void)r;return 0x10006;}
#define COCOS(n) Java_org_cocos2dx_lib_Cocos2dxRenderer_##n
#define GODOT(n) Java_org_godotengine_godot_GodotLib_##n
#define GM(n) Java_com_yoyogames_runner_RunnerJNILib_##n
#define SDL(n) Java_org_libsdl_app_SDLActivity_##n
#define GTA(n) Java_com_rockstargames_oswrapper_GameNative_##n
void Java_org_cocos2dx_lib_Cocos2dxHelper_nativeSetApkPath(void *e,void *c,void *p){}
void COCOS(nativeInit)(void *e,void *c,int w,int h) {record(1);}
void COCOS(nativeRender)(void *e,void *c) {draw();}
void COCOS(nativeOnPause)(void *e,void *c) {record(8);}
void COCOS(nativeOnResume)(void *e,void *c) {record(16);}
void COCOS(nativeTouchesBegin)(void *e,void *c,int id,float x,float y) {record(2);}
void COCOS(nativeTouchesEnd)(void *e,void *c,int id,float x,float y) {record(4);}
void COCOS(nativeTouchesMove)(void *e,void *c,void *ids,void *x,void *y) {}
void COCOS(nativeTouchesCancel)(void *e,void *c,void *ids,void *x,void *y) {record(64);}
unsigned char COCOS(nativeKeyDown)(void *e,void *c,int key) {record(32);return 1;}
void GODOT(initialize)(void *e,void *c,void *a,void *g,void *as,void *io,void *net,void *d,void *f,unsigned char exp){}
unsigned char GODOT(setup)(void *e,void *c,void *a,void *t){return 1;}
void GODOT(newcontext)(void *e,void *c){record(1);}
void GODOT(resize)(void *e,void *c,int w,int h){}
void GODOT(focusin)(void *e,void *c){}
unsigned char GODOT(step)(void *e,void *c){draw();return 1;}
void GODOT(onRendererPaused)(void *e,void *c){
    record(8);
#ifdef PAUSE_FAILURE
    void **jni=*(void ***)e;
    void *cls=((void *(*)(void *,const char *))jni[6])(e,"java/lang/RuntimeException");
    ((int (*)(void *,void *,const char *))jni[14])(e,cls,"fixture pause failed");
#endif
}
void GODOT(onRendererResumed)(void *e,void *c){record(16);}
void GODOT(dispatchTouchEvent)(void *e,void *c,int action,int pointer,int count,void *pos,unsigned char dbl){record(action==0?2:action==3?64:4);}
void GODOT(key)(void *e,void *c,int code,int scan,int uni,unsigned char down){record(32);}
int GM(initGLFuncs)(void *e,void *c,int gl2){return gl2;}
void GM(Startup)(void *e,void *c,void *apk,void *save,void *package,int sleep,unsigned char dynamic){record(1);}
int GM(Process)(void *e,void *c,int w,int h,float x,float y,float z,int pad,int ori,float refresh){draw();return 1;}
unsigned char GM(canFlip)(void *e,void *c){return 1;}
void GM(Pause)(void *e,void *c,int v){record(8);}
void GM(Resume)(void *e,void *c,int v){record(16);}
void GM(TouchEvent)(void *e,void *c,int action,int id,float x,float y,int count){record(action==0?2:action==3?64:4);}
void GM(KeyEvent)(void *e,void *c,int action,int code,int uni,int source,int repeat){record(32);}
int SDL(nativeSetupJNI)(void *e,void *c){record(1);return 0;}
void SDL(onNativeSurfaceCreated)(void *e,void *c){}
void SDL(onNativeSurfaceChanged)(void *e,void *c){}
void SDL(nativeSetScreenResolution)(void *e,void *c,int w,int h,int dw,int dh,float d,float hz){}
void SDL(nativeSetNaturalOrientation)(void *e,void *c,int v){}
void SDL(onNativeFocusChanged)(void *e,void *c,unsigned char v){}
int SDL(nativeRunMain)(void *e,void *c,void *lib,void *entry,void *args){
    setup_gl();while(!atomic_load(&quit_requested)){
        atomic_store(&rendering,1);
        if(!atomic_load(&paused)){draw();eglSwapBuffers(display,surface);}
        atomic_store(&rendering,0);usleep(16000);
    }close_gl();return 0;
}
int SDL_main(int argc,char **argv){return 0;}
void SDL(nativePause)(void *e,void *c){atomic_store(&paused,1);while(atomic_load(&rendering))usleep(1000);record(8);}
void SDL(nativeResume)(void *e,void *c){record(16);atomic_store(&paused,0);}
void SDL(nativeSendQuit)(void *e,void *c){atomic_store(&quit_requested,1);}
/* SDL accepts input on the platform event thread, separate from SDLMain. */
void SDL(onNativeTouch)(void *e,void *c,int device,int finger,int action,float x,float y,float pressure){record_on(action==0?2:action==3?64:4,&event_owner);}
void SDL(onNativeKeyDown)(void *e,void *c,int key){record_on(32,&event_owner);}
void SDL(onNativeKeyUp)(void *e,void *c,int key){}
void GTA(implOnActivityCreated)(void *e,void *c,void *svc,unsigned char initialized){record(1);}
void GTA(implOnInitialSetup)(void *e,void *c,void *device,void *assets,void *apks,void *none){setup_gl();}
unsigned char GTA(implIsInitialized)(void *e,void *c){return 1;}
void GTA(implOnDrawFrame)(void *e,void *c,float dt){draw();eglSwapBuffers(display,surface);usleep(16000);}
void GTA(implOnPause)(void *e,void *c){record(8);}
void GTA(implOnResume)(void *e,void *c){record(16);}
void GTA(implOnTouchStart)(void *e,void *c,int id,float x,float y){record(2);}
void GTA(implOnTouchEnd)(void *e,void *c,int id,float x,float y){record(4|64);}
void GTA(implOnGamepadButtonDown)(void *e,void *c,int device,int key){record(32);}
void GTA(implOnGamepadButtonUp)(void *e,void *c,int device,int key){record(32);}
#ifndef MISSING_DESTROY
void GODOT(ondestroy)(void *e,void *c){
    record(128);
#ifdef PAUSE_FAILURE
    ((void (*)(void *))(*(void ***)e)[17])(e);
#endif
}
void GM(Exit)(void *e,void *c){record(128);}
void SDL(nativeQuit)(void *e,void *c){record(128);}
void GTA(implOnActivityDestroyed)(void *e,void *c){record(128);close_gl();}
#endif

#ifdef ACTIVITY_FIXTURE
typedef struct Activity Activity;
typedef struct {
    void (*start)(Activity *), (*resume)(Activity *);
    void *(*save)(Activity *,unsigned long *);
    void (*pause)(Activity *), (*stop)(Activity *), (*destroy)(Activity *);
    void (*focus)(Activity *,int);
    void (*windowCreated)(Activity *,void *), (*windowResized)(Activity *,void *), (*redraw)(Activity *,void *), (*windowDestroyed)(Activity *,void *);
    void (*queueCreated)(Activity *,void *), (*queueDestroyed)(Activity *,void *);
    void (*rect)(Activity *,const void *), (*config)(Activity *), (*lowMemory)(Activity *);
} Callbacks;
struct Activity {Callbacks *callbacks;};
extern void *ALooper_forThread(void);
extern void AInputQueue_attachLooper(void *,void *,int,int (*)(int,int,void *),void *);
extern void AInputQueue_detachLooper(void *);
extern int AInputQueue_getEvent(void *,void **);
extern void AInputQueue_finishEvent(void *,void *,int);
extern int AInputEvent_getType(void *);
extern int AMotionEvent_getAction(void *);
static void *input_queue;
static int poll_input(int fd,int events,void *context) {
    void *event;
    while(input_queue&&AInputQueue_getEvent(input_queue,&event)>=0){
        if(AInputEvent_getType(event)==1)record(32);
        else {int action=AMotionEvent_getAction(event)&255;record(action==0?2:action==3?64:action==1?4:0);}
        AInputQueue_finishEvent(input_queue,event,1);
    }
    return 1;
}
static void activity_resume(Activity *a){record(16);}
static void activity_pause(Activity *a){poll_input(0,0,0);record(8);}
static void activity_window(Activity *a,void *w){setup_gl();draw();eglSwapBuffers(display,surface);}
static void activity_queue(Activity *a,void *q){input_queue=q;AInputQueue_attachLooper(q,ALooper_forThread(),1,poll_input,0);}
static void activity_queue_gone(Activity *a,void *q){poll_input(0,0,0);AInputQueue_detachLooper(q);input_queue=0;}
static void activity_destroy(Activity *a){record(128);close_gl();}
void ANativeActivity_onCreate(Activity *a,void *saved,unsigned long length){
    record(1);a->callbacks->resume=activity_resume;a->callbacks->pause=activity_pause;
    a->callbacks->windowCreated=activity_window;a->callbacks->queueCreated=activity_queue;
    a->callbacks->queueDestroyed=activity_queue_gone;a->callbacks->destroy=activity_destroy;
}
#endif
