/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Drive the production activity thread with an in-process NDK guest. No game,
 * window or audio; callbacks deliberately take time to expose early receipts. */
#include "../../src/translation-layer-next/husk-tl-nativeactivity.c"
void tl_log_line(const char *format, ...) { (void)format; }

static pthread_t owner;
static atomic_int pauses, destroys, stopped, queue_gone, window_gone;
static atomic_bool wrong_thread, destroying;
static bool missing, create_failed;
static int starts, resumes, focus;
static void check_thread(void) { if (!pthread_equal(owner, pthread_self())) atomic_store(&wrong_thread, true); }
static void start(ANativeActivity *a) { (void)a; check_thread(); starts++; }
static void resume(ANativeActivity *a) { (void)a; check_thread(); resumes++; }
static void pause_game(ANativeActivity *a) { (void)a; check_thread(); usleep(40000); atomic_fetch_add(&pauses, 1); }
static void focus_changed(ANativeActivity *a, int value) { (void)a; check_thread(); focus += value ? 1 : -1; }
static void window_destroyed(ANativeActivity *a, void *w) { (void)a; (void)w; check_thread(); atomic_store(&window_gone, 1); }
static void queue_created(ANativeActivity *a, void *queue) {
    (void)a; check_thread();
    void *(*looper)(void) = tl_bionic_find("ALooper_forThread");
    void (*attach)(void *, void *, int, void *, void *) = tl_bionic_find("AInputQueue_attachLooper");
    attach(queue, looper(), 5, NULL, NULL);
}
static void queue_destroyed(ANativeActivity *a, void *queue) {
    (void)a; check_thread();
    void (*detach)(void *) = tl_bionic_find("AInputQueue_detachLooper");
    detach(queue); atomic_store(&queue_gone, 1);
}
static void stop_game(ANativeActivity *a) { (void)a; check_thread(); atomic_store(&stopped, 1); }
static void destroy(ANativeActivity *a) {
    (void)a; check_thread(); atomic_store(&destroying, true);
    if (focus || (!create_failed && (!atomic_load(&queue_gone) || !atomic_load(&window_gone) || !atomic_load(&stopped)))) atomic_store(&wrong_thread, true);
    usleep(60000); atomic_store(&destroys, 1);
}
static void create(ANativeActivity *a, void *save, size_t size) {
    (void)save; (void)size; owner = pthread_self();
    *a->callbacks = (ANativeActivityCallbacks){.onStart=start,.onResume=resume,.onPause=pause_game,
        .onStop=stop_game,.onDestroy=missing?NULL:destroy,.onWindowFocusChanged=focus_changed,
        .onNativeWindowDestroyed=window_destroyed,.onInputQueueCreated=queue_created,.onInputQueueDestroyed=queue_destroyed};
    if (create_failed) tl_jni_throw("java/lang/RuntimeException", "test onCreate failure");
}
#define CHECK(c) do { if (!(c)) { fprintf(stderr,"FAIL NativeActivity line %d: %s\n",__LINE__,#c); return 1; } } while (0)
static bool wait_state(tl_na_state state) {
    for (int i=0;i<2000;i++) { if (tl_na_get_state()==state) return true; usleep(1000); } return false;
}
static void *stop_thread(void *unused) { (void)unused; tl_na_stop(); return NULL; }
int main(int argc, char **argv) {
    missing=argc>1&&!strcmp(argv[1],"missing-destroy");
    create_failed=argc>1&&!strcmp(argv[1],"create-failed");
    bool guest=argc>1&&!strcmp(argv[1],"guest-finish");
    tl_jni_init(); tl_hle_configure("org.husk.test","","/tmp",1280,720); tl_jni_hle_install();
    tl_jni_declare("android/app/NativeActivity", "android/app/Activity");
    N.generic=true; N.started=true; N.on_create=create;
    N.activity=tl_jni_new_object(tl_jni_class("android/app/NativeActivity"));
    tl_native_activity_finish_hook=request_finish;
    CHECK(tl_na_run());
    if (create_failed) {
        CHECK(wait_state(TL_NA_FAILED));
        tl_na_stop();
        CHECK(!N.thread_created && !atomic_load(&wrong_thread) && atomic_load(&destroys)==1);
        CHECK(starts==0 && resumes==0 && !focus && !atomic_load(&pauses));
        CHECK(!atomic_load(&queue_gone) && !atomic_load(&window_gone) && !atomic_load(&stopped));
        puts("PASS failed onCreate destroys without delivering a started lifecycle or a storage receipt");
        return 0;
    }
    CHECK(wait_state(TL_NA_RUNNING));
    CHECK(starts==1 && resumes==1 && focus==1);
    jobj *app=tl_jni_call(tl_jni_class_object("android/app/ActivityThread"),"currentApplication","()Landroid/app/Application;",NULL).l;
    CHECK(app && app==tl_jni_call(N.activity,"getApplication","()Landroid/app/Application;",NULL).l);
    tl_na_touch(0,0,10,20); tl_na_touch(1,0,12,22); tl_na_touch(2,0,12,22);
    tl_na_key(29,true); tl_na_key(29,false);
    int (*get_event)(void *,void **) = tl_bionic_find("AInputQueue_getEvent");
    int (*type)(void *) = tl_bionic_find("AInputEvent_getType");
    int (*motion)(void *) = tl_bionic_find("AMotionEvent_getAction");
    int (*key)(void *) = tl_bionic_find("AKeyEvent_getKeyCode");
    int (*key_action)(void *) = tl_bionic_find("AKeyEvent_getAction");
    int (*device)(void *) = tl_bionic_find("AInputEvent_getDeviceId");
    float (*axis)(void *,int,size_t) = tl_bionic_find("AMotionEvent_getAxisValue");
    void (*finish)(void *,void *,int) = tl_bionic_find("AInputQueue_finishEvent");
    for (int i=0;i<5;i++) {
        void *e=NULL; CHECK(!get_event(&N,&e) && e);
        if (i<3) { int actions[]={0,2,1}; CHECK(type(e)==2 && motion(e)==actions[i]); }
        else CHECK(type(e)==1 && key(e)==29);
        finish(&N,e,1);
    }
    tl_pad_connect(0,"NativeActivity test controller");
    for (int release=0;release<2;release++) {
        tl_pad_state pad = release ? (tl_pad_state){0} : (tl_pad_state){.buttons=1u<<TL_PAD_A,.lx=.5f};
        tl_pad_update(0,&pad);
        for (int i=0;i<2;i++) {
            void *e=NULL; CHECK(!get_event(&N,&e) && e && device(e)==41);
            if (i==0) CHECK(type(e)==1 && key(e)==96 && key_action(e)==release);
            else CHECK(type(e)==2 && axis(e,0,0)==pad.lx);
            finish(&N,e,1);
        }
    }
    tl_na_set_paused(true); CHECK(tl_na_get_state()==TL_NA_RUNNING);
    CHECK(wait_state(TL_NA_PAUSED) && atomic_load(&pauses)==1 && !focus);
    tl_na_key(29,true); void *event=NULL; CHECK(get_event(&N,&event)<0);
    tl_na_set_paused(false); CHECK(wait_state(TL_NA_RUNNING) && resumes==2);
    pthread_t stopper;
    if (guest) { void (*request)(void *)=tl_bionic_find("ANativeActivity_finish"); request(&N.na); }
    else CHECK(!pthread_create(&stopper,NULL,stop_thread,NULL));
    if (!missing) {
        for (int i=0;i<2000&&!atomic_load(&destroying);i++) usleep(1000);
        CHECK(atomic_load(&destroying) && tl_na_get_state()==TL_NA_STOPPING && !atomic_load(&destroys));
    }
    CHECK(wait_state(missing?TL_NA_FAILED:TL_NA_DESTROYED));
    if (guest) tl_na_stop(); else pthread_join(stopper,NULL);
    CHECK(!N.thread_created && !atomic_load(&wrong_thread) && atomic_load(&pauses)==2);
    puts("PASS NativeActivity callback ownership, touch/key/controller input, Application singleton, pause and joined destruction");
    return 0;
}
