/* SPDX-License-Identifier: GPL-2.0-or-later */
#import <Foundation/Foundation.h>

// Runs only in an isolated Runner, before the loader starts any guest code.
NSString *mac_aot_prepare(NSArray<NSString *> *apks, NSString *runtimeRoot,
                         void (^progress)(NSString *), NSError **error);
