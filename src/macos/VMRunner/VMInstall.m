/* SPDX-License-Identifier: GPL-2.0-or-later */
#import "VMInstall.h"
#import <CommonCrypto/CommonDigest.h>

static void failure(NSError **error, NSString *message) {
    if(error && !*error)*error=[NSError errorWithDomain:@"HuskVM" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
static NSString *digest(NSString *path) {
    NSInputStream *stream=[NSInputStream inputStreamWithFileAtPath:path];[stream open];
    CC_SHA256_CTX context;CC_SHA256_Init(&context);uint8_t bytes[65536],out[32];NSInteger n;
    while((n=[stream read:bytes maxLength:sizeof(bytes)])>0)CC_SHA256_Update(&context,bytes,(CC_LONG)n);
    [stream close];if(n<0)return nil;CC_SHA256_Final(out,&context);
    NSMutableString *result=[NSMutableString new];for(int i=0;i<32;i++)[result appendFormat:@"%02x",out[i]];return result;
}
NSDictionary *VMInstallAPKs(VMConnection *bridge, NSArray *files, NSError **error) {
    if(![files isKindOfClass:NSArray.class]||!files.count||files.count>32){failure(error,@"Invalid APK set");return nil;}
    uint64_t total=0;NSMutableArray<NSNumber *> *sizes=[NSMutableArray new];
    for(id record in files){
        if(![record isKindOfClass:NSDictionary.class]){failure(error,@"Invalid APK record");return nil;}
        NSString *path=record[@"apk"],*hash=record[@"sha256"];
        if(![path isKindOfClass:NSString.class]||![hash isKindOfClass:NSString.class]||hash.length!=64||![digest(path) isEqual:hash]){
            failure(error,@"APK hash mismatch");return nil;
        }
        uint64_t size=[NSFileManager.defaultManager attributesOfItemAtPath:path error:error].fileSize;
        if(!size||size>(4ULL<<30)||total>(4ULL<<30)-size){failure(error,@"APK set too large");return nil;}
        total+=size;[sizes addObject:@(size)];
    }
    int status=-1;
    NSString *created=[bridge shell:[NSString stringWithFormat:@"pm install-create -r -S %llu",total] timeout:60 status:&status error:error];
    NSRegularExpression *pattern=[NSRegularExpression regularExpressionWithPattern:@"Success: created install session \\[([0-9]+)\\]" options:0 error:nil];
    NSTextCheckingResult *match=created?[pattern firstMatchInString:created options:0 range:NSMakeRange(0,created.length)]:nil;
    if(status!=0||!match){failure(error,created?:@"Could not create installation session");return nil;}
    NSString *session=[created substringWithRange:[match rangeAtIndex:1]];
    NSMutableArray<NSString *> *temporary=[NSMutableArray new];BOOL committed=NO;
    NSDictionary *result=nil;
    @try {
        for(NSUInteger i=0;i<files.count;i++){
            NSString *remote=[NSString stringWithFormat:@"/data/local/tmp/husk-install-%lu.apk",(unsigned long)i];
            [temporary addObject:remote];
            if(![bridge push:files[i][@"apk"] remote:remote error:error])return nil;
            NSString *remoteHash=[bridge shell:[@"sha256sum " stringByAppendingString:remote] timeout:120 status:&status error:error];
            NSString *expected=[files[i][@"sha256"] stringByAppendingString:@"  "];
            if(status!=0||![remoteHash hasPrefix:expected]){failure(error,@"Transferred APK hash mismatch");return nil;}
            NSString *command=[NSString stringWithFormat:@"pm install-write -S %@ %@ part%lu %@",sizes[i],session,(unsigned long)i,remote];
            NSString *written=[bridge shell:command timeout:600 status:&status error:error];
            if(status!=0||![written hasPrefix:@"Success"]){failure(error,written?:@"APK write failed");return nil;}
        }
        NSString *out=[bridge shell:[@"pm install-commit " stringByAppendingString:session] timeout:600 status:&status error:error];
        committed=status==0&&[out hasPrefix:@"Success"];
        if(out)result=@{@"status":@(status),@"output":out};
    } @finally {
        if(!committed)[bridge shell:[@"pm install-abandon " stringByAppendingString:session] timeout:20 status:NULL error:nil];
        if(temporary.count)[bridge shell:[@"rm -f " stringByAppendingString:[temporary componentsJoinedByString:@" "]] timeout:20 status:NULL error:nil];
    }
    return result;
}
