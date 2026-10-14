/* SPDX-License-Identifier: GPL-2.0-or-later */
#import "MacGeode.h"
#import <CommonCrypto/CommonDigest.h>
#include "husk-tl-geode.h"
#include <sys/stat.h>
#include <limits.h>

static BOOL regular(NSString *path, off_t limit) {
    struct stat st;
    return lstat(path.fileSystemRepresentation,&st)==0 && S_ISREG(st.st_mode) && st.st_size>0 && st.st_size<=limit;
}
static NSString *sha256(NSString *path) {
    NSInputStream *stream=[NSInputStream inputStreamWithFileAtPath:path]; [stream open];
    CC_SHA256_CTX context; CC_SHA256_Init(&context);
    uint8_t bytes[65536], hash[CC_SHA256_DIGEST_LENGTH]; NSInteger count;
    while((count=[stream read:bytes maxLength:sizeof(bytes)])>0) CC_SHA256_Update(&context,bytes,(CC_LONG)count);
    [stream close]; if(count<0) return nil;
    CC_SHA256_Final(hash,&context);
    NSMutableString *hex=[NSMutableString new];
    for(unsigned i=0;i<sizeof(hash);i++)[hex appendFormat:@"%02x",hash[i]];
    return hex;
}
BOOL mac_geode_configure(NSString *directory,NSString *apk,NSString *digest,
                        NSString *package,NSString *runtime,NSString *data,NSError **error) {
    tl_geode_configure(NULL,NULL,NULL,0);
    if(!directory) return YES;
    NSString *reason=@"Geode 缓存缺失或损坏，请在游戏设置中重新下载。";
    BOOL ok=NO;
    do {
        if(![package isEqual:@"com.robtopx.geometryjump"] || ![runtime isEqual:@"cocos"]) break;
        NSString *expected=[apk.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"geode"];
        if(![directory.stringByStandardizingPath isEqual:expected.stringByStandardizingPath]) break;
        struct stat st;
        if(lstat(directory.fileSystemRepresentation,&st) || !S_ISDIR(st.st_mode)) break;
        NSString *manifest=[directory stringByAppendingPathComponent:@"installation.json"];
        if(!regular(manifest,32768)) break;
        id record=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:manifest]?:[NSData data] options:0 error:NULL];
        if(![record isKindOfClass:NSDictionary.class] || ![record[@"schema"] isEqual:@1] ||
           ![record[@"gameDigest"] isEqual:digest] || ![record[@"versionCode"] isKindOfClass:NSNumber.class]) break;
        long long versionCode=[record[@"versionCode"] longLongValue];
        if(versionCode<=0 || versionCode>INT_MAX) break;
        NSString *version=record[@"version"];
        if(![version isKindOfClass:NSString.class] || !version.length || version.length>=80 ||
           [version rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-+"] invertedSet]].location!=NSNotFound) break;
        NSString *plainVersion=[version hasPrefix:@"v"]?[version substringFromIndex:1]:version;
        NSString *majorString=[plainVersion componentsSeparatedByString:@"."].firstObject;
        if(!majorString.length || [majorString rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location!=NSNotFound || majorString.intValue<=0) break;
        NSArray *names=majorString.intValue>=5 ? @[@"geode-android64.zip",@"geode-launcher.apk",@"geode-resources.zip"] : @[@"geode-android64.zip",@"geode-launcher.apk"];
        NSDictionary *files=record[@"files"];
        if(![files isKindOfClass:NSDictionary.class] || ![[NSSet setWithArray:files.allKeys] isEqual:[NSSet setWithArray:names]]) break;
        BOOL valid=YES;
        for(NSString *name in names) {
            NSString *file=[directory stringByAppendingPathComponent:name];
            if(!regular(file,256ll<<20) || ![files[name] isKindOfClass:NSString.class] || ![sha256(file) isEqual:files[name]]) { valid=NO; break; }
        }
        NSString *zip=[directory stringByAppendingPathComponent:@"geode-android64.zip"];
        NSString *launcher=[directory stringByAppendingPathComponent:@"geode-launcher.apk"];
        if(!valid || strlen(zip.fileSystemRepresentation)>=1024 || strlen(launcher.fileSystemRepresentation)>=1024 || strlen(data.fileSystemRepresentation)>=800) break;
        tl_geode_configure(zip.fileSystemRepresentation,launcher.fileSystemRepresentation,data.fileSystemRepresentation,(int)versionCode);
        ok=tl_geode_configured();
    } while(0);
    if(!ok && error) *error=[NSError errorWithDomain:@"org.husk.Geode" code:1 userInfo:@{NSLocalizedDescriptionKey:reason}];
    return ok;
}
