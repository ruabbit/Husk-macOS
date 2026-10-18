/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Exercise the production Unity driver with registered JNI natives. No window,
 * guest APK, audio output, or intentional crash. Real games are opt-in. */
#include "husk-tl-unity.h"
#include "husk-tl-jni.h"
#include "husk-tl-gamepad.h"
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

void tl_input_install(void);
void tl_log_line(const char *format, ...) { (void)format; }
static pthread_t render_thread;
static atomic_int calls, pause_entered, pause_returned, destroy_entered, destroy_returned;
static atomic_bool wrong_thread, quitting;
static int resumes, focuses, actions[16], keys[16], motion_count, key_count;
static atomic_int text_events, text_selection, text_closed, text_cancelled, keyboard_action, keyboard_kind;
static char last_text[4096];
static void check_thread(void) { if (!pthread_equal(pthread_self(), render_thread)) atomic_store(&wrong_thread,true); }
static void noop(void *env, void *self) { (void)env; (void)self; }
static void init(void *env, void *self, void *context) { (void)context; noop(env,self); }
static void init_two(void *env, void *self, void *context, int mode) {
    init(env,self,context);if(mode!=0)atomic_store(&wrong_thread,true);
}
static void init_modern(void *env, void *self, void *context, int mode, jobj *command_line) {
    init(env,self,context);
    if(mode!=0||!command_line||strcmp(tl_jni_string(command_line),""))atomic_store(&wrong_thread,true);
}
static void surface(void *env, void *self, int display, void *s) { (void)display; (void)s; noop(env,self); render_thread=pthread_self(); }
static void resume(void *env, void *self) { noop(env,self); check_thread(); resumes++; }
static void focus(void *env, void *self, unsigned char active) { noop(env,self); check_thread(); focuses += active?1:-1; }
static unsigned char render(void *env, void *self) { noop(env,self); check_thread(); atomic_fetch_add(&calls,1); return !atomic_load(&quitting); }
static unsigned char pause_game(void *env, void *self) {
    noop(env,self); check_thread(); atomic_fetch_add(&pause_entered,1);
    usleep(50000); atomic_fetch_add(&pause_returned,1); return 0;
}
static void done(void *env, void *self) {
    noop(env,self); check_thread(); atomic_store(&destroy_entered,1);
    if (focuses || atomic_load(&pause_entered)!=atomic_load(&pause_returned)) atomic_store(&wrong_thread,true);
    usleep(50000); atomic_store(&destroy_returned,1);
}
static unsigned char done_modern(void *env, void *self) { done(env,self);return 0; }
static void text_set(void *env,void *self,jobj *text) {
    noop(env,self);check_thread();snprintf(last_text,sizeof(last_text),"%s",tl_jni_string(text));
    atomic_fetch_add(&text_events,1);
}
static void text_select(void *env,void *self,int start,int count) {
    noop(env,self);check_thread();if(count)atomic_store(&wrong_thread,true);atomic_store(&text_selection,start);
}
static void text_close(void *env,void *self) { noop(env,self);check_thread();atomic_fetch_add(&text_closed,1); }
static void text_cancel(void *env,void *self) { noop(env,self);check_thread();atomic_fetch_add(&text_cancelled,1); }
static void keyboard(int action,int kind) { atomic_store(&keyboard_kind,kind);atomic_store(&keyboard_action,action); }
static unsigned char inject(void *env, void *self, jobj *event) {
    noop(env,self);
    int action=tl_jni_call(event,"getAction","()I",NULL).i;
    if (!strcmp(tl_jni_class_name(event),"android/view/KeyEvent")) {
        if(key_count<16)keys[key_count++]=tl_jni_call(event,"getKeyCode","()I",NULL).i;
    } else if(motion_count<16)actions[motion_count++]=action;
    return 1;
}
typedef struct { const char *name, *sig; void *fn; } Native;
#define CHECK(c) do { if(!(c)){fprintf(stderr,"FAIL Unity lifecycle line %d: %s\n",__LINE__,#c);return 1;} } while(0)
static bool wait_state(tl_unity_state state) {
    for(int i=0;i<2000;i++){if(tl_unity_get_state()==state)return true;usleep(1000);}return false;
}
static void *stop_thread(void *unused) { (void)unused;tl_unity_stop();return NULL; }
int main(int argc, char **argv) {
    bool missing=argc>1&&!strcmp(argv[1],"missing-done"), quit=argc>1&&!strcmp(argv[1],"guest-quit");
    bool modern=argc>1&&!strcmp(argv[1],"modern-player");
    bool two=argc>1&&!strcmp(argv[1],"two-argument-init");
    tl_jni_init();tl_input_install();
    Native natives[]={
        {"initJni","(Landroid/content/Context;)V",init},
        {"nativeRecreateGfxState","(ILandroid/view/Surface;)V",surface},
        {"nativeSendSurfaceChangedEvent","()V",noop},
        {"nativeResume","()V",resume},{"nativeFocusChanged","(Z)V",focus},
        {"nativeRender","()Z",render},{"nativePause","()Z",pause_game},
        {"nativeInjectEvent","(Landroid/view/InputEvent;)Z",inject},
        {"nativeDone","()V",done}
    };
    const void **jni=*(const void ***)tl_jni_env();
    int (*register_natives)(void *,void *,const Native *,int)=(void *)jni[215];
    if(two)natives[0]=(Native){"initJni","(Landroid/content/Context;I)V",init_two};
    if(modern){
        Native base[]={{"initJni","(Landroid/content/Context;ILjava/lang/String;)V",init_modern},natives[7]};
        natives[8]=(Native){"nativeDone","()Z",done_modern};
        CHECK(!register_natives(tl_jni_env(),tl_jni_class_object("com/unity3d/player/UnityPlayer"),base,2));
        CHECK(!register_natives(tl_jni_env(),tl_jni_class_object("com/unity3d/player/UnityPlayerForActivityOrService"),natives+1,8));
    }else CHECK(!register_natives(tl_jni_env(),tl_jni_class_object("com/unity3d/player/UnityPlayer"),natives,missing?8:9));
    Native text_natives[]={
        {"nativeSetInputString","(Ljava/lang/String;)V",text_set},
        {"nativeSetInputSelection","(II)V",text_select},
        {"nativeSoftInputClosed","()V",text_close},{"nativeSoftInputCanceled","()V",text_cancel}
    };
    CHECK(!register_natives(tl_jni_env(),tl_jni_class_object("com/unity3d/player/UnityPlayer"),text_natives,4));
    tl_unity_set_keyboard_handler(keyboard);
    CHECK(tl_unity_run()&&wait_state(TL_UNITY_RUNNING));
    jobj *player=tl_jni_new_object(tl_jni_class("com/unity3d/player/UnityPlayer"));
    jvalue show[9]={0};show[0].l=tl_jni_new_string("");show[3].z=1;show[4].z=1;show[7].i=3;
    tl_jni_call(player,"showSoftInput","(Ljava/lang/String;IZZZZLjava/lang/String;IZ)V",show);
    CHECK(atomic_load(&keyboard_action)==1&&atomic_load(&keyboard_kind)==0x300);
    tl_unity_insert_text("中😀ab");
    for(int i=0;i<2000&&atomic_load(&text_selection)!=4;i++)usleep(1000);
    CHECK(atomic_load(&text_selection)==4&&!strcmp(last_text,"中😀a"));
    tl_unity_delete_backward();tl_unity_delete_backward();
    char current[4096];tl_unity_text_copy(current,sizeof(current));CHECK(!strcmp(current,"中"));
    tl_unity_finish_text(true);
    for(int i=0;i<2000&&!atomic_load(&text_closed);i++)usleep(1000);
    CHECK(atomic_load(&text_closed)==1&&!strcmp(last_text,"中"));
    tl_jni_call(player,"showSoftInput","(Ljava/lang/String;IZZZZLjava/lang/String;IZ)V",show);
    tl_unity_insert_text("cancel");tl_unity_finish_text(false);
    for(int i=0;i<2000&&!atomic_load(&text_cancelled);i++)usleep(1000);
    CHECK(atomic_load(&text_cancelled)==1);
    tl_jni_call(player,"hideSoftInput","()V",NULL);
    tl_jni_unref(show[0].l);tl_jni_unref(player);
    tl_unity_touch(0,0,10,20);tl_unity_touch(1,0,12,22);tl_unity_touch(2,0,12,22);
    tl_unity_touch(0,0,10,20);tl_unity_touch(3,0,0,0);
    tl_unity_key(29,true,0);tl_unity_key(29,false,0);
    CHECK(motion_count==5&&actions[0]==0&&actions[1]==2&&actions[2]==1&&actions[4]==3);
    CHECK(key_count==2&&keys[0]==29&&keys[1]==29);
    tl_unity_register_pad_sink();tl_pad_connect(0,"Unity test pad");
    tl_pad_state pad={.buttons=1,.lx=.5f};tl_pad_update(0,&pad);tl_pad_disconnect(0);
    CHECK(key_count>2&&motion_count>5);
    tl_unity_set_paused(true);
    while(!atomic_load(&pause_entered))usleep(1000);
    CHECK(tl_unity_get_state()!=TL_UNITY_PAUSED);
    CHECK(wait_state(TL_UNITY_PAUSED)&&atomic_load(&pause_returned)==1);
    int frames=atomic_load(&calls), inputs=key_count;
    tl_unity_key(29,true,0);usleep(30000);
    CHECK(atomic_load(&calls)==frames&&key_count==inputs);
    tl_unity_set_paused(false);CHECK(wait_state(TL_UNITY_RUNNING));
    pthread_t stopper;
    if(quit){atomic_store(&quitting,true);}
    else CHECK(!pthread_create(&stopper,NULL,stop_thread,NULL));
    if(!missing){
        while(!atomic_load(&destroy_entered))usleep(1000);
        CHECK(tl_unity_get_state()==TL_UNITY_STOPPING&&!atomic_load(&destroy_returned));
    }
    CHECK(wait_state(missing?TL_UNITY_FAILED:TL_UNITY_DESTROYED));
    if(quit)tl_unity_stop();else pthread_join(stopper,NULL);
    CHECK(!atomic_load(&wrong_thread)&&resumes==2&&atomic_load(&pause_returned)==2);
    CHECK(missing||atomic_load(&destroy_returned));
    puts("PASS Unity thread order, touch/key/controller delivery, pause acknowledgement, resume and completed destruction");
    return 0;
}
