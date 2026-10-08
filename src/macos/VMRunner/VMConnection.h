/* SPDX-License-Identifier: GPL-2.0-or-later */
#import <Foundation/Foundation.h>
@interface VMConnection : NSObject
- (instancetype)initPort:(uint16_t)port;
- (NSString *)shell:(NSString *)command timeout:(double)timeout status:(int *)status error:(NSError **)error;
- (BOOL)push:(NSString *)path remote:(NSString *)remote error:(NSError **)error;
- (void)close;
@end
NSDictionary *VMQMP(NSString *path, NSString *command, NSDictionary *arguments, NSError **error);
