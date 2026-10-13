/* SPDX-License-Identifier: GPL-2.0-or-later */
#import <Foundation/Foundation.h>
#import "MacJavaRuntime.h"
#include "husk-tl-bionic.h"
#include <unistd.h>
#include <string.h>

#define CHECK(c) do { if(!(c)){fprintf(stderr,"FAIL system resources line %d: %s\n",__LINE__,#c);return 1;} } while(0)
int main(int argc,char **argv) { @autoreleasepool {
    if(argc!=2)return 64;
    NSString *root=[NSString stringWithUTF8String:argv[1]];
    CHECK(mac_runtime_configure(root));
    int (*guest_open)(const char *,int,...)=tl_bionic_find("open");
    long (*guest_read)(int,void *,size_t)=tl_bionic_find("read");
    int (*guest_close)(int)=tl_bionic_find("close");
    CHECK(guest_open&&guest_read&&guest_close);
    NSString *system=[root stringByAppendingPathComponent:@"android-system"];
    NSArray *fonts=[NSFileManager.defaultManager contentsOfDirectoryAtPath:[system stringByAppendingPathComponent:@"fonts"] error:NULL];
    CHECK(fonts.count>100);
    NSMutableArray *paths=[NSMutableArray arrayWithObjects:@"etc/fonts.xml",@"etc/font_fallback.xml",nil];
    for(NSString *name in fonts)[paths addObject:[@"fonts" stringByAppendingPathComponent:name]];
    for(NSString *path in paths){
        NSData *expected=[NSData dataWithContentsOfFile:[system stringByAppendingPathComponent:path]];
        CHECK(expected.length>=16);
        int fd=guest_open([[@"/system" stringByAppendingPathComponent:path] fileSystemRepresentation],0);
        CHECK(fd>=0);
        unsigned char header[16];CHECK(guest_read(fd,header,sizeof(header))==sizeof(header));CHECK(guest_close(fd)==0);
        CHECK(!memcmp(header,expected.bytes,sizeof(header)));
    }
    CHECK(guest_open("/system/fonts/husk-nonexistent-font.ttf",0)<0);
    printf("PASS production runtime mapping: %lu font names, font XML and missing-file behavior\n",(unsigned long)fonts.count);
    return 0;
} }
