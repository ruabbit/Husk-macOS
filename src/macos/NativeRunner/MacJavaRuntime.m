/* SPDX-License-Identifier: GPL-2.0-or-later */
#import "MacJavaRuntime.h"
#import <CommonCrypto/CommonDigest.h>
#include "husk-tl-dvm-boot.h"
#include <pthread.h>

BOOL mac_java_accepts_scan(NSDictionary *scan)
{
    NSArray *abis=scan[@"abis"], *libraries=scan[@"libraries"];
    NSString *engine=[scan[@"engine"] isKindOfClass:NSString.class]?scan[@"engine"]:nil;
    if(![scan[@"ok"] boolValue]||![scan[@"hasManifest"] boolValue]||![abis isKindOfClass:NSArray.class]||
        (abis.count&&![abis containsObject:@"arm64-v8a"]))return NO;
    if(!abis.count)return [scan[@"dexCount"] intValue]>0 && (!scan[@"webKind"]||scan[@"webKind"]==NSNull.null);
    if([engine isEqual:@"Unity 6"])return YES;
    if([engine isEqual:@"Cocos"]){for(NSDictionary *library in libraries)if([library[@"name"] isEqual:@"libfmod.so"])return NO;return YES;}
    if([engine isEqual:@"SDL"]){for(NSDictionary *library in libraries)if([library[@"name"] hasPrefix:@"libdxvk"])return NO;return YES;}
    if([@[@"Python",@"Flutter",@"libGDX",@"Java",@"React Native",@".NET / Xamarin"] containsObject:engine?:@""])return YES;
    return !engine&&[scan[@"dexCount"] intValue]>0;
}

static NSString *sha256(NSString *path)
{
    NSFileHandle *file=[NSFileHandle fileHandleForReadingAtPath:path];if(!file)return nil;
    CC_SHA256_CTX hash;CC_SHA256_Init(&hash);
    @try{NSData *chunk;while((chunk=[file readDataOfLength:1<<20]).length)CC_SHA256_Update(&hash,chunk.bytes,(CC_LONG)chunk.length);}
    @catch(NSException *error){[file closeFile];return nil;}
    [file closeFile];unsigned char bytes[CC_SHA256_DIGEST_LENGTH];CC_SHA256_Final(bytes,&hash);
    NSMutableString *result=[NSMutableString new];for(int i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[result appendFormat:@"%02x",bytes[i]];return result;
}
static BOOL validate(NSString *root)
{
    NSData *data=[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"runtime-manifest.json"]];
    NSDictionary *manifest=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]:nil;
    NSDictionary *files=manifest[@"files"];
    if(![manifest isKindOfClass:NSDictionary.class]||![manifest[@"schema"] isEqual:@1]||![files isKindOfClass:NSDictionary.class]||files.count<30)return NO;
    for(NSString *name in files){
        if(![name isKindOfClass:NSString.class]||name.isAbsolutePath||[name.pathComponents containsObject:@".."]||[name.pathComponents containsObject:@"."])return NO;
        NSString *path=[root stringByAppendingPathComponent:name];
        if(![[path stringByResolvingSymlinksInPath] isEqual:path.stringByStandardizingPath])return NO;
        NSDictionary *entry=files[name];
        if(![entry isKindOfClass:NSDictionary.class]||![sha256(path) isEqual:entry[@"sha256"]])return NO;
    }
    return files[@"husk-framework.dex"]&&files[@"framework-res.apk"]&&files[@"com.android.art/javalib/core-oj.jar"]&&
        files[@"android-system/etc/fonts.xml"]&&files[@"android-system/etc/font_fallback.xml"];
}
BOOL mac_runtime_configure(NSString *root)
{
    static NSString *configuredRoot;
    if([configuredRoot isEqual:root])return YES;
    if(!validate(root)){fprintf(stderr,"runtime: resource verification failed\n");return NO;}
    void tl_set_cacerts_dir(const char *);
    void tl_set_system_fonts_dir(const char *);
    tl_set_cacerts_dir([root stringByAppendingPathComponent:@"com.android.conscrypt/cacerts"].fileSystemRepresentation);
    tl_set_system_fonts_dir([root stringByAppendingPathComponent:@"android-system"].fileSystemRepresentation);
    configuredRoot=[root copy];
    return YES;
}
typedef struct { const char *root,*data; bool ok; } Boot;
static void *boot(void *p) { Boot *b=p;b->ok=tl_dvm_boot(b->root,b->data);return NULL; }
BOOL mac_java_start(NSString *root,const tl_javaapp_config *cfg)
{
    if(!mac_runtime_configure(root))return NO;
    Boot b={root.fileSystemRepresentation,cfg->data_dir,false};
    pthread_attr_t attr;pthread_attr_init(&attr);pthread_attr_setstacksize(&attr,256u<<20);
    pthread_t t;int error=pthread_create(&t,&attr,boot,&b);pthread_attr_destroy(&attr);
    if(error)return NO;pthread_join(t,NULL);
    if(!b.ok)return NO;
    return tl_javaapp_start(cfg);
}
