/* SPDX-License-Identifier: GPL-2.0-or-later */
#import "MacNativeDrivers.h"
#include "husk-tl-cocos.h"
#include "husk-tl-godot.h"
#include "husk-tl-gamemaker.h"
#include "husk-tl-sdl.h"
#include "husk-tl-gtasa.h"
#include "husk-tl-vulkan.h"

_Static_assert((int)TL_DRIVER_IDLE == (int)TL_UNITY_IDLE &&
    (int)TL_DRIVER_RUNNING == (int)TL_UNITY_RUNNING && (int)TL_DRIVER_PAUSED == (int)TL_UNITY_PAUSED &&
    (int)TL_DRIVER_STOPPING == (int)TL_UNITY_STOPPING && (int)TL_DRIVER_DESTROYED == (int)TL_UNITY_DESTROYED &&
    (int)TL_DRIVER_FAILED == (int)TL_UNITY_FAILED, "Runner lifecycle values must match");
static NSString *selected;
BOOL mac_driver_select(NSString *name) {
    if (![@[@"cocos", @"godot", @"gamemaker", @"sdl", @"gta"] containsObject:name]) return NO;
    selected = [name copy]; return YES;
}
NSString *mac_driver_name(void) { return selected; }
BOOL mac_driver_accepts_scan(NSDictionary *scan) {
    if (![scan isKindOfClass:NSDictionary.class] || ![scan[@"ok"] boolValue] || ![scan[@"hasManifest"] boolValue] ||
        ![scan[@"abis"] isKindOfClass:NSArray.class] || ![scan[@"abis"] containsObject:@"arm64-v8a"]) return NO;
    NSDictionary *engines = @{@"cocos":@"Cocos",@"godot":@"Godot",@"gamemaker":@"GameMaker",@"sdl":@"SDL",@"gta":@"Rockstar"};
    if (![scan[@"engine"] isEqual:engines[selected]]) return NO;
    if ([selected isEqual:@"cocos"] || [selected isEqual:@"sdl"]) {
        for (NSDictionary *lib in scan[@"libraries"]) {
            NSString *name=lib[@"name"];
            if (![name isKindOfClass:NSString.class]) continue;
            if ([selected isEqual:@"cocos"] ? [name isEqual:@"libfmod.so"] : [name hasPrefix:@"libdxvk"]) return YES;
        }
        return NO;
    }
    return YES;
}
#define CONFIG_FIELDS .apk_path=c->apk_path,.data_dir=c->data_dir,.package_name=c->package_name,\
    .width=c->width,.height=c->height,.metal_layer=c->metal_layer,.angle_egl=c->angle_egl,\
    .angle_gles=c->angle_gles,.frame_dir=c->frame_dir,.frame_every=c->frame_every
BOOL mac_driver_start(const tl_unity_config *c, NSString *activity, NSString *vulkan) {
    if ([selected isEqual:@"cocos"]) { tl_cocos_config cfg={CONFIG_FIELDS}; tl_cocos_text_install(); tl_cocos_register_pad_sink(); return tl_cocos_start(&cfg)&&tl_cocos_run(); }
    if ([selected isEqual:@"godot"]) { tl_godot_config cfg={CONFIG_FIELDS}; return tl_godot_start(&cfg)&&tl_godot_run(); }
    if ([selected isEqual:@"gamemaker"]) { tl_gm_config cfg={CONFIG_FIELDS}; return tl_gm_start(&cfg)&&tl_gm_run(); }
    tl_ga_config cfg={CONFIG_FIELDS};
    if ([selected isEqual:@"gta"]) return tl_gta_start(&cfg)&&tl_gta_run();
    if ([selected isEqual:@"sdl"] && activity.length) {
        tl_vk_configure(vulkan.fileSystemRepresentation,NULL,0);
        return tl_sdl_start(&cfg,activity.UTF8String)&&tl_sdl_run();
    }
    return NO;
}
void mac_driver_touch(int phase,int id,float x,float y) {
    if ([selected isEqual:@"cocos"]) tl_cocos_touch(phase,id,x,y);
    else if ([selected isEqual:@"godot"]) tl_godot_touch(phase,id,x,y);
    else if ([selected isEqual:@"gamemaker"]) tl_gm_touch(phase,id,x,y);
    else if ([selected isEqual:@"sdl"]) tl_sdl_touch(phase,id,x,y);
    else tl_gta_touch(phase,id,x,y);
}
void mac_driver_key(int key,bool down) {
    if ([selected isEqual:@"cocos"]) { if(down)tl_cocos_key_down(key); }
    else if ([selected isEqual:@"godot"]) tl_godot_key(key,down);
    else if ([selected isEqual:@"gamemaker"]) tl_gm_key(key,down);
    else if ([selected isEqual:@"sdl"]) tl_sdl_key(key,down);
    else tl_gta_key(key,down);
}
void mac_driver_text(const char *text) {
    if ([selected isEqual:@"cocos"]) tl_cocos_insert_text(text);
    else if ([selected isEqual:@"sdl"]) tl_sdl_commit_text(text);
}
void mac_driver_delete(void) {
    if ([selected isEqual:@"cocos"]) tl_cocos_delete_backward();
    else { mac_driver_key(67,true); mac_driver_key(67,false); }
}
void mac_driver_keyboard(void (*callback)(int)) { tl_cocos_keyboard_hook=callback; tl_sdl_set_keyboard_handler(callback); }
#define DISPATCH(OP, ARG) \
    if ([selected isEqual:@"cocos"]) return tl_cocos_##OP ARG; \
    if ([selected isEqual:@"godot"]) return tl_godot_##OP ARG; \
    if ([selected isEqual:@"gamemaker"]) return tl_gm_##OP ARG; \
    if ([selected isEqual:@"sdl"]) return tl_sdl_##OP ARG; \
    return tl_gta_##OP ARG
void mac_driver_pause(bool paused) { DISPATCH(set_paused,(paused)); }
void mac_driver_stop(void) { DISPATCH(stop,()); }
unsigned long mac_driver_frames(void) { DISPATCH(frames,()); }
tl_driver_state mac_driver_state(void) { DISPATCH(state,()); }
