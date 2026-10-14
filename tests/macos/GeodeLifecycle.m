/* SPDX-License-Identifier: GPL-2.0-or-later */
#import "MacGeode.h"
#import "MacNativeDrivers.h"
#include "husk-tl-geode.h"
#include "husk-tl-egl.h"
#include "husk-tl-bionic.h"
#include "HuskCore.h"
#include <unistd.h>
#define CHECK(x) do{if(!(x)){fprintf(stderr,"FAIL line %d: %s\n",__LINE__,#x);return 1;}}while(0)
static BOOL waitState(tl_driver_state state) {
    for(int i=0;i<3000;i++){if(mac_driver_state()==state)return YES;if(mac_driver_state()==TL_DRIVER_FAILED)return NO;usleep(1000);}return NO;
}
int main(int argc,const char **argv) { @autoreleasepool {
    if(argc!=5)return 64;
    NSFileManager *fm=NSFileManager.defaultManager;
    NSString *root=[@(argv[3]) stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    CHECK([fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:NULL]);
    NSString *game=[root stringByAppendingPathComponent:@"game"];
    CHECK([fm copyItemAtPath:@(argv[1]) toPath:game error:NULL]);
    NSString *cache=[game stringByAppendingPathComponent:@"geode"], *apk=[game stringByAppendingPathComponent:@"game.apk"];
    NSString *data=[root stringByAppendingPathComponent:@"data"], *receipt=[data stringByAppendingPathComponent:@"loaded.txt"];
    NSString *manifest=[cache stringByAppendingPathComponent:@"installation.json"];
    NSDictionary *record=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:manifest] options:0 error:NULL];
    CHECK(record);
    NSString *digest=record[@"gameDigest"];
    NSError *error=nil;
    CHECK(!mac_geode_configure(cache,apk,digest,@"org.other.app",@"cocos",data,&error));
    CHECK(!mac_geode_configure(cache,apk,digest,@"com.robtopx.geometryjump",@"java",data,&error));
    CHECK(!mac_geode_configure(cache,apk,@"wrong digest",@"com.robtopx.geometryjump",@"cocos",data,&error));
    NSString *launcher=[cache stringByAppendingPathComponent:@"geode-launcher.apk"];
    NSString *moved=[game stringByAppendingPathComponent:@"launcher.apk"];
    CHECK([fm moveItemAtPath:launcher toPath:moved error:NULL]);
    CHECK([fm createSymbolicLinkAtPath:launcher withDestinationPath:moved error:NULL]);
    CHECK(!mac_geode_configure(cache,apk,digest,@"com.robtopx.geometryjump",@"cocos",data,&error));
    CHECK([fm removeItemAtPath:launcher error:NULL]);CHECK([fm moveItemAtPath:moved toPath:launcher error:NULL]);
    CHECK(mac_geode_configure(cache,apk,digest,@"com.robtopx.geometryjump",@"cocos",data,&error));
    CHECK(tl_geode_configured()&&!tl_geode_loaded());
    NSString *bin=[data stringByAppendingPathComponent:@"geode-bin"];
    NSString *resources=[data stringByAppendingPathComponent:@"geode/game/geode/resources/geode.loader"];
    NSString *mods=[data stringByAppendingPathComponent:@"geode/game/geode/mods"];
    for(NSString *dir in @[bin,resources,mods])CHECK([fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL]);
    size_t length=0;void *bytes=husk_tl_read_entry([[cache stringByAppendingPathComponent:@"geode-android64.zip"] fileSystemRepresentation],"Geode.android64.so",128<<20,&length);
    CHECK(bytes&&length>64);husk_tl_free(bytes);
    CHECK([[NSMutableData dataWithLength:length] writeToFile:[bin stringByAppendingPathComponent:@"Geode.android64.so"] atomically:YES]);
    CHECK([[@"old!" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:[resources stringByAppendingPathComponent:@"loader.txt"] atomically:YES]);
    CHECK([[@"user mod" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:[mods stringByAppendingPathComponent:@"test.geode"] atomically:YES]);
    NSString *callbacks=[data stringByAppendingPathComponent:@"callbacks.bin"];
    setenv("HUSK_GEODE_RECEIPT",receipt.fileSystemRepresentation,1);setenv("HUSK_FIXTURE_SAVE",callbacks.fileSystemRepresentation,1);
    setenv("TL_AUDIO_MUTE","1",1);tl_egl_offscreen_windows(true);CHECK(mac_driver_select(@"cocos"));
    tl_unity_config cfg={.apk_path=apk.fileSystemRepresentation,.data_dir=data.fileSystemRepresentation,.package_name="com.robtopx.geometryjump",
        .width=320,.height=200,.angle_egl=argv[2]};
    BOOL started=mac_driver_start(&cfg,nil,nil);
    CHECK([[NSString stringWithContentsOfFile:receipt encoding:NSUTF8StringEncoding error:NULL] isEqual:@"CJ"]);
    if(!strcmp(argv[4],"failure")) {
        CHECK(!started&&!tl_geode_loaded());CHECK(mac_driver_frames()==0);
        puts("PASS Geode JNI failure blocks game startup before frames");return 0;
    }
    CHECK(started&&tl_geode_loaded());CHECK(waitState(TL_DRIVER_RUNNING));
    for(int i=0;i<2000&&mac_driver_frames()<2;i++)usleep(1000);
    CHECK(mac_driver_frames()>0);
    CHECK([[NSString stringWithContentsOfFile:[resources stringByAppendingPathComponent:@"loader.txt"] encoding:NSUTF8StringEncoding error:NULL] isEqual:@"new!"]);
    CHECK([[NSString stringWithContentsOfFile:[data stringByAppendingPathComponent:@"files/game_version.txt"] encoding:NSUTF8StringEncoding error:NULL] isEqual:@"39"]);
    mac_driver_touch(0,0,50,50);mac_driver_touch(2,0,50,50);mac_driver_key(4,true);
    mac_driver_pause(true);CHECK(waitState(TL_DRIVER_PAUSED));
    unsigned long frames=mac_driver_frames();usleep(60000);CHECK(mac_driver_frames()==frames);
    mac_driver_pause(false);CHECK(waitState(TL_DRIVER_RUNNING));mac_driver_touch(0,0,50,50);mac_driver_touch(3,0,50,50);
    mac_driver_stop();CHECK(mac_driver_state()==TL_DRIVER_DESTROYED);
    NSData *events=[NSData dataWithContentsOfFile:callbacks];CHECK(events.length==8);
    const unsigned *v=events.bytes;CHECK((v[0]&127)==127&&!v[1]);
    CHECK([[NSString stringWithContentsOfFile:[mods stringByAppendingPathComponent:@"test.geode"] encoding:NSUTF8StringEncoding error:NULL] isEqual:@"user mod"]);
    puts("PASS checked Geode injection, constructors/JNI, equal-size replacement, frames, input, pause/close and preserved mods");return 0;
}}
