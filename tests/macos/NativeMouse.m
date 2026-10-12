/* SPDX-License-Identifier: GPL-2.0-or-later */
// Exercise the production GameView responders with native event objects. Only
// the Android boundary is recorded. No events are posted to the system and the
// window stays hidden; visible AppKit dispatch is a separate integration check.
#define main husk_runner_main
#define tl_ga_mouse recordMouse
#define tl_ga_mouse_relative recordRelative
#define tl_unity_touch recordUnityTouch
#define tl_unity_key recordUnityKey
#define tl_na_touch recordUnityTouch
#define tl_na_key recordNativeKey
#define tl_javaapp_touch recordUnityTouch
#define tl_javaapp_key recordNativeKey
#import "../../src/macos/NativeRunner/main.m"
#undef main
#undef tl_ga_mouse
#undef tl_ga_mouse_relative
#undef tl_unity_touch
#undef tl_unity_key
#undef tl_na_touch
#undef tl_na_key
#undef tl_javaapp_touch
#undef tl_javaapp_key

static struct { int action, buttons; float x,y,scroll; BOOL relative; } received[64];
static int count;
static int unityKey, unityKeyEvents;
void recordUnityKey(int code,bool down,int repeat) { (void)down;(void)repeat;unityKey=code;unityKeyEvents++; }
void recordNativeKey(int code,bool down) { recordUnityKey(code,down,0); }
void recordUnityTouch(int phase,int id,float x,float y) { (void)id;recordMouse(phase,x,y,0,0); }
void recordMouse(int action,float x,float y,int buttons,float scroll)
{
    if(count<64)received[count++]=(typeof(received[0])){action,buttons,x,y,scroll,NO};
}
void recordRelative(float x,float y,int buttons)
{
    recordMouse(2,x,y,buttons,0);received[count-1].relative=YES;
}
#define CHECK(x) do { if(!(x)) { fprintf(stderr,"FAIL line %d: %s (events=%d)\n",__LINE__,#x,count); return 1; } } while(0)
static BOOL deliver(GameView *view,NSEvent *event)
{
    @try {
        switch(event.type) {
            case NSEventTypeLeftMouseDown:[view mouseDown:event];break;
            case NSEventTypeLeftMouseUp:[view mouseUp:event];break;
            case NSEventTypeLeftMouseDragged:[view mouseDragged:event];break;
            case NSEventTypeRightMouseDown:[view rightMouseDown:event];break;
            case NSEventTypeRightMouseUp:[view rightMouseUp:event];break;
            case NSEventTypeRightMouseDragged:[view rightMouseDragged:event];break;
            case NSEventTypeOtherMouseDown:[view otherMouseDown:event];break;
            case NSEventTypeOtherMouseUp:[view otherMouseUp:event];break;
            case NSEventTypeOtherMouseDragged:[view otherMouseDragged:event];break;
            case NSEventTypeMouseMoved:[view mouseMoved:event];break;
            case NSEventTypeScrollWheel:[view scrollWheel:event];break;
            default:return NO;
        }
    } @catch(NSException *exception) {
        fprintf(stderr,"caught %s: %s\n",exception.name.UTF8String,exception.reason.UTF8String);
        return NO;
    }
    return YES;
}
static BOOL mouse(GameView *view,NSEventType type,NSPoint point)
{
    NSEvent *event=[NSEvent mouseEventWithType:type location:point modifierFlags:0
        timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:view.window.windowNumber context:nil
        eventNumber:1 clickCount:1 pressure:0];
    // The NSEvent factory defaults buttonNumber to zero even for right/other.
    // Set it on a private copy, without dispatching any system input.
    int button=type==NSEventTypeRightMouseDown||type==NSEventTypeRightMouseUp||type==NSEventTypeRightMouseDragged?1:
        type==NSEventTypeOtherMouseDown||type==NSEventTypeOtherMouseUp||type==NSEventTypeOtherMouseDragged?2:0;
    CGEventRef copy=CGEventCreateCopy(event.CGEvent);
    CGEventSetIntegerValueField(copy,kCGMouseEventButtonNumber,button);
    event=[NSEvent eventWithCGEvent:copy];CFRelease(copy);
    return deliver(view,event);
}

int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    minecraft=YES;surfaceWidth=1280;surfaceHeight=720;
    __attribute__((objc_precise_lifetime)) Runner *runner=[Runner new];runner.state=@"running";
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,960,540)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed=NO;runner.window=window;
    GameView *view=[[GameView alloc] initWithFrame:NSMakeRect(0,0,960,540) renderSize:NSMakeSize(1280,720)];
    view.runner=runner;runner.textInput=view;window.contentView=view;
    [view layoutSubtreeIfNeeded];[window makeFirstResponder:view];
    // Window points have a bottom-left origin; this maps to guest (640,405).
    NSPoint point=NSMakePoint(480,236.25);
    CHECK([view hitTest:point]==view && [view acceptsFirstMouse:nil]);
    CHECK(mouse(view,NSEventTypeLeftMouseDown,point));
    CHECK(mouse(view,NSEventTypeLeftMouseUp,point));
    CHECK(count==2);
    CHECK(received[0].action==0 && received[0].buttons==1 && received[0].scroll==0);
    CHECK(received[1].action==1 && received[1].buttons==0);
    CHECK(fabsf(received[0].x-640)<.01 && fabsf(received[0].y-405)<.01);
    puts("PASS queued click reaches the guest with event-derived buttons and mapped coordinates");

    count=0;
    CHECK(mouse(view,NSEventTypeLeftMouseDown,point));
    CHECK(mouse(view,NSEventTypeRightMouseDown,point));
    CHECK(mouse(view,NSEventTypeRightMouseDragged,point));
    CHECK(mouse(view,NSEventTypeLeftMouseUp,point));
    CHECK(mouse(view,NSEventTypeRightMouseUp,point));
    CHECK(mouse(view,NSEventTypeOtherMouseDown,point));
    CHECK(mouse(view,NSEventTypeOtherMouseDragged,point));
    CHECK(mouse(view,NSEventTypeOtherMouseUp,point));
    CHECK(count==8 && received[1].buttons==3 && received[2].action==2);
    CHECK(received[3].buttons==2 && received[4].buttons==0);
    CHECK(received[5].buttons==4 && received[6].action==2 && received[6].buttons==4 && received[7].buttons==0);
    puts("PASS simultaneous left/right buttons and middle-button drag/release");

    count=0;
    CHECK(mouse(view,NSEventTypeMouseMoved,point));
    // Construct a local wheel object only. It is never posted or injected.
    CGEventRef wheel=CGEventCreateScrollWheelEvent(NULL,kCGScrollEventUnitLine,1,3);
    CGEventSetLocation(wheel,CGPointMake(point.x,NSMaxY(NSScreen.screens.firstObject.frame)-point.y));
    NSEvent *scroll=[NSEvent eventWithCGEvent:wheel];CFRelease(wheel);
    CHECK(scroll.type==NSEventTypeScrollWheel && scroll.scrollingDeltaY!=0);
    CHECK(deliver(view,scroll));
    CHECK(count==2 && received[0].action==7 && received[0].scroll==0);
    CHECK(received[1].action==8 && received[1].buttons==0 && received[1].scroll==scroll.scrollingDeltaY);
    puts("PASS hover and wheel use only properties valid for their event type");

    count=0;runner.state=@"paused";
    CHECK(mouse(view,NSEventTypeLeftMouseDown,point));
    runner.state=@"running";
    CHECK(mouse(view,NSEventTypeLeftMouseDragged,point));
    CHECK(mouse(view,NSEventTypeLeftMouseUp,point));
    CHECK(count==0 && view.mouseButtons==0);
    CHECK(mouse(view,NSEventTypeLeftMouseDown,point));
    [runner windowDidResignKey:[NSNotification notificationWithName:NSWindowDidResignKeyNotification object:window]];
    CHECK(view.mouseButtons==0 && [runner.state isEqual:@"running"]);
    CHECK(mouse(view,NSEventTypeLeftMouseDragged,point));
    CHECK(mouse(view,NSEventTypeLeftMouseUp,point));
    CHECK(count==1);
    puts("PASS pause rejects presses and focus loss clears tracked buttons");

    count=0;
    [window setContentSize:NSMakeSize(1200,540)];[view layoutSubtreeIfNeeded];
    NSPoint bar=NSMakePoint(40,236.25),inside=NSMakePoint(600,236.25);
    CHECK(mouse(view,NSEventTypeLeftMouseDown,bar));
    CHECK(mouse(view,NSEventTypeLeftMouseDragged,inside));
    CHECK(mouse(view,NSEventTypeLeftMouseUp,inside));
    CHECK(count==0 && view.mouseButtons==0);
    CHECK(mouse(view,NSEventTypeLeftMouseDown,inside));
    CHECK(mouse(view,NSEventTypeLeftMouseDragged,bar));
    CHECK(mouse(view,NSEventTypeLeftMouseUp,bar));
    CHECK(count==3 && fabsf(received[0].x-640)<.01 && fabsf(received[0].y-405)<.01);
    CHECK(received[1].action==2 && received[1].x==0 && received[1].buttons==1);
    CHECK(received[2].action==1 && received[2].x==0 && received[2].buttons==0);
    puts("PASS resized letterbox ignores outside presses but completes inside-origin drags");

    count=0;
    CHECK(mouse(view,NSEventTypeLeftMouseDown,inside));
    runner.cursorCaptured=YES;
    BOOL moved=mouse(view,NSEventTypeMouseMoved,inside);
    BOOL dragged=mouse(view,NSEventTypeLeftMouseDragged,inside);
    runner.cursorCaptured=NO; // This test never changes the real cursor state.
    CHECK(moved && dragged && count==3);
    CHECK(received[1].relative && received[2].relative && received[2].buttons==1);
    CHECK(mouse(view,NSEventTypeLeftMouseUp,inside));
    CHECK(received[3].buttons==0);
    for(int profile=0;profile<3;profile++){
    minecraft=NO;unity=profile==0;nativeactivity=profile==1;javaapp=profile==2;unityKeyEvents=0;runner.loaded=YES;runner.heldKeys=[NSMutableSet new];count=0;
    CHECK(mouse(view,NSEventTypeLeftMouseDown,bar));
    CHECK(mouse(view,NSEventTypeLeftMouseDragged,inside));
    CHECK(mouse(view,NSEventTypeLeftMouseUp,inside));
    CHECK(count==0);
    CHECK(mouse(view,NSEventTypeLeftMouseDown,inside));
    CHECK(mouse(view,NSEventTypeLeftMouseDragged,bar));
    CHECK(mouse(view,NSEventTypeLeftMouseUp,bar));
    CHECK(count==3&&received[0].action==0&&received[1].action==1&&received[2].action==2);
    CHECK(fabsf(received[0].x-640)<.01&&fabsf(received[0].y-405)<.01&&received[2].x==0);
    CHECK(mouse(view,NSEventTypeRightMouseDown,inside));CHECK(count==3);
    [runner guestKey:35 down:YES repeat:NO];CHECK(unityKey==44&&unityKeyEvents==1);
    CHECK(mouse(view,NSEventTypeLeftMouseDown,inside));
    [runner windowDidResignKey:[NSNotification notificationWithName:NSWindowDidResignKeyNotification object:window]];
    CHECK(count==5&&received[4].action==3&&view.mouseButtons==0&&runner.heldKeys.count==0);
    CHECK(unityKeyEvents==2&&[runner.state isEqual:@"running"]);
    CHECK(mouse(view,NSEventTypeLeftMouseUp,inside));CHECK(count==5);
    puts("PASS native engine click/drag mapping, ignored bars/right button, keyboard and focus-loss cancellation");
    }
    CHECK(!window.visible);
    [window close];
    puts("PASS captured move/drag forwards relative input without changing the system cursor");
    return 0;
} }
