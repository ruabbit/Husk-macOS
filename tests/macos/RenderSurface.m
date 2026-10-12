/* SPDX-License-Identifier: GPL-2.0-or-later */
#import "MacRenderView.h"
#import "MacGraphics.h"
#include <GLES2/gl2.h>
#include <math.h>

#define CHECK(x) do { if (!(x)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); return 1; } } while (0)
static BOOL near(CGFloat a, CGFloat b) { return fabs(a-b) < 0.001; }

int main(int argc, const char **argv) { @autoreleasepool {
    CHECK(argc == 2);
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,960,540)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    NSUInteger checks = 0;
    for (NSValue *size in @[[NSValue valueWithSize:NSMakeSize(1280,720)], [NSValue valueWithSize:NSMakeSize(640,400)]]) {
        NSSize pixels = size.sizeValue;
        NSSize initial = pixels.width == 1280 ? NSMakeSize(960,540) : NSMakeSize(800,500);
        [window setContentSize:initial];
        MacRenderView *view = [[MacRenderView alloc] initWithFrame:(NSRect){NSZeroPoint, initial} renderSize:pixels];
        NSView *web = view.webContainer;
        window.contentView = view;
        [view layoutSubtreeIfNeeded];
        NSError *error = nil;
        MacGraphics *graphics = [[MacGraphics alloc] initWithLibrary:@(argv[1]) layer:view.surface error:&error];
        if (!graphics) fprintf(stderr, "%s\n", error.description.UTF8String);
        CHECK(graphics);
        PFNGLCLEARCOLORPROC clearColor = [graphics symbol:"glClearColor"];
        PFNGLCLEARPROC clear = [graphics symbol:"glClear"];
        PFNGLENABLEPROC enable = [graphics symbol:"glEnable"];
        PFNGLDISABLEPROC disable = [graphics symbol:"glDisable"];
        PFNGLSCISSORPROC scissor = [graphics symbol:"glScissor"];
        PFNGLREADPIXELSPROC readPixels = [graphics symbol:"glReadPixels"];
        PFNGLFINISHPROC finish = [graphics symbol:"glFinish"];
        PFNGLGETERRORPROC getError = [graphics symbol:"glGetError"];
        CHECK(clearColor && clear && enable && disable && scissor && readPixels && finish && getError);
        NSArray<NSValue *> *sizes = @[ [NSValue valueWithSize:initial],
            [NSValue valueWithSize:NSMakeSize(1400,600)], [NSValue valueWithSize:NSMakeSize(960,900)],
            [NSValue valueWithSize:NSMakeSize(1173,697)], [NSValue valueWithSize:NSMakeSize(1920,1080)],
            [NSValue valueWithSize:initial] ];
        for (NSNumber *backingScale in @[@1, @2]) for (NSValue *size in sizes) {
            [window setContentSize:size.sizeValue];
            // Simulate both display backing scales without changing system settings.
            view.layer.contentsScale = backingScale.doubleValue;
            [view viewDidChangeBackingProperties];
            [view layoutSubtreeIfNeeded];
            [CATransaction flush];
            CHECK(!window.visible);
            CHECK(NSEqualSizes(view.bounds.size, size.sizeValue));
            NSRect rect = view.contentRect;
            CHECK(near(web.frame.origin.x,rect.origin.x)&&near(web.frame.origin.y,rect.origin.y)&&
                  near(web.frame.size.width,rect.size.width)&&near(web.frame.size.height,rect.size.height)&&
                  near(web.bounds.size.width,pixels.width)&&near(web.bounds.size.height,pixels.height)&&web.isFlipped);
            CHECK(near(NSMidX(rect), NSMidX(view.bounds)) && near(NSMidY(rect), NSMidY(view.bounds)));
            CHECK(near(rect.size.width / rect.size.height, pixels.width / pixels.height));
            CHECK(rect.origin.x >= -0.001 && rect.origin.y >= -0.001);
            CHECK(near(rect.size.width, view.bounds.size.width) || near(rect.size.height, view.bounds.size.height));
            const NSPoint points[] = {{NSMinX(rect),NSMinY(rect)}, {NSMaxX(rect),NSMinY(rect)},
                {NSMaxX(rect),NSMaxY(rect)}, {NSMinX(rect),NSMaxY(rect)}, {NSMidX(rect),NSMidY(rect)}};
            const NSPoint expected[] = {{0,0},{pixels.width,0},{pixels.width,pixels.height},{0,pixels.height},
                {pixels.width/2,pixels.height/2}};
            for (NSUInteger i=0; i<5; i++) {
                NSPoint point = [view renderPointForViewPoint:points[i]];
                CHECK(near(point.x, expected[i].x) && near(point.y, expected[i].y));
            }
            NSPoint outside = [view renderPointForViewPoint:NSMakePoint(NSMinX(rect)-1, NSMinY(rect)-1)];
            CHECK(outside.x < 0 && outside.y < 0);
            // Swap first: ANGLE checks layer bounds at drawable acquisition and
            // used to override the guest framebuffer on initial launch and resize.
            disable(GL_SCISSOR_TEST); clearColor(0,0,0,1); clear(GL_COLOR_BUFFER_BIT);
            CHECK([graphics present]);
            disable(GL_SCISSOR_TEST); clearColor(0,0,0,1); clear(GL_COLOR_BUFFER_BIT);
            CHECK(CGSizeEqualToSize(graphics.drawableSize, pixels));
            CHECK(CGSizeEqualToSize(view.surface.drawableSize, pixels));
            CHECK(CGSizeEqualToSize(view.surface.bounds.size, pixels));
            enable(GL_SCISSOR_TEST);
            const GLint corners[][2] = {{0,0},{(GLint)pixels.width-8,0},
                {(GLint)pixels.width-8,(GLint)pixels.height-8},{0,(GLint)pixels.height-8}};
            const GLubyte colors[][4] = {{255,0,0,255},{0,255,0,255},{0,0,255,255},{255,255,0,255}};
            for (NSUInteger i=0; i<4; i++) {
                scissor(corners[i][0],corners[i][1],8,8);
                clearColor(colors[i][0]/255.f,colors[i][1]/255.f,colors[i][2]/255.f,1);
                clear(GL_COLOR_BUFFER_BIT);
            }
            finish();
            for (NSUInteger i=0; i<4; i++) {
                GLubyte actual[4] = {0};
                readPixels(corners[i][0]+4,corners[i][1]+4,1,1,GL_RGBA,GL_UNSIGNED_BYTE,actual);
                CHECK(memcmp(actual,colors[i],4) == 0);
            }
            CHECK(getError() == GL_NO_ERROR);
            CHECK([graphics present]);
            checks++;
        }
        [graphics close];
    }
    [window close];
    printf("PASS %lu hidden ANGLE surface cases: initial/resize/1x/2x, full framebuffer corners, centered aspect fit and input mapping\n", (unsigned long)checks);
    return 0;
} }
