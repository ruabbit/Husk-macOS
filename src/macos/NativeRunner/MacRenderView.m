/* SPDX-License-Identifier: GPL-2.0-or-later */
#import "MacRenderView.h"

@implementation MacRenderView {
    CALayer *_canvas;
}
- (instancetype)initWithFrame:(NSRect)frame renderSize:(NSSize)size
{
    if ((self = [super initWithFrame:frame])) {
        _renderSize = size;
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.blackColor.CGColor;
        self.layer.masksToBounds = YES;

        // ANGLE derives drawableSize from bounds * contentsScale and enables
        // autoresizing on the supplied layer. Its parent must therefore keep
        // guest-pixel bounds, even when AppKit resizes the view's root layer.
        _canvas = [CALayer layer];
        _canvas.bounds = (CGRect){CGPointZero, size};
        [self.layer addSublayer:_canvas];
        _surface = [CAMetalLayer layer];
        _surface.frame = _canvas.bounds;
        _surface.contentsScale = 1;
        _surface.drawableSize = size;
        [_canvas addSublayer:_surface];
        self.needsLayout = YES;
    }
    return self;
}
- (BOOL)isFlipped { return YES; }
- (void)setFrameSize:(NSSize)size
{
    [super setFrameSize:size];
    self.needsLayout = YES;
}
- (void)viewDidChangeBackingProperties
{
    [super viewDidChangeBackingProperties];
    self.needsLayout = YES;
}
- (void)layout
{
    [super layout];
    CGFloat scale = MIN(self.bounds.size.width / _renderSize.width,
                        self.bounds.size.height / _renderSize.height);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _canvas.position = [self convertPointToLayer:NSMakePoint(NSMidX(self.bounds), NSMidY(self.bounds))];
    _canvas.affineTransform = CGAffineTransformMakeScale(scale, scale);
    _canvas.hidden = scale <= 0;
    [CATransaction commit];
}
- (NSRect)contentRect
{
    return [self convertRectFromLayer:[_canvas convertRect:_canvas.bounds toLayer:self.layer]];
}
- (NSPoint)renderPointForViewPoint:(NSPoint)point
{
    return [self.layer convertPoint:[self convertPointToLayer:point] toLayer:_canvas];
}
@end
