/* SPDX-License-Identifier: GPL-2.0-or-later */
#import "MacAOT.h"
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>
#include "husk-tl-aot.h"
#include <sys/file.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

static BOOL regular(NSString *path) {
    struct stat s;
    return !lstat(path.fileSystemRepresentation,&s) && S_ISREG(s.st_mode) && s.st_uid==getuid() && s.st_size>0;
}
static NSString *hex(const uint8_t *bytes, size_t length) {
    NSMutableString *s=[NSMutableString new];
    for(size_t i=0;i<length;i++)[s appendFormat:@"%02x",bytes[i]];
    return s;
}
static NSString *digest(NSString *path) {
    if(!regular(path))return nil;
    NSInputStream *stream=[NSInputStream inputStreamWithFileAtPath:path];[stream open];
    CC_SHA256_CTX c;CC_SHA256_Init(&c);uint8_t b[65536],hash[32];NSInteger n;
    while((n=[stream read:b maxLength:sizeof(b)])>0)CC_SHA256_Update(&c,b,(CC_LONG)n);
    [stream close];if(n<0)return nil;CC_SHA256_Final(hash,&c);return hex(hash,sizeof(hash));
}
static BOOL signedFile(NSString *path) {
    SecStaticCodeRef code=NULL;
    OSStatus status=SecStaticCodeCreateWithPath((__bridge CFURLRef)[NSURL fileURLWithPath:path],kSecCSDefaultFlags,&code);
    if(!status)status=SecStaticCodeCheckValidity(code,kSecCSStrictValidate|kSecCSCheckAllArchitectures,NULL);
    if(code)CFRelease(code);return status==errSecSuccess;
}
static BOOL directory(NSString *path, BOOL create) {
    struct stat s;
    if(create && mkdir(path.fileSystemRepresentation,0700) && errno!=EEXIST)return NO;
    return !lstat(path.fileSystemRepresentation,&s) && S_ISDIR(s.st_mode) && s.st_uid==getuid() && !(s.st_mode&0022);
}
static void report(void *user,int index,int total,const char *name) {
    void (^progress)(NSString *)=(__bridge id)user;
    if(progress)progress(name?[NSString stringWithFormat:@"%d/%d %s",index+1,total,name]:@"verifying");
}
static NSDictionary *files(NSString *path) {
    NSArray *names=[NSFileManager.defaultManager contentsOfDirectoryAtPath:path error:NULL];
    if(!names || names.count>4096)return nil;
    NSMutableDictionary *result=[NSMutableDictionary new];
    for(NSString *name in names) {
        if([name isEqual:@"manifest.json"])continue;
        if((![name hasPrefix:@"aot-v"] && ![name hasPrefix:@"system-aot-v"]) || (![name hasSuffix:@".dylib"] && ![name hasSuffix:@".dylib.signer"]))return nil;
        NSString *file=[path stringByAppendingPathComponent:name],*hash=digest(file);
        if(!hash || ([name hasSuffix:@".dylib"] && !signedFile(file)))return nil;
        result[name]=hash;
    }
    return result;
}
NSString *mac_aot_prepare(NSArray<NSString *> *apks,NSString *runtimeRoot,void (^progress)(NSString *),NSError **error) {
    NSString *reason=@"JIT-less 缓存校验失败，请重新导入游戏。";
    NSString *result=nil,*stage=nil;
    int lock=-1;BOOL ownStage=NO;
    do {
        if(!apks.count || apks.count>TL_LD_MAX_APKS)break;
        NSString *root=[apks[0].stringByDeletingLastPathComponent stringByAppendingPathComponent:@"jitless"];
        // A colon would be interpreted as another loader search directory.
        if([root containsString:@":"] || strlen(root.fileSystemRepresentation)>700 || !directory(root,YES))break;
        lock=open([root stringByAppendingPathComponent:@"prepare.lock"].fileSystemRepresentation,O_CREAT|O_RDWR|O_NOFOLLOW,0600);
        struct stat st;
        if(lock<0 || fstat(lock,&st) || !S_ISREG(st.st_mode) || st.st_uid!=getuid() || flock(lock,LOCK_EX|LOCK_NB)){
            reason=@"另一个运行进程正在准备 JIT-less，请稍后重试。";break;
        }
        NSMutableArray<NSString *> *paths=[apks mutableCopy];
        if(runtimeRoot){
            NSArray *relative=[[NSFileManager.defaultManager enumeratorAtPath:runtimeRoot].allObjects sortedArrayUsingSelector:@selector(compare:)];
            for(NSString *name in relative)if([name hasSuffix:@".so"])[paths addObject:[runtimeRoot stringByAppendingPathComponent:name]];
        }
        NSMutableArray *inputs=[NSMutableArray new];
        for(NSString *path in paths){NSString *hash=digest(path);if(!hash){reason=@"JIT-less 来源文件缺失或损坏。";break;}[inputs addObject:@[path.lastPathComponent,hash]];}
        if(inputs.count!=paths.count)break;
        // Change the revision when the fork's code rewrites or signer changes.
        NSDictionary *source=@{@"revision":@"mac-aot-3",@"format":@(TL_AOT_VERSION),@"inputs":inputs};
        NSData *identity=[NSJSONSerialization dataWithJSONObject:source options:NSJSONWritingSortedKeys error:NULL];
        uint8_t hash[32];CC_SHA256(identity.bytes,(CC_LONG)identity.length,hash);
        NSString *target=[root stringByAppendingPathComponent:hex(hash,sizeof(hash))];
        if(!lstat(target.fileSystemRepresentation,&st)){
            NSString *manifest=[target stringByAppendingPathComponent:@"manifest.json"];
            if(!directory(target,NO) || !regular(manifest) || [NSFileManager.defaultManager attributesOfItemAtPath:manifest error:NULL].fileSize>1048576)break;
            NSDictionary *record=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:manifest] options:0 error:NULL];
            NSDictionary *actual=files(target);
            if(![record isKindOfClass:NSDictionary.class] || ![record[@"source"] isEqual:source] || !actual || ![record[@"files"] isEqual:actual])break;
            result=target;break;
        }
        stage=[root stringByAppendingPathComponent:@".preparing"];
        if(!lstat(stage.fileSystemRepresentation,&st)){
            if(!directory(stage,NO) || ![NSFileManager.defaultManager removeItemAtPath:stage error:NULL])break;
        }
        if(!directory(stage,YES))break;
        ownStage=YES;
        const char **names=calloc(paths.count,sizeof(char *));
        if(!names)break;
        for(NSUInteger i=0;i<paths.count;i++)names[i]=paths[i].fileSystemRepresentation;
        char why[512]={0};
        int n=husk_aot_prepare(names,(int)apks.count,stage.fileSystemRepresentation,NULL,0,"","mac-adhoc-1",NULL,report,(__bridge void *)progress,why,sizeof(why));
        if(n>=0 && paths.count>apks.count)
            n=husk_aot_prepare_runtime(names+apks.count,(int)(paths.count-apks.count),stage.fileSystemRepresentation,NULL,0,"","mac-adhoc-1",NULL,report,(__bridge void *)progress,why,sizeof(why));
        free(names);
        if(n<0){reason=[NSString stringWithFormat:@"JIT-less 准备失败：%s",why];break;}
        NSDictionary *actual=files(stage);if(!actual)break;
        NSDictionary *record=@{@"source":source,@"files":actual};
        NSData *data=[NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingSortedKeys error:NULL];
        if(![data writeToFile:[stage stringByAppendingPathComponent:@"manifest.json"] options:NSDataWritingAtomic error:NULL])break;
        if(rename(stage.fileSystemRepresentation,target.fileSystemRepresentation))break;
        stage=nil;result=target;
    }while(0);
    if(stage && ownStage)[NSFileManager.defaultManager removeItemAtPath:stage error:NULL];
    if(lock>=0)close(lock);
    if(!result && error)*error=[NSError errorWithDomain:@"org.husk.AOT" code:1 userInfo:@{NSLocalizedDescriptionKey:reason}];
    return result;
}
