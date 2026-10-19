/* SPDX-License-Identifier: GPL-2.0-or-later */
#import "MacDocumentPicker.h"
#include <sys/stat.h>
#define CHECK(...) do { if (!(__VA_ARGS__)) { fprintf(stderr,"FAIL documents line %d: %s\n",__LINE__,#__VA_ARGS__); return 1; } } while(0)
int main(void) { @autoreleasepool {
    NSFileManager *fm=NSFileManager.defaultManager;
    NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    CHECK([fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:NULL]);
    NSMutableArray *urls=[NSMutableArray new];
    for(int n=0;n<2;n++) {
        NSString *dir=[root stringByAppendingPathComponent:@(n).stringValue];
        CHECK([fm createDirectoryAtPath:dir withIntermediateDirectories:NO attributes:nil error:NULL]);
        NSString *path=[dir stringByAppendingPathComponent:@"存档 %.txt"];
        CHECK([[NSString stringWithFormat:@"selected %d",n] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
        [urls addObject:[NSURL fileURLWithPath:path]];
    }
    NSString *dest=[root stringByAppendingPathComponent:@"picked"];
    NSError *error=nil;
    NSArray *paths=[MacDocumentPicker copyURLs:urls toDirectory:dest progress:[NSProgress progressWithTotalUnitCount:1] error:&error];
    CHECK(paths.count==2&&!error&&![paths[0] isEqual:paths[1]]);
    for(int n=0;n<2;n++) {
        CHECK([[NSString stringWithContentsOfFile:paths[n] encoding:NSUTF8StringEncoding error:NULL] isEqual:[NSString stringWithFormat:@"selected %d",n]]);
        struct stat st; CHECK(stat([paths[n] fileSystemRepresentation],&st)==0&&(st.st_mode&0777)==0600);
    }
    NSUInteger batches=[fm contentsOfDirectoryAtPath:dest error:NULL].count;
    NSProgress *cancel=[NSProgress progressWithTotalUnitCount:1];[cancel cancel];
    CHECK(![MacDocumentPicker copyURLs:urls toDirectory:dest progress:cancel error:&error].count);
    CHECK(error.code==NSUserCancelledError);error=nil;
    NSArray *bad=@[urls[0],[NSURL fileURLWithPath:root]];
    CHECK(![MacDocumentPicker copyURLs:bad toDirectory:dest progress:[NSProgress progressWithTotalUnitCount:1] error:&error].count);
    CHECK([fm contentsOfDirectoryAtPath:dest error:NULL].count==batches);
    NSString *link=[root stringByAppendingPathComponent:@"link.txt"];
    CHECK([fm createSymbolicLinkAtPath:link withDestinationPath:[urls[0] path] error:NULL]);
    CHECK(![MacDocumentPicker copyURLs:@[[NSURL fileURLWithPath:link]] toDirectory:dest progress:[NSProgress progressWithTotalUnitCount:1] error:NULL].count);
    CHECK([[MacDocumentPicker contentTypes:@"image/*,application/pdf"] containsObject:UTTypeImage]);
    CHECK([[MacDocumentPicker contentTypes:@"unknown/not-registered"] isEqual:@[UTTypeItem]]);
    MacDocumentPicker *picker=[[MacDocumentPicker alloc] initWithDataDirectory:root];
    __block BOOL cancelled=NO,closed=NO;
    [picker presentForWindow:nil mimeTypes:@"*/*" multiple:YES completion:^(NSArray *p){cancelled=p.count==0;}];
    CHECK(cancelled);
    [picker closeWithCompletion:^{closed=YES;}];
    NSDate *end=[NSDate dateWithTimeIntervalSinceNow:5];
    while(!closed&&end.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    CHECK(closed);CHECK([fm removeItemAtPath:root error:NULL]);
    puts("PASS selected copies: duplicate/Unicode names, modes, cancellation rollback, rejected directories/symlinks and close drain");
    return 0;
} }
