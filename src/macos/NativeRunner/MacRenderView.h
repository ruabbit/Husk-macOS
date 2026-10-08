/* SPDX-License-Identifier: GPL-2.0-or-later */
#import "MacTextInput.h"
#import <QuartzCore/QuartzCore.h>

/// Presents a fixed guest framebuffer in view points without resizing it.
@interface MacRenderView : MacTextInput
@property(readonly) CAMetalLayer *surface;
@property(readonly) NSSize renderSize;
@property(readonly) NSRect contentRect;
- (instancetype)initWithFrame:(NSRect)frame renderSize:(NSSize)size;
- (NSPoint)renderPointForViewPoint:(NSPoint)point;
@end
