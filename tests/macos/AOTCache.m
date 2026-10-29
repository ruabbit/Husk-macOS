/* SPDX-License-Identifier: GPL-2.0-or-later */
#import "MacAOT.h"
#include <fcntl.h>
#include <sys/file.h>
#include <unistd.h>
#define CHECK(c) do{if(!(c)){fprintf(stderr,"FAIL AOT cache line %d: %s\n",__LINE__,#c);return 1;}}while(0)
void tl_log_line(const char *format,...) {(void)format;}
int main(int argc,char **argv) {@autoreleasepool{
    if(argc!=3)return 64;
    NSFileManager *fm=NSFileManager.defaultManager;
    NSString *root=[@(argv[2]) stringByAppendingPathComponent:[@"AOTCache-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    CHECK([fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:NULL]);
    NSString *source=[root stringByAppendingPathComponent:@"module.so"];
    CHECK([fm copyItemAtPath:@(argv[1]) toPath:source error:NULL]);
    __block int reports=0;NSError *error=nil;
    NSString *cache=mac_aot_prepare(@[source],nil,^(NSString *s){reports++;},&error);
    CHECK(cache&&reports>0&&!error);
    NSString *file=nil;
    for(NSString *name in [fm contentsOfDirectoryAtPath:cache error:NULL])if([name hasSuffix:@".dylib"]){file=[cache stringByAppendingPathComponent:name];break;}
    CHECK(file);
    NSData *original=[NSData dataWithContentsOfFile:file];
    NSDate *modified=[fm attributesOfItemAtPath:file error:NULL].fileModificationDate;
    reports=0;CHECK([mac_aot_prepare(@[source],nil,^(NSString *s){reports++;},&error) isEqual:cache]);
    CHECK(reports==0&&[modified isEqual:[fm attributesOfItemAtPath:file error:NULL].fileModificationDate]);
    // Reject corruption before dlopen. No invalid code is ever executed.
    NSMutableData *corrupt=[original mutableCopy];((uint8_t *)corrupt.mutableBytes)[16384]^=1;
    CHECK([corrupt writeToFile:file atomically:YES]);error=nil;
    CHECK(!mac_aot_prepare(@[source],nil,nil,&error)&&error);
    CHECK([[NSData dataWithContentsOfFile:file] isEqual:corrupt]);
    CHECK([original writeToFile:file atomically:YES]);error=nil;
    CHECK([mac_aot_prepare(@[source],nil,nil,&error) isEqual:cache]);
    NSString *lockPath=[root stringByAppendingPathComponent:@"jitless/prepare.lock"];
    int lock=open(lockPath.fileSystemRepresentation,O_RDWR);CHECK(lock>=0&&!flock(lock,LOCK_EX|LOCK_NB));
    CHECK(!mac_aot_prepare(@[source],nil,nil,&error));close(lock);
    CHECK([fm removeItemAtPath:file error:NULL]);CHECK(!symlink(source.fileSystemRepresentation,file.fileSystemRepresentation));
    CHECK(!mac_aot_prepare(@[source],nil,nil,&error));
    CHECK([fm removeItemAtPath:root error:NULL]);
    puts("PASS atomic AOT cache, warm reuse, signature/hash corruption, lock and symlink rejection");return 0;
}}
