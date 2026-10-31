/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-jni.h"
#include <stdio.h>
#include <string.h>
void tl_hle_configure(const char *,const char *,const char *,int,int);
void tl_jni_hle_install(void);
void tl_log_line(const char *format,...) {(void)format;}
#define CHECK(x) do { if(!(x)){fprintf(stderr,"FAIL JNI preferences %d: %s\n",__LINE__,#x);return 1;} } while(0)
static jobj *store(const char *name) {
    jobj *ctx=tl_jni_new_object(tl_jni_class("android/content/Context"));
    jvalue a[2]={{.l=tl_jni_new_string(name)},{.i=0}};
    return tl_jni_call(ctx,"getSharedPreferences","(Ljava/lang/String;I)Landroid/content/SharedPreferences;",a).l;
}
static jobj *edit(jobj *s) { return tl_jni_call(s,"edit","()Landroid/content/SharedPreferences$Editor;",NULL).l; }
static jvalue get(jobj *s,const char *key,const char *name,const char *sig,jvalue fallback) {
    jvalue a[2]={{.l=tl_jni_new_string(key)},fallback};return tl_jni_call(s,name,sig,a);
}
static void put(jobj *ed,const char *key,const char *name,const char *type,jvalue v) {
    char sig[160];snprintf(sig,sizeof sig,"(Ljava/lang/String;%s)Landroid/content/SharedPreferences$Editor;",type);
    jvalue a[2]={{.l=tl_jni_new_string(key)},v};tl_jni_call(ed,name,sig,a);
}
int main(int argc,char **argv) {
    if(argc!=3)return 64;
    tl_jni_init();tl_hle_configure("org.husk.prefs","",argv[2],1280,720);tl_jni_hle_install();
    char name[300];memset(name,'x',200);strcpy(name+200,"../世界/a");
    jobj *s=store(name);CHECK(s==store(name));strcpy(name+200,"../世界/b");jobj *other=store(name);
    #define INT(s,k) get(s,k,"getInt","(Ljava/lang/String;I)I",(jvalue){.i=-1}).i
    CHECK(s&&other&&!tl_jni_pending());
    if(!strcmp(argv[1],"empty")) { CHECK(INT(s,"i")==-1&&INT(other,"i")==-1);return 0; }
    if(!strcmp(argv[1],"write")) {
        jobj *ed=edit(s);
        put(ed,"i","putInt","I",(jvalue){.i=7});CHECK(INT(s,"i")==-1);
        put(ed,"j","putLong","J",(jvalue){.j=INT64_C(0x10000000042)});
        put(ed,"f","putFloat","F",(jvalue){.f=.75f});
        put(ed,"z","putBoolean","Z",(jvalue){.z=1});
        put(ed,"s","putString","Ljava/lang/String;",(jvalue){.l=tl_jni_new_string("世界\n\t\\")});
        CHECK(tl_jni_call(ed,"commit","()Z",NULL).z);
        ed=edit(other);put(ed,"i","putInt","I",(jvalue){.i=91});
        tl_jni_call(ed,"apply","()V",NULL);CHECK(INT(s,"i")==7&&INT(other,"i")==91);
        /* A discarded editor must not be flushed during normal close. */
        put(edit(s),"i","putInt","I",(jvalue){.i=999});CHECK(tl_hle_flush_prefs());
    } else if(!strcmp(argv[1],"failure")) {
        jobj *ed=edit(s);put(ed,"i","putInt","I",(jvalue){.i=8});
        CHECK(!tl_jni_call(ed,"commit","()Z",NULL).z&&!tl_hle_flush_prefs());
        CHECK(!tl_jni_pending());puts("PASS failed storage cannot claim a successful close");return 0;
    } else {
        CHECK(INT(s,"i")==7&&INT(other,"i")==91);
        CHECK(get(s,"j","getLong","(Ljava/lang/String;J)J",(jvalue){0}).j==INT64_C(0x10000000042));
        CHECK(get(s,"f","getFloat","(Ljava/lang/String;F)F",(jvalue){0}).f==.75f);
        CHECK(get(s,"z","getBoolean","(Ljava/lang/String;Z)Z",(jvalue){0}).z);
        CHECK(!strcmp(tl_jni_string(get(s,"s","getString","(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;",(jvalue){0}).l),"世界\n\t\\"));
        jobj *map=tl_jni_call(s,"getAll","()Ljava/util/Map;",NULL).l;
        CHECK(map&&tl_jni_call(map,"size","()I",NULL).i==5);
        jobj *ed=edit(s);put(ed,"i","putInt","I",(jvalue){.i=19});
        tl_jni_call(ed,"clear","()Landroid/content/SharedPreferences$Editor;",NULL);
        CHECK(tl_jni_call(ed,"commit","()Z",NULL).z&&INT(s,"i")==19);
        jvalue key={.l=tl_jni_new_string("i")};
        jobj *old=tl_jni_call(map,"get","(Ljava/lang/Object;)Ljava/lang/Object;",&key).l;
        CHECK(tl_jni_call(old,"intValue","()I",NULL).i==7); /* independent snapshot */
        ed=edit(s);tl_jni_call(ed,"remove","(Ljava/lang/String;)Landroid/content/SharedPreferences$Editor;",&key);
        tl_jni_call(ed,"apply","()V",NULL);CHECK(INT(s,"i")==-1);
        CHECK(!tl_jni_call(s,"contains","(Ljava/lang/String;)Z",&key).z&&tl_hle_flush_prefs());
    }
    CHECK(!tl_jni_pending());puts("PASS named JNI preferences: staged edits, all value types, clear/remove, snapshot and durable flush");return 0;
}
