/* SPDX-License-Identifier: GPL-2.0-or-later */
/* P0 host for repository-owned ELF fixtures. This is not a game frontend. */
#import <AppKit/AppKit.h>
#import <Security/SecTask.h>
#include <fcntl.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdio.h>
#include <unistd.h>
#include "husk-tl-ld.h"

static int exitStatus;
static pid_t ownerPID;
static atomic_bool finished;
static NSString *sessionID, *apkPath, *checkpointPath;
static BOOL testControls, headless = YES;
static dispatch_source_t parentWatch;

@interface P0Delegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property NSWindow *window;
@property NSTextField *label;
@property NSTimer *timer;
@property NSString *state;
@property NSUInteger sequence;
@property NSUInteger ticks;
@property BOOL ignoreStop;
@property int (*guestTick)(void);
- (void)event:(NSString *)kind detail:(NSDictionary *)detail;
- (void)stop:(NSString *)reason;
- (void)command:(NSDictionary *)command;
@end

@implementation P0Delegate
- (void)event:(NSString *)kind detail:(NSDictionary *)detail
{
    NSMutableDictionary *message = [@{ @"protocol": @1, @"session": sessionID,
        @"seq": @(++self.sequence), @"pid": @(getpid()), @"event": kind,
        @"state": self.state ?: @"starting", @"ticks": @(self.ticks) } mutableCopy];
    [message addEntriesFromDictionary:detail ?: @{}];
    NSData *json = [NSJSONSerialization dataWithJSONObject:message options:0 error:NULL];
    fwrite(json.bytes, 1, json.length, stdout); fputc('\n', stdout); fflush(stdout);
}
- (void)transition:(NSString *)state reason:(NSString *)reason
{
    self.state = state;
    [self event:@"state" detail:@{@"reason": reason}];
    self.label.stringValue = [NSString stringWithFormat:@"Synthetic ELF session\n%@ · %lu ticks", state, self.ticks];
}
- (void)finish:(BOOL)success reason:(NSString *)reason
{
    if (atomic_exchange(&finished, true)) return;
    [self.timer invalidate];
    exitStatus = success ? 0 : 70;
    [self transition:success ? @"exited" : @"failed" reason:reason];
    [self.window orderOut:nil];
    if (NSApp) {
        [NSApp stop:nil];
        /* Wake AppKit even when stop is called from a dispatch block. */
        [NSApp postEvent:[NSEvent otherEventWithType:NSEventTypeApplicationDefined
            location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0
            context:nil subtype:0 data1:0 data2:0] atStart:NO];
    }
    CFRunLoopStop(CFRunLoopGetMain());
}
- (BOOL)checkpoint
{
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{ @"session": sessionID,
        @"ticks": @(self.ticks), @"synthetic": @YES } options:0 error:NULL];
    NSString *temporary = [checkpointPath stringByAppendingFormat:@".%d.tmp", getpid()];
    int fd = open(temporary.fileSystemRepresentation, O_CREAT | O_EXCL | O_WRONLY, 0600);
    if (fd < 0) return NO;
    const uint8_t *bytes = data.bytes;
    size_t remaining = data.length;
    BOOL ok = YES;
    while (remaining) {
        ssize_t n = write(fd, bytes, remaining);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) { ok = NO; break; }
        remaining -= (size_t)n; bytes += n;
    }
    if (ok) ok = fsync(fd) == 0;
    if (close(fd) != 0) ok = NO;
    if (ok) ok = rename(temporary.fileSystemRepresentation, checkpointPath.fileSystemRepresentation) == 0;
    if (ok) {
        int dir = open(checkpointPath.stringByDeletingLastPathComponent.fileSystemRepresentation, O_RDONLY);
        ok = dir >= 0 && fsync(dir) == 0;
        if (dir >= 0) close(dir);
    }
    if (!ok) unlink(temporary.fileSystemRepresentation);
    return ok;
}
- (void)stop:(NSString *)reason
{
    if (atomic_load(&finished) || [self.state isEqual:@"stopping"]) return;
    [self transition:@"stopping" reason:reason];
    [self.timer invalidate];
    if (self.ignoreStop) return; /* Test only: simulate an unresponsive engine. */
    if (![self checkpoint]) { [self finish:NO reason:@"checkpoint-failed"]; return; }
    [self event:@"checkpoint" detail:@{@"saved": @YES}];
    [self finish:YES reason:reason];
}
- (void)togglePause:(id)sender
{
    (void)sender;
    if ([self.state isEqual:@"running"]) [self transition:@"paused" reason:@"pause-acknowledged"];
    else if ([self.state isEqual:@"paused"]) [self transition:@"running" reason:@"resume-acknowledged"];
}
- (void)command:(NSDictionary *)command
{
    if (![command isKindOfClass:NSDictionary.class] ||
        ![command[@"session"] isKindOfClass:NSString.class] ||
        ![command[@"session"] isEqual:sessionID] || ![command[@"protocol"] isEqual:@1]) {
        [self event:@"rejected" detail:@{@"reason": @"session-or-protocol-mismatch"}]; return;
    }
    NSString *action = command[@"command"];
    if (![action isKindOfClass:NSString.class]) { [self event:@"rejected" detail:@{@"reason": @"invalid-command"}]; return; }
    if ([action isEqual:@"stop"]) [self stop:@"controller-stop"];
    else if ([action isEqual:@"pause"] && [self.state isEqual:@"running"]) [self togglePause:nil];
    else if ([action isEqual:@"resume"] && [self.state isEqual:@"paused"]) [self togglePause:nil];
    else if ([action isEqual:@"status"]) [self windowStatus];
    else if (testControls && [action isEqual:@"window-close"]) [self.window performClose:nil];
    else if (testControls && [action isEqual:@"menu-quit"]) [NSApp.mainMenu.itemArray[0].submenu performActionForItemAtIndex:2];
    else if (testControls && [action isEqual:@"menu-pause"]) [NSApp.mainMenu.itemArray[0].submenu performActionForItemAtIndex:0];
    else if (testControls && [action isEqual:@"crash"]) abort();
    else if (testControls && [action isEqual:@"hang-stop"]) { self.ignoreStop = YES; signal(SIGTERM, SIG_IGN); [self event:@"test-armed" detail:nil]; }
    else if (testControls && [action isEqual:@"hang-main"]) { [self event:@"test-armed" detail:nil]; for (;;) pause(); }
    else [self event:@"rejected" detail:@{@"reason": @"invalid-state-or-command"}];
}
- (void)windowStatus
{
    [self event:@"window" detail:@{ @"headless": @(headless), @"visible": @(self.window.visible),
        @"key": @(self.window.keyWindow), @"main": @(self.window.mainWindow),
        @"active": @(NSApp.active), @"windowNumber": @(self.window.windowNumber),
        @"menu": @(NSApp.mainMenu.numberOfItems > 0), @"ownerPID": @(getpid()) }];
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    (void)notification;
    if (atomic_load(&finished) || [self.state isEqual:@"stopping"]) return;
    /* Enforce the P0 host contract before any guest instruction is attempted. */
    SecTaskRef task = SecTaskCreateFromSelf(NULL);
    CFTypeRef value = task ? SecTaskCopyValueForEntitlement(task,
        CFSTR("com.apple.security.cs.allow-unsigned-executable-memory"), NULL) : NULL;
    BOOL permitted = value && CFEqual(value, kCFBooleanTrue);
    if (value) CFRelease(value);
    if (task) CFRelease(task);
    if (!permitted) { [self finish:NO reason:@"missing-unsigned-executable-memory-entitlement"]; return; }
    if (!tl_ld_add_apk(apkPath.fileSystemRepresentation)) { [self finish:NO reason:@"fixture-open-failed"]; return; }
    tl_lib *lib = tl_ld_load("librela4.so");
    if (!lib || tl_ld_unresolved_count() || !tl_ld_init(lib)) { [self finish:NO reason:@"fixture-load-failed"]; return; }
    self.guestTick = tl_ld_sym(lib, "fixture_tick");
    if (!self.guestTick) { [self finish:NO reason:@"fixture-symbol-missing"]; return; }

    if (!headless) {
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 400)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"Husk · P0 Native Runner";
    self.window.delegate = self;
    self.window.releasedWhenClosed = NO;
    self.window.restorable = NO;
    self.label = [NSTextField labelWithString:@"Synthetic ELF session"];
    self.label.font = [NSFont systemFontOfSize:24 weight:NSFontWeightMedium];
    self.label.alignment = NSTextAlignmentCenter;
    self.label.frame = NSMakeRect(24, 150, 592, 100);
    self.label.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin;
    [self.window.contentView addSubview:self.label];
    [self.window center];
    NSMenu *main = [[NSMenu alloc] init];
    NSMenuItem *root = [[NSMenuItem alloc] init]; [main addItem:root];
    NSMenu *app = [[NSMenu alloc] initWithTitle:@"Husk P0 Runner"];
    NSMenuItem *pause = [app addItemWithTitle:@"Pause / Resume" action:@selector(togglePause:) keyEquivalent:@"p"];
    pause.target = self;
    [app addItem:NSMenuItem.separatorItem];
    NSMenuItem *quit = [app addItemWithTitle:@"Quit Husk P0 Runner" action:@selector(terminate:) keyEquivalent:@"q"];
    quit.target = NSApp;
    root.submenu = app; NSApp.mainMenu = main;
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    }
    [self transition:@"running" reason:@"fixture-ready"];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 60 repeats:YES block:^(NSTimer *timer) {
        (void)timer;
        if ([self.state isEqual:@"running"]) {
            self.guestTick(); self.ticks++;
            self.label.stringValue = [NSString stringWithFormat:@"Synthetic ELF session\nrunning · %lu ticks", self.ticks];
        }
    }];
    [self windowStatus];
}
- (BOOL)windowShouldClose:(NSWindow *)sender { (void)sender; [self stop:@"window-close"]; return NO; }
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{ (void)sender; [self stop:@"menu-quit"]; return NSTerminateCancel; }
@end

int main(int argc, const char **argv)
{
    @autoreleasepool {
        for (int i = 1; i < argc; i++) {
            NSString *arg = @(argv[i]);
            if ([arg isEqual:@"--test-controls"]) testControls = YES;
            else if ([arg isEqual:@"--headless"]) headless = YES;
            else if ([arg isEqual:@"--show-window"]) headless = NO;
            else if (i + 1 < argc && [arg isEqual:@"--session"]) sessionID = @(argv[++i]);
            else if (i + 1 < argc && [arg isEqual:@"--apk"]) apkPath = @(argv[++i]);
            else if (i + 1 < argc && [arg isEqual:@"--checkpoint"]) checkpointPath = @(argv[++i]);
            else { fprintf(stderr, "unknown or incomplete option\n"); return 64; }
        }
        if (![[NSUUID alloc] initWithUUIDString:sessionID] || !apkPath || !checkpointPath) {
            fprintf(stderr, "usage: NativeRunner --session UUID --apk fixture.apk --checkpoint file [--show-window] [--test-controls]\n"); return 64;
        }
        signal(SIGPIPE, SIG_IGN);
        ownerPID = getppid();
        P0Delegate *delegate = [P0Delegate new];
        [delegate transition:@"starting" reason:@"launch"];
        /* Sessions are relaunched only by their supervisor. AppKit's crash
         * restoration prompt can otherwise block didFinishLaunching after a
         * forced stop. These overrides are process-local, never saved defaults. */
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        NSMutableDictionary *arguments = [[defaults volatileDomainForName:NSArgumentDomain] mutableCopy] ?: [NSMutableDictionary dictionary];
        arguments[@"NSQuitAlwaysKeepsWindows"] = @NO;
        arguments[@"ApplePersistenceIgnoreState"] = @YES;
        [defaults setVolatileDomain:arguments forName:NSArgumentDomain];
        NSApplication *app = nil;
        if (!headless) {
            app = NSApplication.sharedApplication;
            [app disableRelaunchOnLogin];
            [app setActivationPolicy:NSApplicationActivationPolicyRegular];
            app.delegate = delegate;
        }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            char line[4096];
            while (fgets(line, sizeof(line), stdin)) {
                @autoreleasepool {
                    NSData *data = [NSData dataWithBytes:line length:strlen(line)];
                    NSDictionary *message = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
                    dispatch_async(dispatch_get_main_queue(), ^{ [delegate command:message]; });
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{ [delegate stop:@"control-channel-closed"]; });
        });
        /* Independent of the AppKit thread, including a guest hung in a call. */
        parentWatch = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
        __block int orphanTicks = 0;
        dispatch_source_set_timer(parentWatch, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_MSEC * 100), NSEC_PER_MSEC * 100, NSEC_PER_MSEC * 10);
        dispatch_source_set_event_handler(parentWatch, ^{
            if (getppid() != ownerPID || ownerPID == 1) {
                if (!orphanTicks++) dispatch_async(dispatch_get_main_queue(), ^{ [delegate stop:@"parent-exited"]; });
                if (orphanTicks >= 20) _exit(125);
            }
        });
        dispatch_resume(parentWatch);
        if (headless) {
            [delegate applicationDidFinishLaunching:nil];
            while (!atomic_load(&finished))
                CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, true);
        } else {
            [app run];
        }
        dispatch_source_cancel(parentWatch);
    }
    return exitStatus;
}
