/* SPDX-License-Identifier: GPL-2.0-or-later */
#import "MacDocumentPicker.h"
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

@implementation MacDocumentPicker {
    NSString *_directory;
    NSOpenPanel *_panel;
    NSProgress *_progress;
    dispatch_queue_t _copies;
    BOOL _busy, _closed;
}
- (instancetype)initWithDataDirectory:(NSString *)directory {
    if ((self = [super init])) {
        _directory = [directory stringByAppendingPathComponent:@"cache/picked"];
        _copies = dispatch_queue_create("org.husk.documents", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}
+ (NSArray<UTType *> *)contentTypes:(NSString *)mimeTypes {
    NSMutableArray *types = [NSMutableArray new];
    NSDictionary *wildcards = @{@"image/*":UTTypeImage, @"video/*":UTTypeMovie,
        @"audio/*":UTTypeAudio, @"text/*":UTTypeText, @"application/*":UTTypeData};
    for (NSString *raw in [mimeTypes componentsSeparatedByString:@","]) {
        NSString *mime = [[raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
        if (!mime.length || [mime isEqual:@"*/*"]) return @[UTTypeItem];
        UTType *type = wildcards[mime] ?: [UTType typeWithMIMEType:mime];
        if (!type || type.dynamic) return @[UTTypeItem];
        if (![types containsObject:type]) [types addObject:type];
    }
    return types.count ? types : @[UTTypeItem];
}
+ (NSArray<NSString *> *)copyURLs:(NSArray<NSURL *> *)urls toDirectory:(NSString *)directory
                        progress:(NSProgress *)progress error:(NSError **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *batch = [directory stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSMutableArray *paths = [NSMutableArray new];
    BOOL ok = urls.count > 0 && urls.count <= 64 && !progress.cancelled;
    if (ok) ok = [fm createDirectoryAtPath:batch withIntermediateDirectories:YES
                              attributes:@{NSFilePosixPermissions:@0700} error:error];
    for (NSURL *url in urls) {
        if (!ok) break;
        BOOL scoped = [url startAccessingSecurityScopedResource];
        int source = url.isFileURL ? open(url.fileSystemRepresentation, O_RDONLY|O_NOFOLLOW|O_NONBLOCK) : -1;
        struct stat st;
        ok = source >= 0 && fstat(source, &st) == 0 && S_ISREG(st.st_mode) && !progress.cancelled;
        NSString *folder = [batch stringByAppendingPathComponent:[NSString stringWithFormat:@"%lu",(unsigned long)paths.count]];
        NSString *dest = [folder stringByAppendingPathComponent:url.lastPathComponent];
        if (ok) ok = [fm createDirectoryAtPath:folder withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:error];
        int output = ok ? open(dest.fileSystemRepresentation, O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600) : -1;
        if (output < 0) ok = NO;
        char bytes[65536];
        while (ok && !progress.cancelled) {
            ssize_t n = read(source, bytes, sizeof(bytes));
            if (n < 0 && errno == EINTR) continue;
            if (n < 0) { ok = NO; break; }
            if (!n) break;
            for (ssize_t done = 0; done < n;) {
                ssize_t wrote = write(output, bytes+done, (size_t)(n-done));
                if (wrote < 0 && errno == EINTR) continue;
                if (wrote <= 0) { ok = NO; break; }
                done += wrote;
            }
        }
        ok = ok && !progress.cancelled;
        if (ok) ok = fsync(output) == 0;
        if (output >= 0 && close(output) != 0) ok = NO;
        if (source >= 0) close(source);
        if (scoped) [url stopAccessingSecurityScopedResource];
        if (ok) [paths addObject:dest];
    }
    if (!ok) {
        [fm removeItemAtPath:batch error:NULL];
        if (error && !*error) *error = [NSError errorWithDomain:NSCocoaErrorDomain
            code:progress.cancelled?NSUserCancelledError:NSFileReadUnknownError userInfo:nil];
        return @[];
    }
    return paths;
}
- (void)presentForWindow:(NSWindow *)window mimeTypes:(NSString *)types multiple:(BOOL)multiple
              completion:(void (^)(NSArray<NSString *> *))completion {
    NSAssert(NSThread.isMainThread, @"document UI belongs to the main thread");
    if (_closed || _busy || !window || !window.visible) { completion(@[]); return; }
    _busy = YES;
    _progress = [NSProgress progressWithTotalUnitCount:1];
    NSOpenPanel *panel = [NSOpenPanel openPanel]; _panel = panel;
    panel.canChooseFiles = YES; panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = multiple;
    panel.allowedContentTypes = [MacDocumentPicker contentTypes:types];
    [panel beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
        NSArray *urls = response == NSModalResponseOK ? panel.URLs : @[];
        self->_panel = nil;
        NSProgress *progress = self->_progress;
        dispatch_async(self->_copies, ^{
            NSError *error = nil;
            NSArray *paths = urls.count ? [MacDocumentPicker copyURLs:urls toDirectory:self->_directory progress:progress error:&error] : @[];
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_busy = NO; self->_progress = nil;
                if (error && !progress.cancelled) NSLog(@"Husk document import failed (%ld)",(long)error.code);
                if (!self->_closed) completion(paths);
            });
        });
    }];
}
- (void)closeWithCompletion:(void (^)(void))completion {
    NSAssert(NSThread.isMainThread, @"document close belongs to the main thread");
    _closed = YES; [_progress cancel]; [_panel cancel:nil];
    // Drain any copying before Android's lifecycle can acknowledge storage closed.
    dispatch_async(_copies, ^{ dispatch_async(dispatch_get_main_queue(), completion); });
}
@end
