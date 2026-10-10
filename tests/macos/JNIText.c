/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-jni.h"
#include <stdio.h>
#include <string.h>
void tl_mc_hle_install(const char *,const char *,const char *,int,int);
void tl_hle_configure(const char *,const char *,const char *,int,int);
void tl_jni_hle_install(void);
void tl_log_line(const char *format,...){(void)format;}
#define CHECK(x) do{if(!(x)){fprintf(stderr,"JNI text check failed: %s\n",#x);return 1;}}while(0)
int main(void) {
    tl_jni_init();tl_hle_configure("com.husk.text-test","","/tmp",1280,720);tl_jni_hle_install();
    tl_mc_hle_install("com.husk.text-test","","/tmp",1280,720);
    jvalue class_args[3]={{.l=tl_jni_new_string("java.lang.String")},{.z=1},{.l=NULL}};
    jobj *class_object=tl_jni_call(tl_jni_class_object("java/lang/Class"),"forName","(Ljava/lang/String;ZLjava/lang/ClassLoader;)Ljava/lang/Class;",class_args).l;
    CHECK(class_object==tl_jni_class_object("java/lang/String")&&!tl_jni_pending());
    tl_jni_unref(class_args[0].l);class_args[0].l=tl_jni_new_string("org.husk.missing.TestClass");
    CHECK(!tl_jni_call(tl_jni_class_object("java/lang/Class"),"forName","(Ljava/lang/String;ZLjava/lang/ClassLoader;)Ljava/lang/Class;",class_args).l&&tl_jni_pending());
    tl_jni_clear();tl_jni_unref(class_args[0].l);
    jvalue name={.l=tl_jni_new_string("UTF-8")};
    jobj *charset=tl_jni_call(tl_jni_class_object("java/nio/charset/Charset"),"forName","(Ljava/lang/String;)Ljava/nio/charset/Charset;",&name).l;
    CHECK(charset&&!tl_jni_pending());
    const char *text="Husk 世界🌍";size_t n=strlen(text);
    const void **functions=*(const void ***)tl_jni_env();
    jobj *(*direct)(void *,void *,int64_t)=(void *)functions[229];
    jobj *b=direct(tl_jni_env(),(void *)text,n);jvalue buffer={.l=b};
    jobj *chars=tl_jni_call(charset,"decode","(Ljava/nio/ByteBuffer;)Ljava/nio/CharBuffer;",&buffer).l;
    jobj *result=tl_jni_call(chars,"toString","()Ljava/lang/String;",NULL).l;
    CHECK(result&&!tl_jni_pending());CHECK(strcmp(tl_jni_string(result),text)==0);
    CHECK(tl_jni_get_field(b,"position","I").i==(int)n);
    int (*length)(void *,jobj *)=(void *)functions[164];CHECK(length(tl_jni_env(),result)==9);
    tl_jni_set_field(b,"position","I",(jvalue){.i=5});tl_jni_set_field(b,"limit","I",(jvalue){.i=11});
    chars=tl_jni_call(charset,"decode","(Ljava/nio/ByteBuffer;)Ljava/nio/CharBuffer;",&buffer).l;
    result=tl_jni_call(chars,"toString","()Ljava/lang/String;",NULL).l;CHECK(strcmp(tl_jni_string(result),"世界")==0);
    jobj *state=tl_jni_new_object(tl_jni_class("com/google/androidgamesdk/gametextinput/State"));
    jobj *initial=tl_jni_new_string("Existing 世界");
    jvalue args[5]={{.l=initial},{.i=0},{.i=11},{.i=-1},{.i=-1}};
    tl_jni_call(state,"<init>","(Ljava/lang/String;IIII)V",args);
    CHECK(initial->refs>1);tl_jni_unref(initial);
    CHECK(strcmp(tl_jni_string(tl_jni_get_field(state,"text","Ljava/lang/String;").l),"Existing 世界")==0);
    puts("PASS GameTextInput UTF-8 decoding, UTF-16 length, range and State string ownership");return 0;
}
