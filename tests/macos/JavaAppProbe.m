/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Explicit real-APK diagnostics. Muted, no window, isolated data, finite run,
 * and the same verified Java boot and shutdown used by NativeRunner. */
#import <AppKit/AppKit.h>
#import "MacJavaRuntime.h"
#include "MacDiagnostics.h"
#include "husk-tl-audio.h"
#include "husk-tl-bionic.h"
#include "husk-tl-egl.h"
#include "husk-tl-jni.h"
#include "husk-tl-ld.h"
#include <stdatomic.h>
#include <unistd.h>

static atomic_bool stop_requested;
static atomic_int outcome = -1;
static void guest_exit(int status) { tl_log_line("probe: unacknowledged guest exit %d", status); _exit(70); }

int main(int argc, char **argv) { @autoreleasepool {
    if (argc < 6 || argc > 37) {
        fprintf(stderr, "usage: JavaAppProbe RUNTIME EMPTY_OUTPUT ANGLE SECONDS BASE [SPLITS...]\n"
                        "stdin: touch PHASE X Y | pause | resume | stop\n"); return 64;
    }
    int seconds = atoi(argv[4]); if (seconds < 1 || seconds > 180) return 64;
    NSString *root = [NSURL fileURLWithPath:@(argv[1])].path;
    NSString *output = [NSURL fileURLWithPath:@(argv[2])].path;
    NSString *angle = [NSURL fileURLWithPath:@(argv[3])].path;
    NSString *data = [output stringByAppendingPathComponent:@"data"];
    NSString *frames = [output stringByAppendingPathComponent:@"frames"];
    if ([NSFileManager.defaultManager fileExistsAtPath:data]) {
        fprintf(stderr, "probe: data already exists; choose an empty test output, never a user save\n"); return 64;
    }
    for (NSString *path in @[data, frames])
        if (![NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL]) return 73;
    [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    NSView *canvas = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 720, 1280)];
    void tl_web_attach(void *, void *, float, bool);
    tl_web_attach((__bridge void *)canvas, (__bridge void *)canvas, 1, true);
    mac_runtime_diagnostics_install(); tl_guest_exit_hook = guest_exit;
    setenv("TL_XMEM_MIB", "1024", 1); setenv("TL_GL_SHADER_DUMP", output.fileSystemRepresentation, 1);
    tl_audio_set_muted(true); tl_audio_install(); tl_egl_offscreen_windows(true);
    tl_ld_set_verbosity(1); tl_jni_set_trace(0);
    for (int i = 6; i < argc; i++) tl_ld_queue_split(argv[i]);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        char line[160];
        while (fgets(line, sizeof(line), stdin)) {
            int phase; float x, y;
            if (sscanf(line, "touch %d %f %f", &phase, &x, &y) == 3 && phase >= 0 && phase <= 3) tl_javaapp_touch(phase, 0, x, y);
            else if (!strcmp(line, "pause\n")) tl_javaapp_set_paused(true);
            else if (!strcmp(line, "resume\n")) tl_javaapp_set_paused(false);
            else if (!strcmp(line, "stop\n")) { atomic_store(&stop_requested, true); break; }
        }
    });
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ @autoreleasepool {
        tl_javaapp_config cfg = {.apk_path=argv[5], .data_dir=data.fileSystemRepresentation, .width=720, .height=1280,
            .density=1, .angle_egl=angle.fileSystemRepresentation, .frame_dir=frames.fileSystemRepresentation, .frame_every=-60,
            .vulkan_library=getenv("HUSK_PROBE_VULKAN"),
            .framework_res=[root stringByAppendingPathComponent:@"framework-res.apk"].fileSystemRepresentation};
        if (!mac_java_start(root, &cfg)) { atomic_store(&outcome, 70); return; }
        for (int i = 0; i < seconds * 10 && !atomic_load(&stop_requested) && !tl_javaapp_ended(); i++) {
            if (i % 50 == 0) tl_log_line("probe: second=%d state=%d frames=%lu", i / 10, tl_javaapp_get_state(), tl_javaapp_frames());
            usleep(100000);
        }
        bool drew = tl_egl_frames_presented() > 0;
        bool closed = tl_javaapp_stop() && tl_javaapp_get_state() == TL_JAVA_DESTROYED;
        tl_log_line("probe: presented=%lu destroyed=%d", tl_egl_frames_presented(), closed);
        atomic_store(&outcome, drew && closed ? 0 : 72);
    }});
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds + 60];
    while (atomic_load(&outcome) < 0 && deadline.timeIntervalSinceNow > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
    int result = atomic_load(&outcome);
    if (result < 0) { tl_log_line("probe: deadline exceeded"); result = 124; }
    return result;
} }
