/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Controlled Android ELF for the shipping Unity and Minecraft dispatch paths. */
#define JNI_OnLoad unused_driver_onload
#include "native_driver.c"
#undef JNI_OnLoad
typedef struct { const char *name,*sig; void *fn; } Native;
typedef union { int i; unsigned char z; void *l; long long j; } Value;
extern void *ALooper_forThread(void);

#ifdef UNITY_FIXTURE
extern int husk_plugin_count(void);
static int init_kind, previous_closes;
static void *preferences;
static void *jni_string(void *e,const char *s) {
    const void **j=*(const void ***)e;return ((void *(*)(void *,const char *))j[167])(e,s);
}
static void *jni_method(void *e,void *o,const char *name,const char *sig) {
    const void **j=*(const void ***)e;void *c=((void *(*)(void *,void *))j[31])(e,o);
    return ((void *(*)(void *,void *,const char *,const char *))j[33])(e,c,name,sig);
}
static void *jni_object(void *e,void *o,const char *name,const char *sig,Value *v) {
    const void **j=*(const void ***)e;return ((void *(*)(void *,void *,void *,Value *))j[36])(e,o,jni_method(e,o,name,sig),v);
}
static void save_preferences(void *e) {
    const void **j=*(const void ***)e;
    void *ed=jni_object(e,preferences,"edit","()Landroid/content/SharedPreferences$Editor;",0);
    Value put[]={{.l=jni_string(e,"closes")},{.i=previous_closes+1}};
    jni_object(e,ed,"putInt","(Ljava/lang/String;I)Landroid/content/SharedPreferences$Editor;",put);
    int ok=((unsigned char (*)(void *,void *,void *,Value *))j[39])(e,ed,jni_method(e,ed,"commit","()Z"),0);
    void *f=fopen("/data/user/0/org.husk.driver/prefs-observed.bin","wb");
    if(f){int v[]={previous_closes,ok};fwrite(v,sizeof v,1,f);fclose(f);}
}
static void unity_init(void *e,void *s,void *c,int mode,void *line) {
    const void **jni=*(const void ***)e;
    const char *text=((const char *(*)(void *,void *,void *))jni[169])(e,line,0);
    init_kind=mode==0&&text&&!text[0]?3:-1;
    if(text)((void (*)(void *,void *,const char *))jni[170])(e,line,text);
    Value args[]={{.l=jni_string(e,"unity.fixture")},{.i=0}};
    preferences=jni_object(e,c,"getSharedPreferences","(Ljava/lang/String;I)Landroid/content/SharedPreferences;",args);
    args[0].l=jni_string(e,"closes");
    previous_closes=((int (*)(void *,void *,void *,Value *))jni[51])(e,preferences,jni_method(e,preferences,"getInt","(Ljava/lang/String;I)I"),args);
}
static void wrong_init(void *e,void *s,void *c) { init_kind=-1; }
static void unity_surface(void *e,void *s,int id,void *surface) {
    if(init_kind!=3)wrong_thread=1;
    setup_gl();record(1);
}
static void unity_noop(void *e,void *s) {}
static void unity_focus(void *e,void *s,unsigned char f) {}
static void unity_resume(void *e,void *s) {record(16);}
static unsigned char unity_pause(void *e,void *s) {record(8);return 0;}
static unsigned char unity_render(void *e,void *s) {draw();eglSwapBuffers(display,surface);return 1;}
static void unity_done(void *e,void *s) {save_preferences(e);record(128);close_gl();}
static unsigned char unity_input(void *e,void *s,void *event) {
    const void **jni=*(const void ***)e;
    void *key=((void *(*)(void *,const char *))jni[6])(e,"android/view/KeyEvent");
    if(((unsigned char (*)(void *,void *,void *))jni[32])(e,event,key))record_on(32,&event_owner);
    else {
        void *cls=((void *(*)(void *,void *))jni[31])(e,event);
        void *mid=((void *(*)(void *,void *,const char *,const char *))jni[33])(e,cls,"getAction","()I");
        int action=((int (*)(void *,void *,void *,const Value *))jni[51])(e,event,mid,0)&255;
        record_on(action==0?2:action==1?4:action==3?64:0,&event_owner);
    }
    return 1;
}
static unsigned char unity_load(void *e,void *cls,void *directory) {
    const void **jni=*(const void ***)e;
    void *player=((void *(*)(void *,const char *))jni[6])(e,"com/unity3d/player/UnityPlayer");
    void *mid=((void *(*)(void *,void *,const char *,const char *))jni[113])(e,player,"loadLibrary","(Ljava/lang/String;)Z");
    Value a={.l=((void *(*)(void *,const char *))jni[167])(e,"huskplugin")};
    for(int i=0;i<2;i++)if(!((unsigned char (*)(void *,void *,void *,const Value *))jni[119])(e,player,mid,&a))return 0;
    if(husk_plugin_count()!=1)return 0;
    mask|=512;
    a.l=jni_string(e,"il2cpp");
    if(!((unsigned char (*)(void *,void *,void *,const Value *))jni[119])(e,player,mid,&a))return 0;
    extern void *dlopen(const char *,int);extern void *dlsym(void *,const char *);
    void *lib=dlopen("libil2cpp.so",2);
    int (*ready)(void)=lib?dlsym(lib,"husk_il2_ready"):0;
    if(!ready || !ready())return 0;
    mask|=1024;return 1;
}
int JNI_OnLoad(void *vm,void *unused) {
    void *e=0;const void **v=*(const void ***)vm;
    if(!ALooper_forThread()||((int (*)(void *,void **,int))v[6])(vm,&e,0x10006))return -1;
    mask|=256;
    const void **jni=*(const void ***)e;
    void *(*find)(void *,const char *)=(void *)jni[6];
    int (*reg)(void *,void *,const Native *,int)=(void *)jni[215];
    Native load={"load","(Ljava/lang/String;)Z",unity_load};
    Native methods[]={
        {"initJni","(Landroid/content/Context;)V",wrong_init},
        {"initJni","(Landroid/content/Context;ILjava/lang/String;)V",unity_init},
        {"nativeRecreateGfxState","(ILandroid/view/Surface;)V",unity_surface},
        {"nativeSendSurfaceChangedEvent","()V",unity_noop},
        {"nativeFocusChanged","(Z)V",unity_focus},{"nativeResume","()V",unity_resume},
        {"nativePause","()Z",unity_pause},{"nativeRender","()Z",unity_render},
        {"nativeDone","()V",unity_done},{"nativeInjectEvent","(Landroid/view/InputEvent;)Z",unity_input}
    };
    if(reg(e,find(e,"com/unity3d/player/NativeLoader"),&load,1)||reg(e,find(e,"com/unity3d/player/UnityPlayer"),methods,10))return -1;
    return 0x10006;
}
#else
static int v8_disabled;
void flags(const char *) __asm__("_ZN2v82V818SetFlagsFromStringEPKc");
void flags(const char *s) {v8_disabled=!strcmp(s,"--jitless");}
int JNI_OnLoad(void *vm,void *unused) {return 0x10006;}
#define GA(n) Java_com_google_androidgamesdk_GameActivity_##n
long long GA(initializeNativeCode)(void *e,void *s,void *a,void *b,void *c,void *d,void *f,void *g) {
    if(!v8_disabled||!ALooper_forThread())return 0;
    mask|=256;record(1);return 42;
}
void GA(onResumeNative)(void *e,void *s,long long h) {record(16);}
void GA(onPauseNative)(void *e,void *s,long long h) {record(8);}
void GA(onSurfaceCreatedNative)(void *e,void *s,long long h,void *w) {setup_gl();draw();eglSwapBuffers(display,surface);}
void GA(onSurfaceDestroyedNative)(void *e,void *s,long long h) {close_gl();}
void GA(terminateNativeCode)(void *e,void *s,long long h) {record(128);}
unsigned char GA(onKeyDownNative)(void *e,void *s,long long h,void *k) {record(32);return 1;}
unsigned char GA(onKeyUpNative)(void *e,void *s,long long h,void *k) {record(32);return 1;}
unsigned char GA(onTouchEventNative)(void *e,void *s,long long h,void *event,int count,int hist,int device,int src,
                                    unsigned long action,...) {record(action==0?2:action==3?64:action==1?4:0);return 1;}
#endif
