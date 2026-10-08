/* SPDX-License-Identifier: GPL-2.0-or-later */
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
@interface VMDisplay : NSView
@property(nonatomic) BOOL ready;
@property(nonatomic) BOOL visible;
@property(nonatomic, readonly) CAMetalLayer *metalLayer;
@property(nonatomic, readonly) uint64_t frames;
- (void)presentTexture:(id<MTLTexture>)texture flip:(BOOL)flip;
- (void)pollCPU;
- (BOOL)screenshot:(NSString *)path;
- (void)releaseInput;
@end
