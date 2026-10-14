/* SPDX-License-Identifier: GPL-2.0-or-later */
#import <Foundation/Foundation.h>
// Recheck the installed cache in the child before loading any Geode code.
BOOL mac_geode_configure(NSString *directory, NSString *apk, NSString *digest,
                        NSString *package, NSString *runtime, NSString *data, NSError **error);
