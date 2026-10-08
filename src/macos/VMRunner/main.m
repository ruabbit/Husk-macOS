/* SPDX-License-Identifier: GPL-2.0-or-later */
#import <AppKit/AppKit.h>
#import <CommonCrypto/CommonDigest.h>
#import "VMDisplay.h"
#import "VMConnection.h"
#import "MacAudio.h"
#include "husk-display.h"
#include "husk-display-gl.h"
#include "husk-audio.h"
#include <sys/file.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <stdatomic.h>

extern void qemu_init(int argc, char **argv);
extern int qemu_main_loop(void);
extern void qemu_cleanup(int status);
extern void bql_unlock(void);
extern void replay_mutex_unlock(void);

static NSDictionary *config;
static VMDisplay *display;
static VMConnection *bridge;
static MacAudio *audio;
static NSString *session,*state=@"starting",*qmp,*temporary,*guest;
static NSObject *eventLock;
static NSWindow *window;
static dispatch_queue_t commands;
static atomic_bool ready,booted,stopping,finished,forced;
static uint64_t sequence;
static int diskLock=-1;
static uint16_t bridgePort;
static BOOL gpu,showWindow;

static void emit(NSString *event, NSDictionary *values) {
    @synchronized(eventLock){
        NSMutableDictionary *data=[@{@"protocol":@1,@"session":session?:@"",@"pid":@(getpid()),@"seq":@(++sequence),@"state":state,@"event":event} mutableCopy];
        [data addEntriesFromDictionary:values?:@{}];
        NSData *json=[NSJSONSerialization dataWithJSONObject:data options:0 error:nil];
        fwrite(json.bytes,1,json.length,stdout);fwrite("\n",1,1,stdout);fflush(stdout);
    }
}
static void transition(NSString *phase, NSString *event, NSDictionary *values) {
    @synchronized(eventLock){state=phase;emit(event,values);}
}
static NSString *sha256(NSString *path) {
    NSFileHandle *f=[NSFileHandle fileHandleForReadingAtPath:path];if(!f)return nil;
    CC_SHA256_CTX ctx;CC_SHA256_Init(&ctx);NSData *data;
    while((data=[f readDataOfLength:1024*1024]).length)CC_SHA256_Update(&ctx,data.bytes,(CC_LONG)data.length);
    [f closeFile];unsigned char bytes[CC_SHA256_DIGEST_LENGTH];CC_SHA256_Final(bytes,&ctx);
    NSMutableString *out=[NSMutableString new];for(int i=0;i<sizeof(bytes);i++)[out appendFormat:@"%02x",bytes[i]];return out;
}
static void stopVM(void) {
    if(atomic_exchange(&stopping,true))return;
    transition(@"stopping",@"stopping",nil);
    dispatch_async(dispatch_get_main_queue(),^{[display releaseInput];});
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        // A paused CPU cannot carry out Android's shutdown request.
        if(atomic_load(&ready))VMQMP(qmp,@"cont",nil,nil);
        if(atomic_load(&booted)) {
            // This is a guest shutdown, not a memory snapshot. Android flushes
            // apps and filesystems before QEMU receives guest poweroff.
            int status=-1;NSError *error=nil;
            [bridge shell:@"sync; svc power shutdown" timeout:8 status:&status error:&error];
            if(error)emit(@"shutdown-request",@{@"detail":error.localizedDescription});
        }else if(atomic_load(&ready))VMQMP(qmp,@"system_powerdown",nil,nil);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,45*NSEC_PER_SEC),dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        if(atomic_load(&finished))return;
        atomic_store(&forced,true);emit(@"shutdown-timeout",@{@"detail":@"Guest did not confirm poweroff; disks may require recovery"});
        VMQMP(qmp,@"quit",nil,nil);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
            if(!atomic_load(&finished))_exit(75);
        });
    });
}
static void metalFrame(void *texture,int flip,int width,int height) {
    [display presentTexture:(__bridge id<MTLTexture>)texture flip:flip!=0];
}
static BOOL packageValid(NSString *s) {
    if(!s.length)return NO;
    NSCharacterSet *bad=[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._$"] invertedSet];
    return [s rangeOfCharacterFromSet:bad].location==NSNotFound;
}
static void handle(NSDictionary *message) {
    if(![message[@"session"] isEqual:session])return;
    NSString *action=message[@"command"];id request=message[@"id"]?:@0;
    NSError *error=nil;NSDictionary *result=nil;
    if([action isEqual:@"shutdown"]){stopVM();return;}
    if(![action isKindOfClass:NSString.class]||atomic_load(&stopping)){
        emit(@"command-error",@{@"id":request,@"detail":@"Invalid command or VM is stopping"});return;
    }
    if(!atomic_load(&ready)){emit(@"command-error",@{@"id":request,@"detail":@"VM not ready"});return;}
    if([action isEqual:@"pause"]||[action isEqual:@"resume"]){
        BOOL pause=[action isEqual:@"pause"];
        result=VMQMP(qmp,pause?@"stop":@"cont",nil,&error);
        if(result)transition(pause?@"paused":@"running",pause?@"paused":@"resumed",@{@"id":request});
    }else if([action isEqual:@"snapshot"]||[action isEqual:@"restore"]){
        emit(@"command-error",@{@"id":request,@"detail":@"Memory snapshots are disabled: virtio-sound and virgl are not migratable. Cold boot preserves disk data."});return;
    }else if([action isEqual:@"screenshot"]){
        NSString *path=[guest stringByAppendingPathComponent:@"screenshot.png"];
        result=@{@"saved":@([display screenshot:path]),@"path":path};
    }else if([action isEqual:@"key"]){
        NSString *key=message[@"key"];
        if(![key isKindOfClass:NSString.class]||![message[@"down"] isKindOfClass:NSNumber.class]){
            emit(@"command-error",@{@"id":request,@"detail":@"Invalid key input"});return;
        }
        result=@{@"accepted":@(key&&husk_display_send_key(key.UTF8String,[message[@"down"] boolValue]))};
    }else if([action isEqual:@"pointer"]){
        for(NSString *field in @[@"x",@"y",@"down"])if(![message[field] isKindOfClass:NSNumber.class]){
            emit(@"command-error",@{@"id":request,@"detail":@"Invalid pointer input"});return;
        }
        int x=MAX(0,MIN(32767,[message[@"x"] intValue])),y=MAX(0,MIN(32767,[message[@"y"] intValue]));
        husk_display_send_pointer(x,y,[message[@"down"] boolValue]);result=@{};
    }else if([action isEqual:@"install"]){
        if(!atomic_load(&booted)){emit(@"command-error",@{@"id":request,@"detail":@"Android has not finished booting"});return;}
        NSString *apk=message[@"apk"],*expected=message[@"sha256"];
        if(![apk isKindOfClass:NSString.class]||![expected isKindOfClass:NSString.class]||expected.length!=64||![[sha256(apk) lowercaseString] isEqual:expected.lowercaseString]){
            emit(@"command-error",@{@"id":request,@"detail":@"APK hash mismatch"});return;
        }
        emit(@"installing",@{@"id":request});
        if([bridge push:apk remote:@"/data/local/tmp/husk-install.apk" error:&error]){
            int status=-1;
            NSString *hash=[bridge shell:@"sha256sum /data/local/tmp/husk-install.apk" timeout:120 status:&status error:&error];
            if(status==0&&[hash hasPrefix:expected.lowercaseString]){
                NSString *out=[bridge shell:@"pm install -r /data/local/tmp/husk-install.apk" timeout:600 status:&status error:&error];
                if(out)result=@{@"status":@(status),@"output":out};
                [bridge shell:@"rm -f /data/local/tmp/husk-install.apk" timeout:20 status:NULL error:nil];
            }else if(!error)error=[NSError errorWithDomain:@"HuskVM" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Transferred APK hash mismatch"}];
        }
    }else if([action isEqual:@"launch"]){
        NSString *package=message[@"package"];
        if(![package isKindOfClass:NSString.class]||!packageValid(package)){emit(@"command-error",@{@"id":request,@"detail":@"Invalid Android package"});return;}
        int status=-1;
        NSString *out=[bridge shell:[NSString stringWithFormat:@"monkey -p '%@' -c android.intent.category.LAUNCHER 1",package] timeout:45 status:&status error:&error];
        if(out)result=@{@"status":@(status),@"output":out};
    }else if([action isEqual:@"shell"]&&[config[@"automation"] boolValue]){
        int status=-1;NSString *command=message[@"text"];
        if([command isKindOfClass:NSString.class]&&command.length<8192){
            NSString *out=[bridge shell:command timeout:MIN(600,MAX(1,[message[@"timeout"] doubleValue])) status:&status error:&error];
            if(out)result=@{@"status":@(status),@"output":out};
        }
    }else if([action isEqual:@"status"]){result=VMQMP(qmp,@"query-status",nil,&error);}
    else {emit(@"command-error",@{@"id":request,@"detail":@"Unsupported VM command"});return;}
    if(error)emit(@"command-error",@{@"id":request,@"detail":error.localizedDescription});
    else emit(@"command-result",@{@"id":request,@"result":result?:@{}});
}

@interface VMDelegate:NSObject<NSApplicationDelegate,NSWindowDelegate>
@end
@implementation VMDelegate
- (BOOL)windowShouldClose:(NSWindow *)sender {stopVM();return NO;}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {stopVM();return NSTerminateCancel;}
- (void)windowDidResignKey:(NSNotification *)notification {[display releaseInput];}
@end

static int fail(NSString *message){transition(@"failed",@"failure",@{@"detail":message});return 2;}
int main(int argc,const char **argv) {
    @autoreleasepool {
        signal(SIGPIPE,SIG_IGN);eventLock=[NSObject new];
        if(argc!=3||strcmp(argv[1],"--config"))return fail(@"Usage: VMRunner --config file.json");
        NSData *data=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[2]]];
        config=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
        if(![config isKindOfClass:NSDictionary.class])return fail(@"Invalid VM configuration");
        for(NSString *key in @[@"session",@"guest",@"accelerator",@"graphics"])
            if(config[key]&&![config[key] isKindOfClass:NSString.class])return fail(@"Invalid VM configuration field type");
        for(NSString *key in @[@"memoryMiB",@"cpus",@"width",@"height",@"showWindow",@"muted",@"automation",@"maxRunSeconds"])
            if(config[key]&&![config[key] isKindOfClass:NSNumber.class])return fail(@"Invalid VM numeric field type");
        session=config[@"session"];guest=config[@"guest"];
        NSString *accel=config[@"accelerator"]?:@"tcg";
        if(![session isKindOfClass:NSString.class]||![[NSUUID alloc]initWithUUIDString:session]||![guest isKindOfClass:NSString.class]||![guest hasPrefix:@"/"])
            return fail(@"Invalid session or VM directory");
        if(![@[@"tcg",@"hvf"] containsObject:accel])return fail(@"Unsupported accelerator");
        if(config[@"snapshot"]||config[@"restore"])return fail(@"Memory snapshot restore is disabled for this device set; use cold boot");
        if(config[@"graphics"]&&![@[@"software",@"virgl"] containsObject:config[@"graphics"]])return fail(@"Unsupported graphics configuration");
        NSDictionary *metadata=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[guest stringByAppendingPathComponent:@"guest.json"]]?:[NSData data] options:0 error:nil];
        NSDictionary *lock=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"macos-vm.lock.json"]]?:[NSData data] options:0 error:nil];
        if(![metadata isKindOfClass:NSDictionary.class]||![lock isKindOfClass:NSDictionary.class]||![metadata[@"coldBootOnly"] isKindOfClass:NSNumber.class])return fail(@"Invalid VM preparation manifest");
        for(NSString *key in @[@"generation",@"systemSourceSHA256",@"firmwareSHA256"])
            if(![metadata[key] isKindOfClass:NSString.class])return fail(@"Invalid VM image identity");
        if(![metadata[@"coldBootOnly"] boolValue]||![metadata[@"generation"] isEqual:lock[@"guest"][@"generation"]]||![metadata[@"systemSourceSHA256"] isEqual:lock[@"guest"][@"sha256"]]||[NSFileManager.defaultManager fileExistsAtPath:[guest stringByAppendingPathComponent:@"INCOMPLETE"]])return fail(@"VM preparation does not match this runtime");
        for(NSString *file in @[@"system.qcow2",@"userdata.qcow2",@"vars.qcow2",@"firmware.fd"])
            if(![NSFileManager.defaultManager isReadableFileAtPath:[guest stringByAppendingPathComponent:file]])return fail(@"Missing VM disk or firmware");
        if(![metadata[@"firmwareSHA256"] isEqual:lock[@"guest"][@"seeds"][@"edk2-aarch64-code.fd"]]||![sha256([guest stringByAppendingPathComponent:@"firmware.fd"]) isEqual:metadata[@"firmwareSHA256"]])return fail(@"Firmware hash mismatch");
        diskLock=open([[guest stringByAppendingPathComponent:@"run.lock"] fileSystemRepresentation],O_CREAT|O_RDWR,0600);
        if(diskLock<0||flock(diskLock,LOCK_EX|LOCK_NB))return fail(@"This Android VM is already running");
        int ram=[config[@"memoryMiB"] intValue]?:4096,cpus=[config[@"cpus"] intValue]?:4;
        int width=[config[@"width"] intValue]?:960,height=[config[@"height"] intValue]?:540;
        if(ram<2048||ram>16384||cpus<1||cpus>8||width<320||height<320||width>1920||height>1920)return fail(@"VM dimensions exceed supported bounds");
        gpu=[config[@"graphics"] isEqual:@"virgl"];showWindow=[config[@"showWindow"] boolValue];
        NSString *frameworks=[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Contents/Frameworks"];
        NSDictionary *fingerprint=@{@"schema":@1,@"guest":metadata[@"systemSourceSHA256"],@"firmware":metadata[@"firmwareSHA256"],
            @"qemu":sha256([frameworks stringByAppendingPathComponent:@"libqemu-aarch64-softmmu.dylib"])?:@"missing",
            @"angle":sha256([frameworks stringByAppendingPathComponent:@"libANGLE-shared.dylib"])?:@"missing",
            @"accelerator":accel,@"cpu":[accel isEqual:@"hvf"]?@"host":@"max,pauth-impdef=on,sve=off,sme=off",
            @"cpus":@(cpus),@"memoryMiB":@(ram),@"width":@(width),@"height":@(height),@"graphics":gpu?@"virgl":@"software",
            @"audio":@"virtio-sound-pci",@"snapshotPolicy":@"disabled-nonmigratable-devices"};
        [[NSJSONSerialization dataWithJSONObject:fingerprint options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil] writeToFile:[guest stringByAppendingPathComponent:@"last-fingerprint.json"] atomically:YES];
        char tmp[]="/tmp/husk-vm-XXXXXX";if(!mkdtemp(tmp))return fail(@"Cannot create session directory");
        temporary=[NSString stringWithUTF8String:tmp];qmp=[temporary stringByAppendingPathComponent:@"qmp.sock"];
        int socketFD=socket(AF_INET,SOCK_STREAM,0);struct sockaddr_in bindAddress={.sin_len=sizeof(bindAddress),.sin_family=AF_INET,.sin_addr.s_addr=htonl(INADDR_LOOPBACK)};
        if(socketFD<0||bind(socketFD,(struct sockaddr *)&bindAddress,sizeof(bindAddress)))return fail(@"Cannot allocate loopback bridge port");
        socklen_t length=sizeof(bindAddress);getsockname(socketFD,(struct sockaddr *)&bindAddress,&length);bridgePort=ntohs(bindAddress.sin_port);close(socketFD);
        bridge=[[VMConnection alloc]initPort:bridgePort];commands=dispatch_queue_create("org.husk.vm.commands",DISPATCH_QUEUE_SERIAL);
        [NSApplication sharedApplication];[NSApp setActivationPolicy:showWindow?NSApplicationActivationPolicyRegular:NSApplicationActivationPolicyProhibited];
        VMDelegate *delegate=[VMDelegate new];NSApp.delegate=delegate;
        display=[[VMDisplay alloc]initWithFrame:NSMakeRect(0,0,width,height)];display.visible=showWindow;
        // The hidden window never becomes ordered or active; it supplies a native
        // CAMetalLayer for EGL without disturbing the user's desktop.
        window=[[NSWindow alloc]initWithContentRect:display.frame styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
        window.title=@"Husk Android";window.contentView=display;window.delegate=delegate;window.releasedWhenClosed=NO;
        if(showWindow){[window makeKeyAndOrderFront:nil];[window makeFirstResponder:display];[NSApp activateIgnoringOtherApps:YES];}
        audio=[[MacAudio alloc]initMuted:NO capture:nil silentDevice:[config[@"muted"] boolValue]||!showWindow];
        NSMutableArray<NSString *> *args=[@[@"HuskVM",@"-M",@"virt,highmem=on",@"-cpu",[accel isEqual:@"hvf"]?@"host":@"max,pauth-impdef=on,sve=off,sme=off",@"-smp",@(cpus).stringValue,@"-m",@(ram).stringValue,@"-accel",[accel isEqual:@"hvf"]?@"hvf":@"tcg,tb-size=256,thread=multi,split-wx=on",@"-S",
            @"-drive",[NSString stringWithFormat:@"if=pflash,unit=0,format=raw,readonly=on,file=%@/firmware.fd",guest],
            @"-drive",[NSString stringWithFormat:@"if=pflash,unit=1,format=qcow2,file=%@/vars.qcow2",guest],
            @"-drive",[NSString stringWithFormat:@"file=%@/system.qcow2,if=none,id=vda,format=qcow2,discard=unmap",guest],
            @"-drive",[NSString stringWithFormat:@"file=%@/userdata.qcow2,if=none,id=vdb,format=qcow2,discard=unmap",guest],
            @"-device",@"virtio-blk-pci,drive=vda,bootindex=0",@"-device",@"virtio-blk-pci,drive=vdb,bootindex=1",
            @"-device",@"virtio-net-pci,netdev=net0,romfile=",@"-netdev",[NSString stringWithFormat:@"user,id=net0,hostfwd=tcp:127.0.0.1:%u-:5599",bridgePort],
            @"-device",[NSString stringWithFormat:@"%@,xres=%d,yres=%d",gpu?@"virtio-gpu-gl-pci":@"virtio-gpu-pci",width,height],
            @"-device",@"qemu-xhci,id=usb-bus",@"-device",@"usb-tablet,bus=usb-bus.0",@"-device",@"usb-kbd,bus=usb-bus.0",@"-device",@"virtio-rng-pci",
            @"-audiodev",@"husk,id=audio0",@"-device",@"virtio-sound-pci,audiodev=audio0",
            @"-serial",[NSString stringWithFormat:@"file:%@/serial.log",guest],@"-display",@"none",@"-monitor",@"none",
            @"-qmp",[NSString stringWithFormat:@"unix:%@,server=on,wait=off",qmp]] mutableCopy];
        if([guest containsString:@","])return fail(@"VM directory cannot contain commas");
        [[NSJSONSerialization dataWithJSONObject:args options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[guest stringByAppendingPathComponent:@"last-arguments.json"] atomically:YES];
        emit(@"starting",@{@"accelerator":accel,@"graphics":gpu?@"virgl":@"software",@"bridgePort":@(bridgePort),@"qmp":qmp});
        [NSThread detachNewThreadWithBlock:^{@autoreleasepool{
            int n=(int)args.count;char **v=calloc(n+1,sizeof(char *));for(int i=0;i<n;i++)v[i]=strdup(args[i].UTF8String);
            if(gpu)husk_display_gl_early();qemu_init(n,v);
            if(gpu){
                __block BOOL created=NO;dispatch_sync(dispatch_get_main_queue(),^{created=husk_display_gl_create((__bridge void *)display.metalLayer,width,height);});
                if(!created||!husk_display_gl_probe()){emit(@"failure",@{@"detail":@"VM EGL probe failed"});_exit(3);}
                husk_display_gl_set_metal_presenter(metalFrame);
                if(!husk_display_gl_bind()){emit(@"failure",@{@"detail":@"VM GL listener failed"});_exit(3);}
            }else husk_display_init();
            atomic_store(&ready,true);dispatch_async(dispatch_get_main_queue(),^{display.ready=YES;});emit(@"qemu-ready",nil);
            int qemuStatus=qemu_main_loop();qemu_cleanup(qemuStatus);atomic_store(&finished,true);
            bql_unlock();replay_mutex_unlock();
            // QEMU's exit notifiers must run on the thread that owns the BQL.
            // Moving exit() to AppKit after qemu_cleanup() deadlocks the notifiers.
            dispatch_sync(dispatch_get_main_queue(),^{
                [audio close];display.ready=NO;
                BOOL clean=qemuStatus==0&&!atomic_load(&forced);
                if(clean)emit(@"storage-closed",@{@"clean":@YES});
                transition(clean?@"exited":@"failed",@"exited",@{@"clean":@(clean)});
                [NSFileManager.defaultManager removeItemAtPath:temporary error:nil];
            });
            exit(atomic_load(&forced)?75:qemuStatus);
        }}];
        [NSThread detachNewThreadWithBlock:^{@autoreleasepool{
            while(!atomic_load(&ready)&&!atomic_load(&finished))[NSThread sleepForTimeInterval:0.1];
            if(atomic_load(&finished))return;
            NSError *error=nil;if(!VMQMP(qmp,@"cont",nil,&error)){emit(@"failure",@{@"detail":error.localizedDescription?:@"Cannot resume VM"});stopVM();return;}
            double deadline=NSProcessInfo.processInfo.systemUptime+900;
            while(!atomic_load(&stopping)&&NSProcessInfo.processInfo.systemUptime<deadline){@autoreleasepool{
                int status=-1;NSString *out=[bridge shell:@"getprop sys.boot_completed" timeout:3 status:&status error:nil];
                if(status==0&&[[out stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] isEqual:@"1"]){
                    if(!atomic_load(&stopping)){atomic_store(&booted,true);transition(@"running",@"android-ready",@{@"bridgePort":@(bridgePort)});}return;
                }
                [NSThread sleepForTimeInterval:2];
            }}
            if(!atomic_load(&stopping)){emit(@"failure",@{@"detail":@"Android cold boot timed out"});stopVM();}
        }}];
        [NSThread detachNewThreadWithBlock:^{@autoreleasepool{
            char *line=NULL;size_t capacity=0;ssize_t n;
            while((n=getline(&line,&capacity,stdin))>0){
                if(n>65536){emit(@"command-error",@{@"detail":@"Command exceeds size limit"});break;}
                id msg=[NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:line length:n] options:0 error:nil];
                if([msg isKindOfClass:NSDictionary.class]) {
                    if([msg[@"command"] isEqual:@"shutdown"]&&[msg[@"session"] isEqual:session])stopVM();
                    else dispatch_async(commands,^{@autoreleasepool{handle(msg);}});
                }
            }
            free(line);stopVM();
        }}];
        pid_t parent=getppid();double start=NSProcessInfo.processInfo.systemUptime;__block int tick=0;
        [NSTimer scheduledTimerWithTimeInterval:1.0/60 repeats:YES block:^(NSTimer *timer){
            if(atomic_load(&ready)&&!atomic_load(&finished)){
                if(!gpu)[display pollCPU];int16_t samples[800*2];husk_audio_pull(samples,800);[audio submit:samples frames:800];
            }
            if(++tick%60==0){emit(@"heartbeat",@{@"frames":@(display.frames),@"audioFrames":@(husk_audio_frames_in()),@"nonzeroSamples":@(audio.nonzeroSamples),@"audioCallbacks":@(audio.callbackCount),@"booted":@(atomic_load(&booted))});
                if(getppid()!=parent)stopVM();double limit=[config[@"maxRunSeconds"] doubleValue];if(limit>0&&NSProcessInfo.processInfo.systemUptime-start>limit)stopVM();}
        }];
        [NSApp run];
    }
    return 0;
}
