/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-jni.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>

void tl_set_data_dir(const char *);
void tl_godot_hle_install(const char *, const char *, const char *, int, int);
void tl_log_line(const char *fmt, ...) { (void)fmt; }
#define CHECK(x) do { if (!(x) || tl_jni_pending()) { fprintf(stderr,"Godot files line %d: %s\n",__LINE__,#x); return 1; } } while(0)
static jobj *file, *directory;
static jvalue call(jobj *o, const char *n, const char *s, jvalue *a) { return tl_jni_call(o,n,s,a); }
int main(void) {
    char root[]="/tmp/husk-godot-files-XXXXXX"; CHECK(mkdtemp(root));
    tl_jni_init(); tl_set_data_dir(root);
    tl_godot_hle_install("org.husk.files","",root,320,200);
    file=tl_jni_new_object(tl_jni_class("org/godotengine/godot/io/file/FileAccessHandler"));
    directory=tl_jni_new_object(tl_jni_class("org/godotengine/godot/io/directory/DirectoryAccessHandler"));
    jobj *folder=tl_jni_new_string("/data/user/0/org.husk.files/files/cache");
    jobj *save=tl_jni_new_string("/data/user/0/org.husk.files/files/cache/save.dat");
    jobj *next=tl_jni_new_string("/data/user/0/org.husk.files/files/cache/next.dat");
    jvalue a[3]={{.i=2},{.l=folder}};
    CHECK(call(directory,"makeDir","(ILjava/lang/String;)Z",a).z);
    a[0].l=save;a[1].i=7;
    int id=call(file,"fileOpen","(Ljava/lang/String;I)I",a).i; CHECK(id>0);
    unsigned char bytes[]={1,2,0,255,5};
    jobj *buffer=tl_jni_new_object(tl_jni_class("java/nio/DirectByteBuffer"));
    tl_jni_set_field(buffer,"address","J",(jvalue){.l=bytes});
    tl_jni_set_field(buffer,"capacity","J",(jvalue){.j=sizeof(bytes)});
    a[0].i=id;a[1].l=buffer;CHECK(call(file,"fileWrite","(ILjava/nio/ByteBuffer;)Z",a).z);
    call(file,"fileFlush","(I)V",a);call(file,"fileClose","(I)V",a);
    call(file,"fileClose","(I)V",a); // duplicate and invalid handles must be harmless
    a[0].i=-7;call(file,"fileClose","(I)V",a);a[0].i=100000;call(file,"fileClose","(I)V",a);
    a[0].l=save;a[1].i=1;id=call(file,"fileOpen","(Ljava/lang/String;I)I",a).i;CHECK(id>0);
    memset(bytes,0,sizeof(bytes));a[0].i=id;a[1].l=buffer;
    CHECK(call(file,"fileRead","(ILjava/nio/ByteBuffer;)I",a).i==sizeof(bytes));
    CHECK(bytes[0]==1&&bytes[1]==2&&bytes[2]==0&&bytes[3]==255&&bytes[4]==5);
    CHECK(call(file,"fileGetSize","(I)J",a).j==5);
    CHECK(call(file,"fileRead","(ILjava/nio/ByteBuffer;)I",a).i==0);
    CHECK(call(file,"isFileEof","(I)Z",a).z);
    a[1].j=0;call(file,"fileSeek","(IJ)V",a);CHECK(!call(file,"isFileEof","(I)Z",a).z);
    call(file,"fileClose","(I)V",a);
    a[0].i=2;a[1].l=save;a[2].l=next;CHECK(call(directory,"rename","(ILjava/lang/String;Ljava/lang/String;)Z",a).z);
    a[1].l=folder;int d1=call(directory,"dirOpen","(ILjava/lang/String;)I",a).i;
    int d2=call(directory,"dirOpen","(ILjava/lang/String;)I",a).i;CHECK(d1>=4096&&d2>d1);
    jobj *alias=tl_jni_new_object(tl_jni_class("org/godotengine/godot/utils/GodotNetUtils"));
    a[0].i=d1;jobj *entry=call(alias,"dirNext","(I)Ljava/lang/String;",a).l;
    CHECK(entry&&!strcmp(tl_jni_string(entry),"next.dat"));CHECK(!call(directory,"dirIsDir","(I)Z",a).z);
    call(directory,"dirClose","(I)V",a);call(directory,"dirClose","(I)V",a);
    a[0].i=d2;entry=call(alias,"dirNext","(I)Ljava/lang/String;",a).l;
    CHECK(entry&&!strcmp(tl_jni_string(entry),"next.dat"));call(directory,"dirClose","(I)V",a);
    a[0].i=2;a[1].l=folder;int d3=call(alias,"dirOpen","(ILjava/lang/String;)I",a).i;CHECK(d3>d2);
    a[0].i=d1;call(alias,"dirClose","(I)V",a); // a stale handle must not close the reused slot
    a[0].i=2;a[1].i=d3;entry=call(directory,"dirNext","(II)Ljava/lang/String;",a).l;
    CHECK(entry&&!strcmp(tl_jni_string(entry),"next.dat"));call(directory,"dirClose","(II)V",a);
    a[0].l=next;a[1].i=3;id=call(alias,"fileOpen","(Ljava/lang/String;I)I",a).i;CHECK(id>0);
    a[0].i=id;a[1].j=2;call(alias,"fileResize","(IJ)V",a);
    CHECK(call(file,"fileGetSize","(I)J",a).j==2);call(file,"fileClose","(I)V",a);
    a[0].i=-1;a[1].l=buffer;CHECK(!call(alias,"fileWrite","(ILjava/nio/ByteBuffer;)Z",a).z);
    a[0].i=2;a[1].l=next;CHECK(call(directory,"remove","(ILjava/lang/String;)Z",a).z);
    a[1].l=folder;CHECK(call(directory,"remove","(ILjava/lang/String;)Z",a).z);
    char files[1200];snprintf(files,sizeof(files),"%s/files",root);rmdir(files);snprintf(files,sizeof(files),"%s/cache",root);rmdir(files);rmdir(root);
    puts("PASS Godot Kotlin save/flush/close/reopen, binary bytes, rename, independent directories and invalid handles");
    return 0;
}
