/* SPDX-License-Identifier: GPL-2.0-or-later */
#pragma once
#import <Foundation/Foundation.h>

/* Call on the main thread before starting Java. A host-owned store is tied to
 * a save, not just a package. WebKit continues to own its database files. */
bool tl_web_set_host_store(NSUUID *identifier);
void tl_web_close_for_host(void (^completion)(BOOL detached, NSDictionary *receipt));
/* Diagnostic protocol only; the caller must require its automation flag. */
void tl_web_evaluate_for_host(int wid, NSString *script, void (^completion)(id, NSError *));
