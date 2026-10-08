/* SPDX-License-Identifier: GPL-2.0-or-later */
/* A finite CLI child; no QEMU, windows, audio, guest code or crash signals. */
#import <Foundation/Foundation.h>
#include <unistd.h>

static NSData *event(NSString *session, int sequence, NSString *kind, NSDictionary *values) {
    NSMutableDictionary *message = [@{@"protocol": @1, @"session": session, @"pid": @(getpid()),
        @"seq": @(sequence), @"state": @"stopping", @"event": kind} mutableCopy];
    [message addEntriesFromDictionary:values];
    NSMutableData *line = [[NSJSONSerialization dataWithJSONObject:message options:0 error:nil] mutableCopy];
    [line appendBytes:"\n" length:1];
    return line;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc != 3) return 64;
        NSDictionary *config = [NSJSONSerialization JSONObjectWithData:
            [NSData dataWithContentsOfFile:@(argv[2])] options:0 error:nil];
        NSString *mode = [NSString stringWithContentsOfFile:[config[@"guest"] stringByAppendingPathComponent:@"mode"]
            encoding:NSUTF8StringEncoding error:nil];
        NSData *closed = event(config[@"session"], 1, @"storage-closed", @{@"clean": @YES});
        if ([mode isEqual:@"failure"]) {
            NSData *failure = event(config[@"session"], 1, @"failure", @{@"detail": @"fixture failure evidence"});
            write(STDOUT_FILENO, failure.bytes, failure.length);
            closed = event(config[@"session"], 2, @"storage-closed", @{@"clean": @YES});
        }
        if ([mode isEqual:@"missing"]) return 0;
        if ([mode isEqual:@"partial"]) { write(STDOUT_FILENO, "{", 1); return 0; }
        if ([mode isEqual:@"normal"] || [mode isEqual:@"failure"] || [mode isEqual:@"nonzero"]) {
            write(STDOUT_FILENO, closed.bytes, closed.length);
            return [mode isEqual:@"nonzero"] ? 7 : 0;
        }
        BOOL stalled = [mode isEqual:@"stalled"], stderrFirst = [mode isEqual:@"stderr-first"];
        BOOL stdoutFirst = [mode isEqual:@"stdout-first"] || stalled;
        const void *bytes = closed.bytes;
        size_t count = closed.length;
        pid_t child = fork();
        if (child < 0) return 71;
        if (child == 0) {
            // Only async-signal-safe operations after fork. Retain the original
            // runner PID in the pre-encoded protocol event.
            close(STDIN_FILENO);
            if (stderrFirst) { write(STDERR_FILENO, "early diagnostic\n", 17); close(STDERR_FILENO); }
            if (!stdoutFirst) usleep(650000);
            write(STDOUT_FILENO, bytes, count);
            close(STDOUT_FILENO);
            if (!stderrFirst) {
                usleep(stalled ? 3000000 : 650000);
                write(STDERR_FILENO, "late diagnostic\n", 16);
                close(STDERR_FILENO);
            }
            _exit(0);
        }
        return 0;
    }
}
