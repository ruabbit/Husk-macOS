/* SPDX-License-Identifier: GPL-2.0-or-later */
#import "MacNativeDrivers.h"
#include "husk-tl-egl.h"
#include "husk-tl-ld.h"
#include "husk-tl-bionic.h"
#include "husk-tl-jni.h"
#include <unistd.h>
static BOOL waitState(tl_driver_state state) {
    for(int i=0;i<3000;i++){if(mac_driver_state()==state)return YES;if(mac_driver_state()==TL_DRIVER_FAILED)return NO;usleep(1000);}return NO;
}
#define CHECK(x) do{if(!(x)){fprintf(stderr,"FAIL line %d: %s (state %d)\n",__LINE__,#x,mac_driver_state());return 1;}}while(0)
int main(int argc,const char **argv) { @autoreleasepool {
    if(argc!=5)return 64;
    NSString *name=@(argv[1]),*apk=@(argv[2]),*angle=@(argv[3]);
    NSString *root=[@(argv[4]) stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *receipt=[root stringByAppendingPathComponent:@"callbacks.bin"];
    setenv("HUSK_FIXTURE_SAVE",receipt.fileSystemRepresentation,1);setenv("TL_AUDIO_MUTE","1",1);
    CHECK(mac_driver_select(name));tl_egl_offscreen_windows(true);
    tl_unity_config cfg={.apk_path=apk.fileSystemRepresentation,.data_dir=root.fileSystemRepresentation,.package_name="org.husk.driver",.width=320,.height=200,.angle_egl=angle.fileSystemRepresentation};
    CHECK(mac_driver_start(&cfg,@"org/libsdl/app/SDLActivity",nil));CHECK(waitState(TL_DRIVER_RUNNING));
    if([apk containsString:@"godot4"]){
        jobj *bridge=tl_jni_new_object(tl_jni_class("org/godotengine/godot/nativeapi/GodotNativeBridge"));
        jobj *view=tl_jni_call(bridge,"getRenderView","()Lorg/godotengine/godot/GodotRenderView;",NULL).l;
        CHECK(view&&!tl_jni_pending());
        CHECK(tl_jni_call(view,"getInputHandler","()Lorg/godotengine/godot/input/GodotInputHandler;",NULL).l);
        tl_jni_unref(bridge);
    }
    for(int i=0;i<2000&&mac_driver_frames()<2;i++)usleep(1000);
    CHECK(mac_driver_frames()>0);
    mac_driver_touch(0,0,50,50);mac_driver_touch(2,0,50,50);mac_driver_key(4,true);mac_driver_key(4,false);
    mac_driver_pause(true);
    if([apk containsString:@"-pause-failed"]){
        CHECK(waitState(TL_DRIVER_FAILED));mac_driver_stop();CHECK(mac_driver_state()==TL_DRIVER_FAILED);
        NSData *record=[NSData dataWithContentsOfFile:receipt];CHECK(record.length==8);
        const unsigned *v=record.bytes;CHECK((v[0]&128)&&!v[1]);
        puts("PASS failed pause remains failed after a successful native destructor");return 0;
    }
    CHECK(waitState(TL_DRIVER_PAUSED));
    unsigned long frames=mac_driver_frames();usleep(60000);CHECK(mac_driver_frames()==frames);
    mac_driver_pause(false);CHECK(waitState(TL_DRIVER_RUNNING));
    mac_driver_touch(0,0,50,50);mac_driver_touch(3,0,50,50);
    mac_driver_stop();
    BOOL missing=[apk containsString:@"-missing"];
    CHECK(mac_driver_state()==(missing?TL_DRIVER_FAILED:TL_DRIVER_DESTROYED));
    NSData *data=[NSData dataWithContentsOfFile:receipt];CHECK(data.length==8);
    const unsigned *v=data.bytes;CHECK(!v[1]);CHECK((v[0]&127)==127);
    if([apk containsString:@"godot4"])CHECK(v[0]&256);
    if(!missing&&![name isEqual:@"cocos"])CHECK(v[0]&128);
    printf("PASS %s real ELF frames, callbacks, same-thread pause/close and persistence (mask %u)\n",argv[1],v[0]);return 0;
}}
