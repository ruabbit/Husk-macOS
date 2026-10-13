/* SPDX-License-Identifier: GPL-2.0-or-later */
#import <Foundation/Foundation.h>
#include "husk-tl-unity.h"
#include "husk-tl-driver.h"
BOOL mac_driver_select(NSString *name);
NSString *mac_driver_name(void);
BOOL mac_driver_accepts_scan(NSDictionary *scan);
BOOL mac_driver_start(const tl_unity_config *config, NSString *activity, NSString *vulkan);
void mac_driver_touch(int phase, int id, float x, float y);
void mac_driver_key(int key, bool down);
void mac_driver_text(const char *text);
void mac_driver_delete(void);
void mac_driver_keyboard(void (*callback)(int));
void mac_driver_pause(bool paused);
void mac_driver_stop(void);
unsigned long mac_driver_frames(void);
tl_driver_state mac_driver_state(void);
