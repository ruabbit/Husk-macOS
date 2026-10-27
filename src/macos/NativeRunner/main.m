/* SPDX-License-Identifier: GPL-2.0-or-later */
#import <AppKit/AppKit.h>
#import <GameController/GameController.h>
#import <Security/SecTask.h>
#import <CommonCrypto/CommonDigest.h>
#import <WebKit/WebKit.h>
#import "MacGraphics.h"
#import "MacAudio.h"
#include "MacInput.h"
#include "HuskCore.h"
#include "husk-tl-ld.h"
#include "husk-tl-egl.h"
#include "husk-tl-gameactivity.h"
#include "husk-tl-unity.h"
#include "husk-tl-nativeactivity.h"
#import "MacJavaRuntime.h"
#import "MacDocumentPicker.h"
#import "husk-tl-dvm-web-host.h"
#import "MacNativeDrivers.h"
#import "MacGeode.h"
#include "husk-tl-vulkan.h"
#include "husk-tl-gamemaker.h"
#include "husk-tl-bionic.h"
#include "husk-tl-gamepad.h"
#include "husk-tl-audio.h"
#include "husk-tl-jni.h"
#include "MacDiagnostics.h"
#import "MacTextInput.h"
#import "MacRenderView.h"
#include <sys/stat.h>
#include <stdatomic.h>
#include <fcntl.h>
#include <signal.h>
#include <unistd.h>
#include <math.h>

static NSMutableArray<NSString *> *splitPaths;
static NSString *sessionID, *apkPath, *apkDigest, *checkpointPath, *gameTitle, *diagnostics;
static BOOL headless=YES, muted, automation, pauseInactive, hiddenWindow, fullScreen;
static int variant, exitStatus;
static BOOL minecraft, unity, nativeactivity, javaapp, javaNativeActivity, nativeDriver, ue4, portrait;
static NSString *packageName, *nativeLibrary, *activityClass, *geodeDirectory;
static NSUUID *javaWebStore;
static FILE *protocolOutput;
static BOOL guestRuntime(void) { return minecraft || unity || nativeactivity || javaapp || nativeDriver; }
static NSString *runtimeName(void) { return nativeDriver ? mac_driver_name() : ue4 ? @"ue4" : javaNativeActivity ? @"nativeactivity" : javaapp ? @"java" : nativeactivity ? @"nativeactivity" : unity ? @"unity" : minecraft ? @"minecraft" : @"orbit"; }
static void activityGuestExit(int status) {
    tl_log_line("%s: guest requested process exit %d before lifecycle acknowledgement",runtimeName().UTF8String,status);
    // The isolated process has no completed destroy receipt. Exit normally so
    // the supervisor reports the failure without a macOS crash dialog.
    _exit(70);
}
static CGFloat surfaceWidth=640, surfaceHeight=400;
static atomic_bool finished;
static MacGraphics *graphics;
void *mac_graphics_symbol(const char *name) { return [graphics symbol:name]; }

@interface Runner : NSObject <NSApplicationDelegate, NSWindowDelegate> {
@public
    MacInput input;
}
@property NSWindow *window;
@property NSTimer *timer;
@property MacAudio *audio;
@property NSString *state;
@property NSUInteger sequence, ticks;
@property NSUInteger keyEvents, pointerEvents, controllerEvents;
@property NSDictionary *lastClick;
@property NSDictionary *javaWebReceipt;
@property BOOL loaded, changingPause, lifecycleDestroyed;
@property BOOL requestedPause;
@property NSView *javaWebContainer;
@property NSDate *pauseStarted, *launchStarted;
@property dispatch_queue_t lifecycleQueue;
@property NSArray<NSString *> *runtimePaths;
@property NSMutableSet<NSNumber *> *heldKeys;
@property NSMapTable<GCController *,NSNumber *> *controllerSlots;
@property MacTextInput *textInput;
@property BOOL manualTextInput;
@property MacDocumentPicker *documentPicker;
@property BOOL captureRequested, cursorCaptured;
- (void)updateCursorCapture;
- (void)releaseCursor;
- (void)gameStopped:(BOOL)ok;
- (void)completeGameStop:(BOOL)ok;
- (void)guestKey:(unsigned)code down:(BOOL)down repeat:(BOOL)repeat;
@property int (*initialize)(int, const OrbitSave *);
@property void (*step)(const OrbitInput *);
@property void (*draw)(int);
@property void (*mix)(int16_t *, int);
@property void (*save)(OrbitSave *);
- (void)event:(NSString *)kind detail:(NSDictionary *)detail;
- (void)statusForRequest:(id)request;
- (void)stop:(NSString *)reason;
- (void)stopRuntime:(NSString *)reason;
- (void)togglePause:(id)sender;
- (void)toggleTextInput:(id)sender;
- (void)clearInput;
@end

@interface GameView : MacRenderView
@property(weak) Runner *runner;
@property int mouseButtons;
@end
@implementation GameView
- (NSView *)hitTest:(NSPoint)point {
    if(javaapp){
        NSPoint guest=[self renderPointForViewPoint:[self convertPoint:point fromView:self.superview]];
        bool tl_web_hit(float,float);
        if(!tl_web_hit(guest.x,guest.y))return NSPointInRect([self convertPoint:point fromView:self.superview],self.bounds)?self:nil;
    }
    return [super hitTest:point];
}
- (BOOL)acceptsFirstResponder {return YES;}
- (BOOL)acceptsFirstMouse:(NSEvent *)event {(void)event;return YES;}
- (void)keyDown:(NSEvent *)event
{
    if((minecraft||javaapp||unity||nativeDriver)&&[self.runner.state isEqual:@"running"]&&[self handleTextKey:event])return;
    if(event.modifierFlags & NSEventModifierFlagCommand) {[super keyDown:event];return;}
    if(!guestRuntime() && (event.keyCode==53 || event.keyCode==35)) {if(!event.isARepeat)[self.runner togglePause:nil];return;}
    if([self.runner.state isEqual:@"running"]) {[self.runner guestKey:event.keyCode down:YES repeat:event.isARepeat];}
}
- (void)keyUp:(NSEvent *)event {[self.runner guestKey:event.keyCode down:NO repeat:NO];}
- (void)flagsChanged:(NSEvent *)event {
    NSEventModifierFlags flag=0;
    switch(event.keyCode){case 56:case 60:flag=NSEventModifierFlagShift;break;case 58:case 61:flag=NSEventModifierFlagOption;break;case 59:case 62:flag=NSEventModifierFlagControl;break;default:return;}
    [self.runner guestKey:event.keyCode down:(event.modifierFlags&flag)!=0 repeat:NO];
}
- (void)pointer:(NSEvent *)event down:(BOOL)down
{
    NSPoint point=[self convertPoint:event.locationInWindow fromView:nil];
    self.inputAnchor=point;
    BOOL press=event.type==NSEventTypeLeftMouseDown||event.type==NSEventTypeRightMouseDown||event.type==NSEventTypeOtherMouseDown;
    BOOL release=event.type==NSEventTypeLeftMouseUp||event.type==NSEventTypeRightMouseUp||event.type==NSEventTypeOtherMouseUp;
    BOOL drag=event.type==NSEventTypeLeftMouseDragged||event.type==NSEventTypeRightMouseDragged||event.type==NSEventTypeOtherMouseDragged;
    if(minecraft) {
        if(![self.runner.state isEqual:@"running"])return;
        int button=0;
        if(press||release||drag) {
            NSInteger number=event.buttonNumber;
            if(number<0||number>=5)return;
            button=1<<(int)number;
            // Ignore releases/drags for a press rejected in the black bars,
            // while paused, or cleared when the window lost focus.
            if((release||drag)&&!(self.mouseButtons&button))return;
        }
        if(self.runner.cursorCaptured&&(event.type==NSEventTypeMouseMoved||drag)) {
            tl_ga_mouse_relative(event.deltaX,event.deltaY,self.mouseButtons);self.runner.pointerEvents++;return;
        }
        NSPoint guest=[self renderPointForViewPoint:point];
        float x=guest.x,y=guest.y;
        if(x<0||x>=surfaceWidth||y<0||y>=surfaceHeight) {
            if(press||event.type==NSEventTypeMouseMoved||event.type==NSEventTypeScrollWheel)return;
            x=MAX(0,MIN(surfaceWidth,x));y=MAX(0,MIN(surfaceHeight,y));
        }
        // Track the delivered stream: global pressedMouseButtons may already
        // be released when AppKit dispatches a queued mouse-down event.
        if(press)self.mouseButtons|=button;
        if(release)self.mouseButtons&=~button;
        if(press||release)self.runner.lastClick=@{@"type":@(event.type),@"windowX":@(event.locationInWindow.x),@"windowY":@(event.locationInWindow.y),
            @"x":@(x),@"y":@(y),@"buttons":@(self.mouseButtons),@"viewWidth":@(self.bounds.size.width),@"viewHeight":@(self.bounds.size.height)};
        int action=event.type==NSEventTypeScrollWheel?8:event.type==NSEventTypeMouseMoved?7:
            drag?2:down?0:1;
        // AppKit raises for scrollingDeltaY on ordinary mouse events.
        tl_ga_mouse(action,x,y,self.mouseButtons,event.type==NSEventTypeScrollWheel?event.scrollingDeltaY:0);
    } else if(unity||nativeactivity||javaapp||nativeDriver) {
        if(![self.runner.state isEqual:@"running"]||self.runner.changingPause||(!press&&!release&&!drag)||event.buttonNumber!=0)return;
        if((release||drag)&&!(self.mouseButtons&1))return;
        NSPoint guest=[self renderPointForViewPoint:point];
        if(guest.x<0||guest.x>=surfaceWidth||guest.y<0||guest.y>=surfaceHeight){
            if(press)return;
            guest.x=MAX(0,MIN(surfaceWidth-1,guest.x));guest.y=MAX(0,MIN(surfaceHeight-1,guest.y));
        }
        if(press)self.mouseButtons|=1;
        if(release)self.mouseButtons&=~1;
        if(javaapp)tl_javaapp_touch(press?0:release?2:1,0,guest.x,guest.y);
        else if(nativeDriver)mac_driver_touch(press?0:release?2:1,0,guest.x,guest.y);
        else if(nativeactivity)tl_na_touch(press?0:release?2:1,0,guest.x,guest.y);
        else tl_unity_touch(press?0:release?2:1,0,guest.x,guest.y);
        self.runner.lastClick=@{@"x":@(guest.x),@"y":@(guest.y),@"buttons":@(self.mouseButtons)};
    } else {
        NSPoint guest=[self renderPointForViewPoint:point];
        mac_input_pointer(&self.runner->input,guest.x,guest.y,surfaceWidth,surfaceHeight,down && [self.runner.state isEqual:@"running"]);
    }
    self.runner.pointerEvents++;
}
- (void)mouseDown:(NSEvent *)event {[self.window makeFirstResponder:self];[self pointer:event down:YES];}
- (void)mouseDragged:(NSEvent *)event {[self pointer:event down:YES];}
- (void)mouseUp:(NSEvent *)event {[self pointer:event down:NO];}
- (void)rightMouseDown:(NSEvent *)event {[self pointer:event down:YES];}
- (void)rightMouseDragged:(NSEvent *)event {[self pointer:event down:YES];}
- (void)rightMouseUp:(NSEvent *)event {[self pointer:event down:NO];}
- (void)otherMouseDown:(NSEvent *)event {[self pointer:event down:YES];}
- (void)otherMouseDragged:(NSEvent *)event {[self pointer:event down:YES];}
- (void)otherMouseUp:(NSEvent *)event {[self pointer:event down:NO];}
- (void)mouseMoved:(NSEvent *)event {if(minecraft)[self pointer:event down:NO];}
- (void)scrollWheel:(NSEvent *)event {if(minecraft)[self pointer:event down:NO];}
@end

static BOOL manualKeyboardSupported(void) {
    return minecraft||unity||javaapp||(nativeDriver&&[@[@"cocos",@"sdl"] containsObject:mac_driver_name()]);
}
static __weak Runner *javaHost;
static void javaRequestFinish(void) {
    // AppMain stays live for WebView save plugins until the lifecycle worker
    // requests phase 10. Never join AppMain from its own callback.
    dispatch_async(dispatch_get_main_queue(), ^{ [javaHost stop:@"guest-quit"]; });
}
static void javaKeyboard(int show,int inputType,int imeOptions) {
    (void)inputType;(void)imeOptions;
    dispatch_async(dispatch_get_main_queue(),^{javaHost.manualTextInput=NO;javaHost.textInput.textInputActive=show!=0;});
}
static void nativeKeyboard(int action) { javaKeyboard(action==1,1,0); }
static int unityKeyboardKind;
static void unityKeyboard(int action,int kind) {
    dispatch_async(dispatch_get_main_queue(),^{
        Runner *host=javaHost;
        if(!host || ![@[@"starting",@"running",@"paused"] containsObject:host.state])return;
        unityKeyboardKind=kind;host.manualTextInput=NO;
        [host.textInput receiveText:@"" selection:NSMakeRange(0,0) marked:NSMakeRange(NSNotFound,0)];
        host.textInput.textInputActive=action==1;
    });
}
static void javaSetClipboard(const char *text) {
    NSString *value=[NSString stringWithUTF8String:text?:""]?:@"";
    dispatch_async(dispatch_get_main_queue(),^{[NSPasteboard.generalPasteboard clearContents];[NSPasteboard.generalPasteboard setString:value forType:NSPasteboardTypeString];});
}
static char *javaGetClipboard(void) {
    __block NSString *value;void (^read)(void)=^{value=[NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString];};
    if(NSThread.isMainThread)read();else dispatch_sync(dispatch_get_main_queue(),read);
    return value?strdup(value.UTF8String):NULL;
}
static NSRange inputRange(int start,int end) {
    return start<0||end<start?NSMakeRange(NSNotFound,0):NSMakeRange((NSUInteger)start,(NSUInteger)(end-start));
}
static void javaPickDocuments(const char *mimeTypes, int multiple) {
    NSString *types = [NSString stringWithUTF8String:mimeTypes ?: "*/*"] ?: @"*/*";
    dispatch_async(dispatch_get_main_queue(), ^{
        Runner *host = javaHost;
        if (!host || [host.state isEqual:@"stopping"] || atomic_load(&finished)) return;
        // An Activity may request a document in onCreate, before the first frame.
        if (!headless && !hiddenWindow && host.window && !host.window.visible) {
            [host.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
        }
        [host.documentPicker presentForWindow:(headless||hiddenWindow)?nil:host.window mimeTypes:types multiple:multiple!=0
            completion:^(NSArray<NSString *> *paths) {
                if ([host.state isEqual:@"stopping"] || atomic_load(&finished)) return;
                const char **items = calloc(MAX((NSUInteger)1, paths.count), sizeof(*items));
                for (NSUInteger n=0; n<paths.count; n++) items[n]=paths[n].fileSystemRepresentation;
                tl_javaapp_documents_picked(items, (int)paths.count); free(items);
            }];
    });
}
static void hostTextState(void *context,const char *text,int start,int end,int cs,int ce) {
    Runner *runner=(__bridge Runner *)context;NSString *copy=[NSString stringWithUTF8String:text?:""]?:@"";
    dispatch_async(dispatch_get_main_queue(),^{[runner.textInput receiveText:copy selection:inputRange(start,end) marked:inputRange(cs,ce)];});
}
static void hostTextActive(void *context,bool active) {
    Runner *runner=(__bridge Runner *)context;
    dispatch_async(dispatch_get_main_queue(),^{runner.textInput.textInputActive=active;[runner event:@"text-input" detail:@{@"active":@(active)}];});
}
static void hostCursorLocked(void *context,bool locked) {
    Runner *runner=(__bridge Runner *)context;
    dispatch_async(dispatch_get_main_queue(),^{runner.captureRequested=locked;[runner updateCursorCapture];[runner event:@"cursor" detail:@{@"requested":@(locked),@"captured":@(runner.cursorCaptured)}];});
}

static NSDictionary *saveDictionary(OrbitSave save)
{
    return @{@"abi":@(save.abi),@"variant":@(save.variant),@"collected":@(save.collected),@"score":@(save.score),
             @"wins":@(save.wins),@"steps":@(save.steps),@"x":@(save.x),@"y":@(save.y)};
}
static BOOL restore(NSDictionary *object, OrbitSave *save)
{
    if(![object isKindOfClass:NSDictionary.class] || ![object[@"schema"] isEqual:@1])return NO;
    NSDictionary *game=object[@"game"];
    if(![game isKindOfClass:NSDictionary.class])return NO;
    for(NSString *key in @[@"abi",@"variant",@"collected",@"score",@"wins",@"steps",@"x",@"y"])
        if(![game[key] isKindOfClass:NSNumber.class] || !isfinite([game[key] doubleValue]) || [game[key] doubleValue]<0 || [game[key] doubleValue]>UINT32_MAX)return NO;
    *save=(OrbitSave){[game[@"abi"] unsignedIntValue],[game[@"variant"] unsignedIntValue],[game[@"collected"] unsignedIntValue],
        [game[@"score"] unsignedIntValue],[game[@"wins"] unsignedIntValue],[game[@"steps"] unsignedIntValue],[game[@"x"] floatValue],[game[@"y"] floatValue]};
    return YES;
}

static void activityJobFinished(void *context)
{
    void (^completion)(void)=CFBridgingRelease(context);
    dispatch_async(dispatch_get_main_queue(),completion);
}
static void activityStopped(void *context,bool ok)
{
    Runner *runner=CFBridgingRelease(context);
    dispatch_async(dispatch_get_main_queue(),^{[runner gameStopped:ok];});
}
static int androidKey(unsigned code)
{
    // macOS virtual key codes -> Android physical keys. Command stays in AppKit.
    static const int keys[128]={
        [0]=29,[1]=47,[2]=32,[3]=34,[4]=36,[5]=35,[6]=54,[7]=52,[8]=31,[9]=50,
        [11]=30,[12]=45,[13]=51,[14]=33,[15]=46,[16]=53,[17]=48,
        [18]=8,[19]=9,[20]=10,[21]=11,[22]=13,[23]=12,[25]=16,[26]=14,[28]=15,[29]=7,
        [31]=43,[32]=49,[34]=37,[35]=44,[36]=66,[37]=40,[38]=38,[40]=39,[45]=42,[46]=41,
        [48]=61,[49]=62,[51]=67,[53]=111,[56]=59,[58]=57,[59]=113,[60]=60,[61]=58,[62]=114,
        [117]=112,[123]=21,[124]=22,[125]=20,[126]=19};
    return code<128?keys[code]:0;
}
@implementation Runner
- (void)event:(NSString *)kind detail:(NSDictionary *)detail
{
    NSMutableDictionary *message=[@{@"protocol":@1,@"session":sessionID,@"pid":@(getpid()),@"seq":@(++self.sequence),
        @"event":kind,@"state":self.state?:@"starting",@"ticks":@(self.ticks)} mutableCopy];
    [message addEntriesFromDictionary:detail?:@{}];
    NSData *data=[NSJSONSerialization dataWithJSONObject:message options:0 error:NULL];
    if(data){fwrite(data.bytes,1,data.length,protocolOutput);fputc('\n',protocolOutput);fflush(protocolOutput);}
}
- (void)transition:(NSString *)state reason:(NSString *)reason
{
    self.state=state;[self event:@"state" detail:@{@"reason":reason}];
    self.window.title=[NSString stringWithFormat:@"%@%@ — Husk",gameTitle,[state isEqual:@"paused"]?@" · 已暂停":@""];
}
- (void)finish:(BOOL)success reason:(NSString *)reason
{
    if(atomic_exchange(&finished,true))return;
    [self releaseCursor];
    [self.timer invalidate];[self.audio close];[graphics close];
    exitStatus=success?0:70;
    [self transition:success?@"exited":@"failed" reason:reason];
    [self.window orderOut:nil];
    if(NSApp){[NSApp stop:nil];[NSApp postEvent:[NSEvent otherEventWithType:NSEventTypeApplicationDefined location:NSZeroPoint
        modifierFlags:0 timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0] atStart:NO];}
    CFRunLoopStop(CFRunLoopGetMain());
}
- (BOOL)checkpoint
{
    NSDictionary *object;
    if(guestRuntime()) {
        if(!self.lifecycleDestroyed)return NO;
        // The receipt describes the completed native lifecycle. The game's
        // own databases and preferences live in the adjacent data directory.
        NSMutableDictionary *receipt=[@{@"schema":@1,@"session":sessionID,@"runtime":runtimeName(),@"lifecycle":@"destroyed"} mutableCopy];
        if(javaapp){if(!self.javaWebReceipt)return NO;receipt[@"web"]=self.javaWebReceipt;}
        object=receipt;
    } else { OrbitSave save;self.save(&save);object=@{@"schema":@1,@"session":sessionID,@"game":saveDictionary(save)}; }
    NSData *data=[NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingSortedKeys error:NULL];
    NSString *temporary=[checkpointPath stringByAppendingFormat:@".%d.tmp",getpid()];
    int fd=open(temporary.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
    if(fd<0)return NO;
    const uint8_t *bytes=data.bytes;size_t left=data.length;BOOL ok=YES;
    while(left){ssize_t n=write(fd,bytes,left);if(n<0&&errno==EINTR)continue;if(n<=0){ok=NO;break;}left-=n;bytes+=n;}
    if(ok)ok=fsync(fd)==0;if(close(fd)!=0)ok=NO;
    if(ok)ok=rename(temporary.fileSystemRepresentation,checkpointPath.fileSystemRepresentation)==0;
    if(ok){int dir=open(checkpointPath.stringByDeletingLastPathComponent.fileSystemRepresentation,O_RDONLY);ok=dir>=0&&fsync(dir)==0;if(dir>=0)close(dir);}
    if(!ok)unlink(temporary.fileSystemRepresentation);
    return ok;
}
- (void)stop:(NSString *)reason
{
    if(atomic_load(&finished)||[self.state isEqual:@"stopping"])return;
    [self transition:@"stopping" reason:reason];[self clearInput];
    if(self.documentPicker) {
        [self.documentPicker closeWithCompletion:^{[self stopRuntime:reason];}];
    } else [self stopRuntime:reason];
}
- (void)stopRuntime:(NSString *)reason
{
    if((unity||nativeactivity||javaapp||nativeDriver) && self.lifecycleQueue) {
        // Initialization and join share a queue, so stop during loading cannot
        // race the loader or miss a thread that has not been created yet.
        dispatch_block_t stop = ^{
            tl_audio_set_muted(true);tl_audio_set_paused(false);
            if(nativeDriver)mac_driver_stop();else if(javaapp)tl_javaapp_stop();else if(nativeactivity)tl_na_stop();else tl_unity_stop();
            BOOL ok=nativeDriver?mac_driver_state()==TL_DRIVER_DESTROYED:javaapp?tl_javaapp_get_state()==TL_JAVA_DESTROYED:nativeactivity?tl_na_get_state()==TL_NA_DESTROYED:tl_unity_get_state()==TL_UNITY_DESTROYED;
            dispatch_async(dispatch_get_main_queue(),^{[self gameStopped:ok];});
        };
        dispatch_async(self.lifecycleQueue,^{
            if (!javaapp) { stop(); return; }
            // AppMain must keep polling phase 9 while page save handlers call
            // Java plugins. Only request Android destruction after that stage.
            dispatch_async(dispatch_get_main_queue(),^{
                tl_audio_set_muted(true);
                tl_web_prepare_for_host(^(BOOL prepared){
                    [self event:@"web-save-stage" detail:@{@"prepared":@(prepared)}];
                    dispatch_async(self.lifecycleQueue, stop);
                });
            });
        });return;
    }
    if(minecraft && self.loaded) {
        // Let the mixer drain during destruction; keep the output silent.
        tl_audio_set_muted(true);tl_audio_set_paused(false);
        tl_ga_stop(activityStopped,(__bridge_retained void *)self);return;
    }
    [self.timer invalidate];
    if(!self.loaded||![self checkpoint]){[self finish:NO reason:@"无法写入游戏存档；之前的存档保留。"];return;}
    [self event:@"checkpoint" detail:@{@"saved":@YES}];[self finish:YES reason:reason];
}
- (void)gameStopped:(BOOL)ok
{
    if(atomic_load(&finished))return;
    if(javaapp){
        if(ok)[self event:@"native-lifecycle" detail:@{@"lifecycle":@"destroyed"}];
        tl_web_close_for_host(^(BOOL detached,NSDictionary *receipt){
            if(atomic_load(&finished))return;
            self.javaWebReceipt=detached?receipt:nil;javaHost=nil;
            [self completeGameStop:ok&&detached];
        });return;
    }
    [self completeGameStop:ok];
}
- (void)completeGameStop:(BOOL)ok
{
    if(atomic_load(&finished))return;
    self.lifecycleDestroyed=ok;
    if(!ok||![self checkpoint]){[self finish:NO reason:@"游戏未能完成正常关闭；已有游戏数据保留。"];return;}
    [self event:@"storage-closed" detail:javaapp?@{@"lifecycle":@"destroyed",@"web":self.javaWebReceipt}:@{@"lifecycle":@"destroyed"}];
    [self finish:YES reason:javaapp?@"java-destroyed":unity?@"unity-destroyed":@"activity-destroyed"];
}
- (void)guestKey:(unsigned)code down:(BOOL)down repeat:(BOOL)repeat
{
    self.keyEvents++;
    if(!guestRuntime()){mac_input_key(&input,code,down);return;}
    int key=androidKey(code);if(!key)return;
    if(down){if(![self.state isEqual:@"running"]||self.changingPause)return;[self.heldKeys addObject:@(key)];}
    else [self.heldKeys removeObject:@(key)];
    if(nativeDriver)mac_driver_key(key,down);else if(javaapp)tl_javaapp_key(key,down);else if(nativeactivity)tl_na_key(key,down);else if(unity)tl_unity_key(key,down,repeat?1:0);else tl_ga_key(key,down,repeat?1:0);
}
- (void)clearInput {
    [self releaseCursor];
    if([self.textInput isKindOfClass:GameView.class])((GameView *)self.textInput).mouseButtons=0;
    mac_input_clear(&input);
    if(guestRuntime()&&self.loaded){
        for(NSNumber *key in self.heldKeys){if(nativeDriver)mac_driver_key(key.intValue,false);else if(javaapp)tl_javaapp_key(key.intValue,false);else if(nativeactivity)tl_na_key(key.intValue,false);else if(unity)tl_unity_key(key.intValue,false,0);else tl_ga_key(key.intValue,false,0);}
        [self.heldKeys removeAllObjects];
        if(nativeDriver)mac_driver_touch(3,0,0,0);else if(javaapp)tl_javaapp_touch(3,0,0,0);else if(nativeactivity)tl_na_touch(3,0,0,0);else if(unity)tl_unity_touch(3,0,0,0);else {tl_ga_touch(3,0,0,0);tl_ga_mouse_cancel();}
        tl_pad_state empty={0};for(int slot=0;slot<TL_PADS;slot++)if(tl_pad_connected(slot))tl_pad_update(slot,&empty);
    }
}
- (void)releaseCursor {
    if(!self.cursorCaptured)return;
    CGAssociateMouseAndMouseCursorPosition(true);[NSCursor unhide];self.cursorCaptured=NO;
}
- (void)updateCursorCapture {
    BOOL capture=self.captureRequested&&!headless&&!hiddenWindow&&self.window.keyWindow&&NSApp.active&&[self.state isEqual:@"running"]&&!atomic_load(&finished);
    if(!capture){[self releaseCursor];return;}
    if(!self.cursorCaptured&&CGAssociateMouseAndMouseCursorPosition(false)==kCGErrorSuccess){[NSCursor hide];self.cursorCaptured=YES;}
}
- (void)togglePause:(id)sender
{
    (void)sender;
    if(![self.state isEqual:@"running"]&&![self.state isEqual:@"paused"])return;
    BOOL pause=[self.state isEqual:@"running"];
    if(self.changingPause)return;
    [self clearInput];
    if(unity||nativeactivity||javaapp||nativeDriver){
        self.changingPause=YES;self.requestedPause=pause;self.pauseStarted=NSDate.date;
        if(!pause)tl_audio_set_paused(false);
        if(nativeDriver)mac_driver_pause(pause);else if(javaapp)tl_javaapp_set_paused(pause);else if(nativeactivity)tl_na_set_paused(pause);else tl_unity_set_paused(pause);return;
    }
    if(minecraft) {
        self.changingPause=YES;
        if(!pause)tl_audio_set_paused(false);
        tl_ga_set_paused(pause);
        void (^done)(void)=^{
            self.changingPause=NO;
            if([self.state isEqual:@"stopping"]||atomic_load(&finished))return;
            tl_audio_set_paused(pause);
            [self transition:pause?@"paused":@"running" reason:pause?@"pause-acknowledged":@"resume-acknowledged"];
            [self updateCursorCapture];
        };
        tl_ga_post(activityJobFinished,(__bridge_retained void *)[done copy]);return;
    }
    [self.audio setPaused:pause];
    [self transition:pause?@"paused":@"running" reason:pause?@"pause-acknowledged":@"resume-acknowledged"];
    self.draw(pause);[graphics present];
}
- (void)frame
{
    @autoreleasepool {
    if(unity||nativeactivity||javaapp||nativeDriver){
        self.ticks=nativeDriver?mac_driver_frames():javaapp?tl_javaapp_frames():nativeactivity?tl_na_frames():tl_unity_frames();
        tl_unity_state state=nativeDriver?(tl_unity_state)mac_driver_state():tl_unity_get_state();
        if(nativeactivity){
            switch(tl_na_get_state()){
                case TL_NA_RUNNING:state=TL_UNITY_RUNNING;break;
                case TL_NA_PAUSED:state=TL_UNITY_PAUSED;break;
                case TL_NA_STOPPING:state=TL_UNITY_STOPPING;break;
                case TL_NA_DESTROYED:state=TL_UNITY_DESTROYED;break;
                case TL_NA_FAILED:state=TL_UNITY_FAILED;break;
                default:state=TL_UNITY_STARTING;break;
            }
        }
        if(javaapp){
            switch(tl_javaapp_get_state()){
                case TL_JAVA_RUNNING:state=TL_UNITY_RUNNING;break;
                case TL_JAVA_PAUSED:state=TL_UNITY_PAUSED;break;
                case TL_JAVA_STOPPING:state=TL_UNITY_STOPPING;break;
                case TL_JAVA_DESTROYED:state=TL_UNITY_DESTROYED;break;
                case TL_JAVA_FAILED:state=TL_UNITY_FAILED;break;
                default:state=TL_UNITY_STARTING;break;
            }
        }
        if(state==TL_UNITY_FAILED){[self finish:NO reason:@"游戏运行或关闭失败，请查看日志。"];return;}
        if([self.state isEqual:@"stopping"])return;
        if(state==TL_UNITY_STOPPING||state==TL_UNITY_DESTROYED){[self stop:@"guest-quit"];return;}
        if([self.state isEqual:@"starting"]){
            if(self.loaded&&state==TL_UNITY_RUNNING&&self.ticks>0){
                [self transition:@"running" reason:@"game-ready"];
                if(!headless&&!hiddenWindow){[self.window makeKeyAndOrderFront:nil];if(fullScreen&&!(self.window.styleMask&NSWindowStyleMaskFullScreen))[self.window toggleFullScreen:nil];[NSApp activateIgnoringOtherApps:YES];}
            }else if(-self.launchStarted.timeIntervalSinceNow>90){[self finish:NO reason:@"游戏启动超时，请查看日志。"];}
        }
        if(self.changingPause){
            if(state==(self.requestedPause?TL_UNITY_PAUSED:TL_UNITY_RUNNING)){
                self.changingPause=NO;tl_audio_set_paused(self.requestedPause);
                [self transition:self.requestedPause?@"paused":@"running" reason:self.requestedPause?@"pause-acknowledged":@"resume-acknowledged"];
            }else if(-self.pauseStarted.timeIntervalSinceNow>15){[self finish:NO reason:@"游戏未响应暂停或继续请求，请查看日志。"];}
        }
        return;
    }
    if(minecraft){
        self.ticks=tl_ga_frames();
        if(tl_ga_failed()){[self finish:NO reason:@"Minecraft Activity 初始化失败，请查看日志。"];return;}
        if([self.state isEqual:@"starting"]&&tl_ga_ready()&&self.ticks>0){
            [self transition:@"running" reason:@"game-ready"];
            if(!headless&&!hiddenWindow){[self.window makeKeyAndOrderFront:nil];if(fullScreen&&!(self.window.styleMask&NSWindowStyleMaskFullScreen))[self.window toggleFullScreen:nil];[NSApp activateIgnoringOtherApps:YES];}
        }
        return;
    }
    if(![self.state isEqual:@"running"])return;
    OrbitInput current=mac_input_frame(&input);self.step(&current);self.ticks++;
    self.draw(0);int16_t samples[1600];self.mix(samples,800);[self.audio submit:samples frames:800];
    if(![graphics present])[self finish:NO reason:@"图形呈现失败。"];
    }
}
- (void)status
{
    [self statusForRequest:nil];
}
- (void)statusForRequest:(id)request
{
    OrbitSave save={0};if(self.loaded&&!guestRuntime())self.save(&save);
    NSMutableDictionary *detail=[@{@"game":saveDictionary(save),@"headless":@(headless),@"windowVisible":@(self.window.visible),
        @"runtime":runtimeName(),@"presentedFrames":@(tl_egl_frames_presented()+tl_vk_frames_presented()),@"surfaceWidth":@(surfaceWidth),@"surfaceHeight":@(surfaceHeight),@"pauseWhenInactive":@(pauseInactive),@"audioFrames":@(guestRuntime()?tl_audio_frames():self.audio.sampleFrames),@"audioNonzero":@(guestRuntime()?tl_audio_nonzero_samples():self.audio.nonzeroSamples),@"controllers":@(GCController.controllers.count),
        @"keys":@(self.keyEvents),@"pointer":@(self.pointerEvents),@"lastClick":self.lastClick?:@{},@"controller":@(self.controllerEvents),@"textActive":@(self.textInput.textInputActive),@"captureRequested":@(self.captureRequested),@"cursorCaptured":@(self.cursorCaptured),@"heldKeys":@(self.heldKeys.count)} mutableCopy];
    // Automation status replies must be distinguishable from periodic heartbeats.
    if(automation&&[request isKindOfClass:NSString.class]&&[request length]<=64)detail[@"request"]=request;
    [self event:@"status" detail:detail];
}
- (void)command:(NSDictionary *)message
{
    if(![message isKindOfClass:NSDictionary.class]||![message[@"session"] isEqual:sessionID]||![message[@"protocol"] isEqual:@1]) {
        [self event:@"rejected" detail:@{@"reason":@"session-or-protocol-mismatch"}];return;
    }
    NSString *command=message[@"command"];
    if([command isEqual:@"stop"]) [self stop:@"controller-stop"];
    else if([command isEqual:@"pause"]&&[self.state isEqual:@"running"]) [self togglePause:nil];
    else if([command isEqual:@"resume"]&&[self.state isEqual:@"paused"]) [self togglePause:nil];
    else if([command isEqual:@"status"]) [self statusForRequest:message[@"request"]];
    else if([command isEqual:@"keyboard"]&&manualKeyboardSupported()&&[self.state isEqual:@"running"]) [self toggleTextInput:nil];
    else if(automation&&javaapp&&[command isEqual:@"evaluate"]&&[self.state isEqual:@"running"]&&[message[@"script"] isKindOfClass:NSString.class]) {
        tl_web_evaluate_for_host([message[@"view"] intValue],message[@"script"],^(id value,NSError *error){
            if(!atomic_load(&finished))[self event:@"evaluation" detail:@{@"request":message[@"request"]?:@"",@"value":value?:NSNull.null,@"error":error.localizedDescription?:@""}];
        });
    }
    else if([command isEqual:@"window"]&&self.window&&!hiddenWindow&&!headless) {
        NSString *action=message[@"action"];
        if([action isEqual:@"show"]){[self.window deminiaturize:nil];[self.window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];}
        else if([action isEqual:@"minimize"])[self.window miniaturize:nil];
        else if([action isEqual:@"zoom"])[self.window zoom:nil];
        else if([action isEqual:@"fullscreen"])[self.window toggleFullScreen:nil];
        else {[self event:@"rejected" detail:@{@"reason":@"unknown-window-action"}];return;}
        [self event:@"window" detail:@{@"action":action}];
    }
    else if([command isEqual:@"set-pause-inactive"]&&[message[@"enabled"] isKindOfClass:NSNumber.class]) {
        pauseInactive=[message[@"enabled"] boolValue];
        [self event:@"pause-policy" detail:@{@"pauseWhenInactive":@(pauseInactive)}];
    }
    else if(automation&&[command isEqual:@"input"]&&[self.state isEqual:@"running"]) {
        NSString *source=message[@"source"];
        if([source isEqual:@"key"]) {[self guestKey:[message[@"code"] unsignedIntValue] down:[message[@"down"] boolValue] repeat:NO];}
        else if(minecraft&&[source isEqual:@"touch"]) {tl_ga_touch([message[@"phase"] intValue],0,[message[@"x"] floatValue],[message[@"y"] floatValue]);self.pointerEvents++;}
        else if((unity||nativeactivity||javaapp||nativeDriver)&&[source isEqual:@"touch"]) {
            if(javaapp)tl_javaapp_touch([message[@"phase"] intValue],0,[message[@"x"] floatValue],[message[@"y"] floatValue]);
            else if(nativeDriver)mac_driver_touch([message[@"phase"] intValue],0,[message[@"x"] floatValue],[message[@"y"] floatValue]);
            else if(nativeactivity)tl_na_touch([message[@"phase"] intValue],0,[message[@"x"] floatValue],[message[@"y"] floatValue]);
            else tl_unity_touch([message[@"phase"] intValue],0,[message[@"x"] floatValue],[message[@"y"] floatValue]);self.pointerEvents++;}
        else if(minecraft&&[source isEqual:@"mouse"]) {tl_ga_mouse([message[@"action"] intValue],[message[@"x"] floatValue],[message[@"y"] floatValue],[message[@"buttons"] intValue],[message[@"scroll"] floatValue]);self.pointerEvents++;}
        else if(minecraft&&[source isEqual:@"relative-mouse"]) {tl_ga_mouse_relative([message[@"x"] floatValue],[message[@"y"] floatValue],[message[@"buttons"] intValue]);self.pointerEvents++;}
        else if(manualKeyboardSupported()&&[source isEqual:@"text"]&&self.textInput.textInputActive&&[message[@"text"] isKindOfClass:NSString.class]) {
            if([message[@"selectAll"] boolValue])[self.textInput selectAll:nil];
            [self.textInput insertText:message[@"text"] replacementRange:NSMakeRange(NSNotFound,0)];
        }
        else if(guestRuntime()&&[source isEqual:@"controller"]) {
            int slot=[message[@"slot"] intValue];if(slot<0||slot>=TL_PADS)return;
            if(!tl_pad_connected(slot))tl_pad_connect(slot,"Husk Test Controller");
            tl_pad_state pad={.buttons=[message[@"buttons"] unsignedIntValue],.lx=[message[@"x"] floatValue],.ly=[message[@"y"] floatValue],.rx=[message[@"rx"] floatValue],.ry=[message[@"ry"] floatValue],.lt=[message[@"lt"] floatValue],.rt=[message[@"rt"] floatValue]};
            tl_pad_update(slot,&pad);self.controllerEvents++;
        }
        else if(guestRuntime()&&[source isEqual:@"controller-disconnect"]) {tl_pad_disconnect([message[@"slot"] intValue]);}
        else if([source isEqual:@"pointer"]) {mac_input_pointer(&input,[message[@"x"] floatValue],[message[@"y"] floatValue],640,400,[message[@"down"] boolValue]);self.pointerEvents++;}
        else if([source isEqual:@"controller"]) {mac_input_controller(&input,[message[@"x"] floatValue],[message[@"y"] floatValue],[message[@"restart"] boolValue]);self.controllerEvents++;}
        else if([source isEqual:@"focus-lost"]) [self windowDidResignKey:[NSNotification notificationWithName:NSWindowDidResignKeyNotification object:self.window]];
        [self event:@"input" detail:nil];
    }
    else if(automation&&!guestRuntime()&&[command isEqual:@"step"]) {
        int frames=MAX(0,MIN(600,[message[@"frames"] intValue]));
        for(int i=0;i<frames&&!atomic_load(&finished);i++)[self frame];
        [self statusForRequest:message[@"request"]];
    }
    else if(automation&&diagnostics&&[command isEqual:@"capture"]) {
        // Only a basename under the launch-time diagnostic directory is accepted.
        NSString *name=message[@"name"];
        if(![name isKindOfClass:NSString.class]||![name isEqual:name.lastPathComponent]||![name.pathExtension isEqual:@"png"])return;
        BOOL ok=NO;
        if(guestRuntime()){
            NSData *data=[NSData dataWithContentsOfFile:[diagnostics stringByAppendingPathComponent:@"frames/latest.bmp"]];
            NSBitmapImageRep *bitmap=data?[NSBitmapImageRep imageRepWithData:data]:nil;
            NSData *png=[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            ok=png&&[png writeToFile:[diagnostics stringByAppendingPathComponent:name] options:NSDataWritingAtomic error:NULL];
        }else{self.draw([self.state isEqual:@"paused"]);ok=[graphics capture:[diagnostics stringByAppendingPathComponent:name]];}
        [self event:@"capture" detail:@{@"saved":@(ok),@"name":name}];
    }
    else if(automation&&[command isEqual:@"exit-unexpectedly"]) _exit(74); // No signal/crash dialog; supervisor failure-path test.
    else [self event:@"rejected" detail:@{@"reason":@"invalid-state-or-command"}];
}
- (BOOL)validateFixture
{
    if(guestRuntime()){
        // The library's import hash remains the integrity contract. Compatibility
        // is checked independently here before any Android code is loaded.
        NSArray<NSString *> *paths=[@[apkPath] arrayByAddingObjectsFromArray:splitPaths];
        NSMutableArray<NSString *> *hashes=[NSMutableArray new];
        const char *rawPaths[TL_LD_MAX_APKS];
        for(NSUInteger i=0;i<paths.count;i++){
            NSInputStream *stream=[NSInputStream inputStreamWithFileAtPath:paths[i]];[stream open];
            CC_SHA256_CTX context;CC_SHA256_Init(&context);uint8_t buffer[65536],digest[CC_SHA256_DIGEST_LENGTH];NSInteger count;
            while((count=[stream read:buffer maxLength:sizeof(buffer)])>0)CC_SHA256_Update(&context,buffer,(CC_LONG)count);
            [stream close];if(count<0)return NO;CC_SHA256_Final(digest,&context);
            NSMutableString *hex=[NSMutableString string];for(unsigned j=0;j<sizeof(digest);j++)[hex appendFormat:@"%02x",digest[j]];
            [hashes addObject:hex];rawPaths[i]=paths[i].fileSystemRepresentation;
        }
        if (![[hashes componentsJoinedByString:@":"] isEqual:apkDigest]) return NO;
        char *raw=husk_tl_scan(rawPaths,(int)paths.count);
        if (!raw) return NO;
        NSData *data=[NSData dataWithBytes:raw length:strlen(raw)];husk_tl_free(raw);
        NSDictionary *scan=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        if(javaapp)return mac_java_accepts_scan(scan) && (!javaNativeActivity || [scan[@"engine"] isEqual:@"NativeActivity"]);
        if(nativeDriver)return mac_driver_accepts_scan(scan);
        return [scan isKindOfClass:NSDictionary.class] && [scan[@"ok"] boolValue] &&
            [scan[@"hasManifest"] boolValue] && [scan[@"engine"] isKindOfClass:NSString.class] &&
            (ue4?[scan[@"engine"] isEqual:@"Unreal Engine"]:nativeactivity?[scan[@"engine"] isEqual:@"NativeActivity"]:unity?([scan[@"engine"] hasPrefix:@"Unity"]&&![scan[@"engine"] isEqual:@"Unity 6"]):[scan[@"engine"] isEqual:@"Minecraft"]) &&
            [scan[@"abis"] isKindOfClass:NSArray.class] && [scan[@"abis"] containsObject:@"arm64-v8a"];
    }
    NSString *catalogPath=[NSBundle.mainBundle pathForResource:@"fixture-catalog" ofType:@"json"];
    NSDictionary *catalog=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:catalogPath]?:[NSData data] options:0 error:NULL];
    size_t size=0;void *bytes=husk_tl_read_entry(apkPath.fileSystemRepresentation,"lib/arm64-v8a/libhusk_orbit.so",4<<20,&size);
    if(!bytes||![catalog isKindOfClass:NSDictionary.class]){if(bytes)husk_tl_free(bytes);return NO;}
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(bytes,(CC_LONG)size,digest);husk_tl_free(bytes);
    NSMutableString *hex=[NSMutableString string];for(int i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[hex appendFormat:@"%02x",digest[i]];
    return [catalog[@"sha256"] isEqual:hex];
}
- (void)setupController:(GCController *)controller
{
    if(!controller.extendedGamepad)return;
    if(!self.controllerSlots)self.controllerSlots=[NSMapTable strongToStrongObjectsMapTable];
    if([self.controllerSlots objectForKey:controller])return;
    int slot=-1;
    NSArray<NSNumber *> *used=self.controllerSlots.objectEnumerator.allObjects;
    for(int i=0;i<TL_PADS;i++)if(![used containsObject:@(i)]){slot=i;break;}
    if(slot<0)return;
    [self.controllerSlots setObject:@(slot) forKey:controller];
    controller.handlerQueue=dispatch_get_main_queue();
    __weak Runner *weak=self;
    NSString *controllerName=controller.vendorName?:@"Game Controller";
    if(guestRuntime())tl_pad_connect(slot,controllerName.UTF8String);
    controller.extendedGamepad.valueChangedHandler=^(GCExtendedGamepad *pad,GCControllerElement *element){
        Runner *self=weak;if(!self.window.keyWindow||![self.state isEqual:@"running"]||self.changingPause)return;
        if(guestRuntime()){
            if(!tl_pad_connected(slot))return;
            tl_pad_state state={.lx=pad.leftThumbstick.xAxis.value,.ly=-pad.leftThumbstick.yAxis.value,.rx=pad.rightThumbstick.xAxis.value,.ry=-pad.rightThumbstick.yAxis.value,.lt=pad.leftTrigger.value,.rt=pad.rightTrigger.value};
            GCControllerButtonInput *buttons[]={pad.buttonA,pad.buttonB,pad.buttonX,pad.buttonY,pad.leftShoulder,pad.rightShoulder,pad.leftThumbstickButton,pad.rightThumbstickButton,pad.buttonMenu,pad.buttonOptions,nil,pad.dpad.up,pad.dpad.down,pad.dpad.left,pad.dpad.right};
            for(int i=0;i<TL_PAD_BUTTONS;i++)if(buttons[i].pressed)state.buttons|=1u<<i;
            tl_pad_update(slot,&state);self.controllerEvents++;return;
        }
        float x=pad.leftThumbstick.xAxis.value+pad.dpad.xAxis.value,y=pad.leftThumbstick.yAxis.value+pad.dpad.yAxis.value;
        mac_input_controller(&self->input,x,y,element==pad.buttonA&&pad.buttonA.pressed);self.controllerEvents++;
    };
    controller.extendedGamepad.buttonMenu.pressedChangedHandler=^(GCControllerButtonInput *button,float value,BOOL pressed){
        (void)button;(void)value;Runner *self=weak;if(!guestRuntime()&&pressed&&self.window.keyWindow)[self togglePause:nil];
    };
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    (void)notification;
    SecTaskRef task=SecTaskCreateFromSelf(NULL);
    CFTypeRef entitlement=task?SecTaskCopyValueForEntitlement(task,CFSTR("com.apple.security.cs.allow-unsigned-executable-memory"),NULL):NULL;
    BOOL allowed=entitlement&&CFEqual(entitlement,kCFBooleanTrue);if(entitlement)CFRelease(entitlement);if(task)CFRelease(task);
    if(!allowed){[self finish:NO reason:@"运行组件缺少执行内存权限，请重新构建或安装。"];return;}
    if(![self validateFixture]){[self finish:NO reason:@"游戏文件校验或运行入口检查未通过，请重新导入完整 APK。"];return;}
    CAMetalLayer *layer=nil;
    if(!headless) {
        NSRect initialFrame=NSMakeRect(0,0,guestRuntime()?(portrait?405:960):800,guestRuntime()?(portrait?720:540):500);
        self.window=[[NSWindow alloc] initWithContentRect:initialFrame styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
        self.window.acceptsMouseMovedEvents=YES;self.window.delegate=self;self.window.restorable=NO;self.window.releasedWhenClosed=NO;self.window.contentMinSize=guestRuntime()?(portrait?NSMakeSize(270,480):NSMakeSize(854,480)):NSMakeSize(640,400);
        GameView *view=[[GameView alloc] initWithFrame:initialFrame renderSize:NSMakeSize(surfaceWidth,surfaceHeight)];view.runner=self;self.window.contentView=view;
        self.textInput=view;
        [view layoutSubtreeIfNeeded];layer=view.surface;
        self.window.title=gameTitle;[self.window center];[self.window makeFirstResponder:view];
        NSMenu *main=[NSMenu new];NSMenuItem *root=[NSMenuItem new];[main addItem:root];
        NSMenu *menu=[[NSMenu alloc] initWithTitle:@"Husk Game"];
        NSMenuItem *pause=[menu addItemWithTitle:@"暂停 / 继续" action:@selector(togglePause:) keyEquivalent:@"p"];pause.target=self;
        if(manualKeyboardSupported()){NSMenuItem *keyboard=[menu addItemWithTitle:@"文字输入 / 键盘控制" action:@selector(toggleTextInput:) keyEquivalent:@"t"];keyboard.target=self;}
        [menu addItem:NSMenuItem.separatorItem];
        [menu addItemWithTitle:@"结束游戏" action:@selector(terminate:) keyEquivalent:@"q"];
        root.submenu=menu;NSApp.mainMenu=main;
    }
    // Runner.app is embedded at Contents/Helpers; Frameworks belongs to the outer app.
    NSString *frameworks=[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"../../Frameworks"];
    NSString *angle=[frameworks stringByAppendingPathComponent:@"libANGLE-shared.dylib"];
    if(guestRuntime()){
        NSString *data=[checkpointPath.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"data"];
        [NSFileManager.defaultManager createDirectoryAtPath:data withIntermediateDirectories:YES attributes:nil error:NULL];
        NSString *frames=diagnostics?[diagnostics stringByAppendingPathComponent:@"frames"]:nil;
        if(frames)[NSFileManager.defaultManager createDirectoryAtPath:frames withIntermediateDirectories:YES attributes:nil error:NULL];
        self.heldKeys=[NSMutableSet new];tl_audio_set_muted(muted||headless);tl_audio_install();
        if(!self.textInput)self.textInput=[[MacTextInput alloc] initWithFrame:NSZeroRect];
        __weak Runner *weakSelf=self;
        self.textInput.textChanged=^(NSString *text,NSRange selection,NSRange marked){
            Runner *self=weakSelf;if(!self||![self.state isEqual:@"running"])return;
            tl_ga_text(text.UTF8String,(int)selection.location,(int)NSMaxRange(selection),marked.location==NSNotFound?-1:(int)marked.location,marked.location==NSNotFound?-1:(int)NSMaxRange(marked));
        };
        self.textInput.textCommand=^(unsigned code){[weakSelf guestKey:code down:YES repeat:NO];[weakSelf guestKey:code down:NO repeat:NO];};
        if(unity){
            javaHost=self;tl_unity_set_keyboard_handler(unityKeyboard);
            self.textInput.committedText=^(NSString *text){
                if([weakSelf.state isEqual:@"running"])tl_unity_insert_text(text.UTF8String);
            };
            self.textInput.textCommand=^(unsigned code){
                Runner *host=weakSelf;if(![host.state isEqual:@"running"])return;
                if(code==51)tl_unity_delete_backward();
                else if(code==36 && (unityKeyboardKind&0x200))tl_unity_insert_text("\n");
                else if(code==36 || code==53){
                    tl_unity_finish_text(code==36);host.textInput.textInputActive=NO;
                    [host.textInput receiveText:@"" selection:NSMakeRange(0,0) marked:NSMakeRange(NSNotFound,0)];
                }
            };
        }
        if(nativeDriver){
            javaHost=self; mac_driver_keyboard(nativeKeyboard);
            self.textInput.committedText=^(NSString *text){
                if(![weakSelf.state isEqual:@"running"])return;
                if(weakSelf.manualTextInput&&[mac_driver_name() isEqual:@"sdl"])
                    mac_send_android_text_keys(text,^(int code,BOOL down){mac_driver_key(code,down);});
                else mac_driver_text(text.UTF8String);
            };
            self.textInput.textCommand=^(unsigned code){if(code==51)mac_driver_delete();else{[weakSelf guestKey:code down:YES repeat:NO];[weakSelf guestKey:code down:NO repeat:NO];}};
        }
        if(javaapp){
            javaHost=self;
            self.documentPicker=[[MacDocumentPicker alloc] initWithDataDirectory:data];
            if(!tl_web_set_host_store(javaWebStore)){[self finish:NO reason:@"Java Web 存档标识无效。"];return;}
            self.textInput.committedText=^(NSString *text){if([weakSelf.state isEqual:@"running"])tl_javaapp_text(text.UTF8String);};
            self.textInput.textCommand=^(unsigned code){
                if(code==51)tl_javaapp_text_delete();else if(code==36)tl_javaapp_text_action();
                else if(code==53&&weakSelf.manualTextInput)[weakSelf toggleTextInput:nil];
                else {[weakSelf guestKey:code down:YES repeat:NO];[weakSelf guestKey:code down:NO repeat:NO];}
            };
            // The shared WebKit host attaches to this canvas; never create the harness's visible fallback window.
            self.javaWebContainer=[self.textInput isKindOfClass:MacRenderView.class]?[(MacRenderView *)self.textInput webContainer]:[[NSView alloc] initWithFrame:NSMakeRect(0,0,surfaceWidth,surfaceHeight)];
            void tl_web_attach(void *,void *,float,bool);tl_web_attach((__bridge void *)self.textInput,(__bridge void *)self.javaWebContainer,1,true);
        }
        if(minecraft){tl_ga_input_host host={hostTextState,hostTextActive,hostCursorLocked,(__bridge void *)self};tl_ga_set_input_host(&host);}
        if(diagnostics){setenv("TL_GAME_DIAGNOSTICS","1",1);setenv("TL_DL_TRACE","1",1);setenv("TL_GL_SHADER_DUMP",diagnostics.fileSystemRepresentation,1);}
        NSString *runtimeRoot=[[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"../../Resources/JavaRuntime"] stringByStandardizingPath];
        if(!mac_runtime_configure(runtimeRoot)){[self finish:NO reason:@"Android 系统资源缺失或损坏，请重新构建 Husk。"] ;return;}
        tl_ld_set_verbosity(2);tl_jni_set_trace(0);tl_egl_offscreen_windows(headless);
        for(NSString *split in splitPaths)tl_ld_queue_split(split.fileSystemRepresentation);
        if(unity||nativeactivity||javaapp||nativeDriver){
            self.runtimePaths=@[apkPath,data,packageName,angle,frames?:@""];
            self.launchStarted=NSDate.date;self.lifecycleQueue=dispatch_queue_create("org.husk.game.lifecycle",DISPATCH_QUEUE_SERIAL);
            tl_guest_exit_hook=activityGuestExit;
            dispatch_async(self.lifecycleQueue,^{ @autoreleasepool {
                tl_unity_config configuration={.apk_path=self.runtimePaths[0].fileSystemRepresentation,
                    .data_dir=self.runtimePaths[1].fileSystemRepresentation,.package_name=self.runtimePaths[2].UTF8String,
                    .width=(int)surfaceWidth,.height=(int)surfaceHeight,.metal_layer=(__bridge void *)layer,
                    .angle_egl=self.runtimePaths[3].fileSystemRepresentation,.frame_dir=frames?self.runtimePaths[4].fileSystemRepresentation:NULL,.frame_every=-60};
                BOOL ok;
                if(nativeDriver){
                    NSError *error=nil;
                    ok=mac_geode_configure(geodeDirectory,apkPath,apkDigest,packageName,mac_driver_name(),data,&error);
                    if(!ok)tl_log_line("geode: %s",error.localizedDescription.UTF8String);
                    if(ok)ok=mac_driver_start(&configuration,activityClass,[frameworks stringByAppendingPathComponent:@"MoltenVK.framework/MoltenVK"]);
                }else if(javaapp){
                    NSString *root=runtimeRoot;
                    NSString *fw=[root stringByAppendingPathComponent:@"framework-res.apk"];
                    tl_javaapp_config javaConfiguration={.apk_path=configuration.apk_path,.data_dir=configuration.data_dir,
                        .package_name=configuration.package_name,.width=configuration.width,.height=configuration.height,.density=2,
                        .metal_layer=configuration.metal_layer,.angle_egl=configuration.angle_egl,
                        .vulkan_library=[frameworks stringByAppendingPathComponent:@"MoltenVK.framework/MoltenVK"].fileSystemRepresentation,
                        .frame_dir=configuration.frame_dir,.frame_every=configuration.frame_every,.framework_res=fw.fileSystemRepresentation,
                        .show_keyboard=javaKeyboard,.set_clipboard=javaSetClipboard,.get_clipboard=javaGetClipboard,
                        .pick_documents=javaPickDocuments,.request_finish=javaRequestFinish};
                    ok=mac_java_start(root,&javaConfiguration);
                }else if(nativeactivity){
                    tl_ga_config nativeConfiguration={.apk_path=configuration.apk_path,.data_dir=configuration.data_dir,
                        .package_name=configuration.package_name,.width=configuration.width,.height=configuration.height,
                        .metal_layer=configuration.metal_layer,.angle_egl=configuration.angle_egl,
                        .frame_dir=configuration.frame_dir,.frame_every=configuration.frame_every};
                    tl_vk_configure([frameworks stringByAppendingPathComponent:@"MoltenVK.framework/MoltenVK"].fileSystemRepresentation,frames.fileSystemRepresentation,60);
                    tl_na_set_library(nativeLibrary.UTF8String);
                    ok=tl_na_start(&nativeConfiguration)&&tl_na_run();
                }else{tl_unity_register_pad_sink();ok=tl_unity_start(&configuration)&&tl_unity_run();}
                dispatch_async(dispatch_get_main_queue(),^{
                    self.loaded=ok;
                    if(!ok)[self finish:NO reason:@"游戏运行时加载失败，请查看日志。"];
                });
            }});
        }else{
        tl_ga_config configuration={.apk_path=apkPath.fileSystemRepresentation,.data_dir=data.fileSystemRepresentation,
            .package_name="com.mojang.minecraftpe",.width=(int)surfaceWidth,.height=(int)surfaceHeight,
            .metal_layer=(__bridge void *)layer,.angle_egl=angle.fileSystemRepresentation,.frame_dir=frames.fileSystemRepresentation,.frame_every=-60};
        if(!tl_ga_start(&configuration)){[self finish:NO reason:@"Minecraft 运行时加载失败，请查看日志。"];return;}
        if(!tl_ga_run()){[self finish:NO reason:@"Minecraft 活动线程启动失败。"];return;}
        self.loaded=YES;
        }
    }else{
    if(!tl_egl_init(angle.fileSystemRepresentation,NULL,NULL,0)){[self finish:NO reason:@"图形入口加载失败。"];return;}
    NSError *error=nil;graphics=[[MacGraphics alloc] initWithLibrary:[frameworks stringByAppendingPathComponent:@"libANGLE-shared.dylib"] layer:layer error:&error];
    if(!graphics){[self finish:NO reason:error.localizedDescription];return;}
    if(!tl_ld_add_apk(apkPath.fileSystemRepresentation)){[self finish:NO reason:@"无法读取游戏 APK。"];return;}
    tl_lib *lib=tl_ld_load("libhusk_orbit.so");
    if(!lib||tl_ld_unresolved_count()||!tl_ld_init(lib)){[self finish:NO reason:@"游戏 ELF 加载失败，请查看运行日志。"];return;}
    self.initialize=tl_ld_sym(lib,"orbit_init");self.step=tl_ld_sym(lib,"orbit_step");self.draw=tl_ld_sym(lib,"orbit_draw");self.mix=tl_ld_sym(lib,"orbit_mix");self.save=tl_ld_sym(lib,"orbit_save");
    if(!self.initialize||!self.step||!self.draw||!self.mix||!self.save){[self finish:NO reason:@"游戏缺少必需的入口。"];return;}
    OrbitSave saved,*restorePointer=NULL;
    if([NSFileManager.defaultManager fileExistsAtPath:checkpointPath]) {
        NSData *data=[NSData dataWithContentsOfFile:checkpointPath options:0 error:NULL];
        NSDictionary *object=data&&data.length<=65536?[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]:nil;
        if(!restore(object,&saved)){[self finish:NO reason:@"存档格式损坏，原文件已保留。可在游戏设置中单独清除存档。"];return;}
        restorePointer=&saved;
    }
    if(!self.initialize(variant,restorePointer)){[self finish:NO reason:@"游戏无法读取此存档；原文件已保留。"];return;}
    self.loaded=YES;
    self.audio=[[MacAudio alloc] initMuted:muted||headless capture:diagnostics?[diagnostics stringByAppendingPathComponent:@"audio.wav"]:nil];
    if(!self.audio){[self finish:NO reason:@"音频输出初始化失败。请检查音频设备或在设置中静音。"];return;}
    [self transition:@"running" reason:@"game-ready"];self.draw(0);[graphics present];
    }
    if(!headless){
        if(!guestRuntime()&&!hiddenWindow){[self.window makeKeyAndOrderFront:nil];if(fullScreen&&!(self.window.styleMask&NSWindowStyleMaskFullScreen))[self.window toggleFullScreen:nil];[NSApp activateIgnoringOtherApps:YES];}
        for(GCController *controller in GCController.controllers)[self setupController:controller];
        [NSNotificationCenter.defaultCenter addObserverForName:GCControllerDidConnectNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){[self setupController:note.object];}];
        [NSNotificationCenter.defaultCenter addObserverForName:GCControllerDidDisconnectNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){
            GCController *controller=note.object;NSNumber *slot=[self.controllerSlots objectForKey:controller];
            if(slot&&guestRuntime())tl_pad_disconnect(slot.intValue);
            controller.extendedGamepad.valueChangedHandler=nil;controller.extendedGamepad.buttonMenu.pressedChangedHandler=nil;
            [self.controllerSlots removeObjectForKey:controller];
            if(!guestRuntime())mac_input_clear(&self->input);
        }];
        [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceWillSleepNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){(void)note;if([self.state isEqual:@"running"])[self togglePause:nil];}];
    }
    __block NSUInteger heartbeat=0;
    self.timer=[NSTimer scheduledTimerWithTimeInterval:1.0/60 repeats:YES block:^(NSTimer *timer){
        (void)timer;if(!automation||guestRuntime())[self frame];if(++heartbeat%60==0)[self status];
    }];
    [self status];
}
- (void)toggleTextInput:(id)sender {
    (void)sender;if(!manualKeyboardSupported()||![self.state isEqual:@"running"])return;
    [self clearInput];self.manualTextInput=!self.textInput.textInputActive;
    self.textInput.textInputActive=self.manualTextInput;
    [self.textInput receiveText:@"" selection:NSMakeRange(0,0) marked:NSMakeRange(NSNotFound,0)];
    if(self.window)[self.window makeFirstResponder:self.textInput];
    [self event:@"text-input" detail:@{@"active":@(self.manualTextInput),@"manual":@YES}];
}
- (void)windowDidResignKey:(NSNotification *)note {(void)note;[self clearInput];if(pauseInactive&&[self.state isEqual:@"running"])[self togglePause:nil];}
- (void)applicationDidResignActive:(NSNotification *)note {(void)note;[self clearInput];}
- (void)windowDidBecomeKey:(NSNotification *)note {(void)note;[self updateCursorCapture];}
- (void)applicationDidBecomeActive:(NSNotification *)note {(void)note;[self updateCursorCapture];}
- (BOOL)windowShouldClose:(NSWindow *)sender {(void)sender;[self stop:@"window-close"];return NO;}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {(void)sender;[self stop:@"menu-quit"];return NSTerminateCancel;}
@end

int main(int argc,const char **argv)
{
    // NativeRunner is a fresh process per game. Reserve before AppKit, Java and
    // the native loader create mappings; the reservation commits no physical RAM.
    husk_prepare_compressed_heap();
    atexit(husk_release_unused_compressed_heap);
    @autoreleasepool {
        const char *language=getenv("HUSK_APP_LANGUAGE");
        if(language&&(!strcmp(language,"en")||!strcmp(language,"zh-Hans"))){
            NSMutableDictionary *domain=[[NSUserDefaults.standardUserDefaults volatileDomainForName:NSArgumentDomain] mutableCopy];
            domain[@"AppleLanguages"]=@[@(language)];
            [NSUserDefaults.standardUserDefaults setVolatileDomain:domain forName:NSArgumentDomain];
        }
        if(argc==3&&(!strcmp(argv[1],"--delete-web-store")||!strcmp(argv[1],"--has-web-store"))){
            NSUUID *identifier=[[NSUUID alloc] initWithUUIDString:@(argv[2])];
            if(!identifier||[identifier.UUIDString isEqual:@"00000000-0000-0000-0000-000000000000"])return 64;
            [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];[NSApp finishLaunching];
            // WebKit's static IO API needs its main-loop infrastructure, but
            // must not open the persistent store that is about to be removed.
            WKWebViewConfiguration *config=[WKWebViewConfiguration new];config.websiteDataStore=WKWebsiteDataStore.nonPersistentDataStore;
            WKWebView *bootstrap=[[WKWebView alloc] initWithFrame:NSZeroRect configuration:config];
            __block int result=1;__block BOOL done=NO;
            void (^complete)(int)=^(int status){result=status;done=YES;CFRunLoopStop(CFRunLoopGetMain());(void)bootstrap;};
            if(!strcmp(argv[1],"--delete-web-store"))
                [WKWebsiteDataStore removeDataStoreForIdentifier:identifier completionHandler:^(NSError *error){complete(error?1:0);}];
            else [WKWebsiteDataStore fetchAllDataStoreIdentifiers:^(NSArray<NSUUID *> *ids){complete([ids containsObject:identifier]?0:3);}];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,12*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(!done)complete(1);});
            if(!done)CFRunLoopRun();
            return result;
        }
        splitPaths=[NSMutableArray new];
        for(int i=1;i<argc;i++) {
            NSString *arg=@(argv[i]);
            if([arg isEqual:@"--headless"])headless=YES;
            else if([arg isEqual:@"--show-window"])headless=NO;
            else if([arg isEqual:@"--hidden-window"]){headless=NO;hiddenWindow=YES;}
            else if([arg isEqual:@"--fullscreen"])fullScreen=YES;
            else if([arg isEqual:@"--mute"])muted=YES;
            else if([arg isEqual:@"--automation"])automation=YES;
            else if([arg isEqual:@"--pause-inactive"])pauseInactive=YES;
            else if([arg isEqual:@"--portrait"])portrait=YES;
            else if(i+1<argc&&[arg isEqual:@"--activity"])activityClass=@(argv[++i]);
            else if(i+1<argc&&[arg isEqual:@"--package"])packageName=@(argv[++i]);
            else if(i+1<argc&&[arg isEqual:@"--native-library"])nativeLibrary=@(argv[++i]);
            else if(i+1<argc&&[arg isEqual:@"--geode-directory"])geodeDirectory=@(argv[++i]);
            else if(i+1<argc&&[arg isEqual:@"--session"])sessionID=@(argv[++i]);
            else if(i+1<argc&&[arg isEqual:@"--apk"])apkPath=@(argv[++i]);
            else if(i+1<argc&&[arg isEqual:@"--split"])[splitPaths addObject:@(argv[++i])];
            else if(i+1<argc&&[arg isEqual:@"--apk-sha256"])apkDigest=@(argv[++i]);
            else if(i+1<argc&&[arg isEqual:@"--checkpoint"])checkpointPath=@(argv[++i]);
            else if(i+1<argc&&[arg isEqual:@"--java-web-store"])javaWebStore=[[NSUUID alloc] initWithUUIDString:@(argv[++i])];
            else if(i+1<argc&&[arg isEqual:@"--runtime"]){
                NSString *runtime=@(argv[++i]); nativeDriver=mac_driver_select(runtime);
                if(!nativeDriver&&![@[@"orbit",@"minecraft",@"unity",@"nativeactivity",@"java",@"ue4"] containsObject:runtime])return 64;
                minecraft=[runtime isEqual:@"minecraft"];unity=[runtime isEqual:@"unity"];ue4=[runtime isEqual:@"ue4"];
                javaNativeActivity=[runtime isEqual:@"nativeactivity"];
                nativeactivity=ue4;javaapp=javaNativeActivity||[runtime isEqual:@"java"];
            }
            else if(i+1<argc&&[arg isEqual:@"--variant"])variant=atoi(argv[++i]);
            else if(i+1<argc&&[arg isEqual:@"--title"])gameTitle=@(argv[++i]);
            else if(i+1<argc&&[arg isEqual:@"--diagnostics"])diagnostics=@(argv[++i]);
            else {fprintf(stderr,"unknown or incomplete option\n");return 64;}
        }
        if(![[NSUUID alloc] initWithUUIDString:sessionID]||!apkPath||!checkpointPath||variant<0||variant>1)return 64;
        if(javaapp&&(!javaWebStore||[javaWebStore.UUIDString isEqual:@"00000000-0000-0000-0000-000000000000"]))return 64;
        if(splitPaths.count>=TL_LD_MAX_APKS || (!guestRuntime() && splitPaths.count))return 64;
        if(portrait&&!unity&&!nativeactivity&&!javaapp&&!nativeDriver)return 64;
        if(geodeDirectory&&(!nativeDriver||![mac_driver_name() isEqual:@"cocos"]||![packageName isEqual:@"com.robtopx.geometryjump"]))return 64;
        if(nativeLibrary&&((!nativeactivity&&!javaNativeActivity)||!nativeLibrary.length||nativeLibrary.length>56||[nativeLibrary rangeOfCharacterFromSet:
            [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._+-"] invertedSet]].location!=NSNotFound))return 64;
        if((unity||nativeactivity||javaapp||nativeDriver)&&(!packageName.length||packageName.length>199||[packageName rangeOfCharacterFromSet:
            [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._"] invertedSet]].location!=NSNotFound))return 64;
        if(guestRuntime()){
            NSArray<NSString *> *hashes=[apkDigest componentsSeparatedByString:@":"];
            if(hashes.count!=splitPaths.count+1)return 64;
            for(NSString *hash in hashes)if(hash.length!=64 || [hash rangeOfCharacterFromSet:
                [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet]].location!=NSNotFound)return 64;
        }
        gameTitle=gameTitle?:@"Orbit Garden";
        if(diagnostics){if(!automation)return 64;[NSFileManager.defaultManager createDirectoryAtPath:diagnostics withIntermediateDirectories:YES attributes:nil error:NULL];}
        if(nativeDriver&&[mac_driver_name() isEqual:@"gamemaker"]){int orientation=tl_gm_orientation(apkPath.fileSystemRepresentation);if(orientation>=0)portrait=orientation==1;}
        if(activityClass&&(activityClass.length>512||[activityClass rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_/$"] invertedSet]].location!=NSNotFound))return 64;
        if(guestRuntime()){surfaceWidth=portrait?720:1280;surfaceHeight=portrait?1280:720;}
        // Android System.out and native printf share fd 1. Keep protocol events
        // on their own inherited pipe and send all guest stdio to diagnostics.
        // Do this before starting guest code; children must not inherit the
        // private writer and keep the supervisor waiting for EOF after exit.
        int protocolFD=fcntl(STDOUT_FILENO,F_DUPFD_CLOEXEC,3);
        if(protocolFD<0)return 71;
        protocolOutput=fdopen(protocolFD,"w");
        if(!protocolOutput){close(protocolFD);return 71;}
        if(dup2(STDERR_FILENO,STDOUT_FILENO)<0){fclose(protocolOutput);return 71;}
        setvbuf(stdout,NULL,_IONBF,0);
        mac_runtime_diagnostics_install();signal(SIGPIPE,SIG_IGN);
        Runner *runner=[Runner new];[runner transition:@"starting" reason:@"launch"];
        NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
        NSMutableDictionary *arguments=[[defaults volatileDomainForName:NSArgumentDomain] mutableCopy]?:[NSMutableDictionary new];
        arguments[@"ApplePersistenceIgnoreState"]=@YES;arguments[@"NSQuitAlwaysKeepsWindows"]=@NO;
        [defaults setVolatileDomain:arguments forName:NSArgumentDomain];
        if(!headless){[NSApplication sharedApplication];[NSApp disableRelaunchOnLogin];[NSApp setActivationPolicy:hiddenWindow?NSApplicationActivationPolicyProhibited:NSApplicationActivationPolicyRegular];NSApp.delegate=runner;}
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
            char line[8192];while(fgets(line,sizeof(line),stdin)) {@autoreleasepool{
                NSData *data=[NSData dataWithBytes:line length:strlen(line)];
                NSDictionary *message=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
                dispatch_async(dispatch_get_main_queue(),^{[runner command:message];});
            }}
            dispatch_async(dispatch_get_main_queue(),^{[runner stop:@"control-channel-closed"];});
        });
        pid_t owner=getppid();__block int orphan=0;
        dispatch_source_t watch=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_global_queue(QOS_CLASS_UTILITY,0));
        dispatch_source_set_timer(watch,dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),100*NSEC_PER_MSEC,10*NSEC_PER_MSEC);
        dispatch_source_set_event_handler(watch,^{if(getppid()!=owner||owner==1){if(!orphan++)dispatch_async(dispatch_get_main_queue(),^{[runner stop:@"parent-exited"];});if(orphan>=(guestRuntime()?300:20))_exit(125);}});
        dispatch_resume(watch);
        if(headless){
            [runner applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:nil]];
            while(!atomic_load(&finished)) { @autoreleasepool { CFRunLoopRunInMode(kCFRunLoopDefaultMode,.1,true); } }
        }
        else [NSApp run];
        dispatch_source_cancel(watch);
    }
    return exitStatus;
}
