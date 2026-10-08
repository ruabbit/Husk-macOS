/* SPDX-License-Identifier: GPL-2.0-or-later */
/* UTF-8 ByteBuffer -> CharBuffer used by GameTextInput's native state bridge.
 * Unsupported encodings raise an exception instead of inventing text. */
#include "husk-tl-jni.h"
#include <stdlib.h>
#include <string.h>
#include <strings.h>

static void Charset_forName(tl_jcall *c) {
    const char *name=tl_jni_string(c->args[0].l);
    if(!name||(strcasecmp(name,"UTF-8")&&strcasecmp(name,"UTF8"))){tl_jni_throw("java/nio/charset/UnsupportedCharsetException",name?name:"");return;}
    c->ret.l=tl_jni_new_object(tl_jni_class("java/nio/charset/Charset"));
}
static void Buffer_wrap(tl_jcall *c) {
    jobj *array=c->args[0].l;
    if(!array||array->kind!=TL_K_PRIM_ARRAY||array->arr.esz!=1){tl_jni_throw("java/lang/IllegalArgumentException","Expected byte array");return;}
    jobj *b=tl_jni_new_object(tl_jni_class("java/nio/ByteBuffer"));
    tl_jni_set_field(b,"array","[B",(jvalue){.l=tl_jni_ref(array)});
    tl_jni_set_field(b,"capacity","J",(jvalue){.j=array->arr.len});
    tl_jni_set_field(b,"position","I",(jvalue){.i=0});
    tl_jni_set_field(b,"limit","I",(jvalue){.i=(int)array->arr.len});c->ret.l=b;
}
static void Charset_decode(tl_jcall *c) {
    jobj *b=c->args[0].l;if(!b){tl_jni_throw("java/lang/NullPointerException","Null ByteBuffer");return;}
    int64_t cap=tl_jni_get_field(b,"capacity","J").j;
    int pos=tl_jni_get_field(b,"position","I").i,limit=tl_jni_get_field(b,"limit","I").i;
    jobj *a=tl_jni_get_field(b,"array","[B").l;
    const unsigned char *data=a&&a->kind==TL_K_PRIM_ARRAY?a->arr.data:tl_jni_get_field(b,"address","J").l;
    if(pos<0||limit<pos||limit>cap||cap>16*1024*1024||(!data&&limit>pos)){tl_jni_throw("java/lang/IllegalArgumentException","Invalid text buffer range");return;}
    size_t n=(size_t)(limit-pos),used=0;char *text=malloc(n*3+1);
    for(size_t i=0;i<n;){
        unsigned ch=data[pos+i];size_t count=ch<0x80?1:ch>=0xc2&&ch<=0xdf?2:ch>=0xe0&&ch<=0xef?3:ch>=0xf0&&ch<=0xf4?4:0;
        bool valid=count&&i+count<=n;unsigned cp=count?ch&((1u<<(7-count))-1):0;
        for(size_t j=1;valid&&j<count;j++){unsigned v=data[pos+i+j];valid=(v&0xc0)==0x80;cp=(cp<<6)|(v&63);}
        if(count>1)valid=valid&&cp>=(count==2?0x80:count==3?0x800:0x10000)&&cp<=0x10ffff&&!(cp>=0xd800&&cp<=0xdfff);
        if(valid&&ch!=0){memcpy(text+used,data+pos+i,count);used+=count;i+=count;}
        else {memcpy(text+used,"\xef\xbf\xbd",3);used+=3;i++;}
    }
    text[used]=0;jobj *out=tl_jni_new_object(tl_jni_class("java/nio/CharBuffer"));
    tl_jni_set_field(out,"text","Ljava/lang/String;",(jvalue){.l=tl_jni_new_string(text)});
    tl_jni_set_field(b,"position","I",(jvalue){.i=limit});free(text);c->ret.l=out;
}
static void CharBuffer_toString(tl_jcall *c) { c->ret.l=tl_jni_ref(tl_jni_get_field(c->self,"text","Ljava/lang/String;").l); }
static const tl_jhle methods[]={
    {"java/nio/charset/Charset","forName","(Ljava/lang/String;)Ljava/nio/charset/Charset;",Charset_forName},
    {"java/nio/charset/Charset","decode","(Ljava/nio/ByteBuffer;)Ljava/nio/CharBuffer;",Charset_decode},
    {"java/nio/ByteBuffer","wrap","([B)Ljava/nio/ByteBuffer;",Buffer_wrap},
    {"java/nio/CharBuffer","toString","()Ljava/lang/String;",CharBuffer_toString},
    {NULL,NULL,NULL,NULL}
};
void tl_jni_text_install(void) {
    tl_jni_declare("java/nio/ByteBuffer","java/lang/Object");
    tl_jni_declare("java/nio/DirectByteBuffer","java/nio/ByteBuffer");
    tl_jni_declare("java/nio/CharBuffer","java/lang/Object");
    tl_jni_declare("java/nio/charset/Charset","java/lang/Object");
    tl_jni_register_hle(methods);
}
