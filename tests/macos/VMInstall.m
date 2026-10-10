/* SPDX-License-Identifier: GPL-2.0-or-later */
#import "VMInstall.h"
#import <CommonCrypto/CommonDigest.h>
@interface FakeInstallBridge : VMConnection
@property NSMutableArray<NSString *> *commands;
@property NSString *expectedHash;
@property BOOL failWrite;
@end
@implementation FakeInstallBridge
- (instancetype)init { if((self=[super initPort:0]))_commands=[NSMutableArray new];return self; }
- (BOOL)push:(NSString *)path remote:(NSString *)remote error:(NSError **)error {
    [_commands addObject:[@"push " stringByAppendingString:remote]];return YES;
}
- (NSString *)shell:(NSString *)command timeout:(double)timeout status:(int *)status error:(NSError **)error {
    [_commands addObject:command];if(status)*status=0;
    if([command hasPrefix:@"pm install-create"])return @"Success: created install session [123]";
    if([command hasPrefix:@"sha256sum "])return [_expectedHash stringByAppendingString:@"  /data/local/tmp/file.apk"];
    if(_failWrite&&[command containsString:@"part1 "]){if(status)*status=1;return @"Failure [INSTALL_FAILED_INVALID_APK]";}
    return @"Success";
}
@end
int main(void){@autoreleasepool{
    NSString *directory=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path=[directory stringByAppendingPathComponent:@"file.apk"];
    NSData *data=[@"synthetic APK transfer" dataUsingEncoding:NSUTF8StringEncoding];[data writeToFile:path atomically:YES];
    uint8_t digest[32];CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
    NSMutableString *hash=[NSMutableString new];for(int i=0;i<32;i++)[hash appendFormat:@"%02x",digest[i]];
    NSArray *files=@[@{@"apk":path,@"sha256":hash},@{@"apk":path,@"sha256":hash}];
    for(int fail=0;fail<2;fail++){
        FakeInstallBridge *bridge=[FakeInstallBridge new];bridge.expectedHash=hash;bridge.failWrite=fail;
        NSError *error=nil;NSDictionary *result=VMInstallAPKs(bridge,files,&error);
        NSString *commands=[bridge.commands componentsJoinedByString:@"\n"];
        if(fail){assert(!result&&error);assert([commands containsString:@"pm install-abandon 123"]);assert(![commands containsString:@"pm install-commit"]);}
        else{assert(!error&&[result[@"status"] intValue]==0);assert([commands containsString:@"pm install-commit 123"]);assert(![commands containsString:@"install-abandon"]);}
        assert([commands containsString:@"part0"]&&[commands containsString:@"part1"]);
        assert([commands containsString:@"rm -f /data/local/tmp/husk-install-0.apk /data/local/tmp/husk-install-1.apk"]);
    }
    FakeInstallBridge *bridge=[FakeInstallBridge new];NSError *error=nil;
    assert(!VMInstallAPKs(bridge,@[@{@"apk":path,@"sha256":[@"0" stringByPaddingToLength:64 withString:@"0" startingAtIndex:0]}],&error));
    assert(bridge.commands.count==0&&error);
    [NSFileManager.defaultManager removeItemAtPath:directory error:nil];
    puts("VM APK set: one commit, failed-write abandon, transfer cleanup, preflight hashes passed");return 0;
}}
