/* SPDX-License-Identifier: GPL-2.0-or-later */
#import "VMConnection.h"
#include <sys/socket.h>
#include <sys/un.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <poll.h>
#include <errno.h>

static void failure(NSError **error, NSString *message) {
    if(error)*error=[NSError errorWithDomain:@"HuskVM" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
static BOOL sendAll(int fd, NSData *data, NSError **error) {
    NSUInteger offset=0;
    while(offset<data.length){ssize_t n=write(fd,(const char *)data.bytes+offset,data.length-offset);
        if(n<0&&errno==EINTR)continue;
        if(n<=0){failure(error,@"VM transport write failed");return NO;}offset+=n;}
    return YES;
}
static int openFD(void) {
    int fd=socket(AF_INET,SOCK_STREAM,0),on=1;
    if(fd>=0)setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&on,sizeof(on));
    return fd;
}

@implementation VMConnection {
    uint16_t _port;
    int _fd;
    NSRecursiveLock *_lock;
    uint64_t _sequence;
    NSString *_nonce;
}
- (instancetype)initPort:(uint16_t)port {
    if((self=[super init])){_port=port;_fd=-1;_lock=[NSRecursiveLock new];_nonce=NSUUID.UUID.UUIDString;}return self;
}
- (void)close { [_lock lock];if(_fd>=0)close(_fd);_fd=-1;[_lock unlock]; }
- (BOOL)connect:(double)timeout error:(NSError **)error {
    if(_fd<0){
        _fd=openFD();struct sockaddr_in addr={.sin_len=sizeof(addr),.sin_family=AF_INET,.sin_port=htons(_port)};
        addr.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
        if(_fd<0||connect(_fd,(struct sockaddr *)&addr,sizeof(addr))!=0){[self close];failure(error,@"Android bridge is not available");return NO;}
    }
    struct timeval t={.tv_sec=MAX(1,(int)timeout)};
    setsockopt(_fd,SOL_SOCKET,SO_RCVTIMEO,&t,sizeof(t));setsockopt(_fd,SOL_SOCKET,SO_SNDTIMEO,&t,sizeof(t));return YES;
}
- (NSString *)receive:(NSString *)token timeout:(double)timeout status:(int *)status error:(NSError **)error {
    NSMutableData *buffer=[NSMutableData new];double deadline=NSProcessInfo.processInfo.systemUptime+timeout;
    NSData *needle=[[NSString stringWithFormat:@"\n%@:",token] dataUsingEncoding:NSUTF8StringEncoding];
    while(NSProcessInfo.processInfo.systemUptime<deadline){
        uint8_t bytes[16384];struct pollfd p={.fd=_fd,.events=POLLIN};
        int result=poll(&p,1,MIN(1000,MAX(1,(deadline-NSProcessInfo.processInfo.systemUptime)*1000)));
        if(result<0&&errno==EINTR)continue;if(result==0)continue;
        ssize_t n=read(_fd,bytes,sizeof(bytes));if(n<0&&errno==EINTR)continue;
        if(n<=0){failure(error,@"Android bridge disconnected");[self close];return nil;}
        [buffer appendBytes:bytes length:n];
        if(buffer.length>2*1024*1024){failure(error,@"Android response exceeded 2 MiB");[self close];return nil;}
        NSRange marker=[buffer rangeOfData:needle options:0 range:NSMakeRange(0,buffer.length)];
        if(marker.location!=NSNotFound){
            NSUInteger start=NSMaxRange(marker);NSData *newline=[@"\n" dataUsingEncoding:NSUTF8StringEncoding];
            NSRange end=[buffer rangeOfData:newline options:0 range:NSMakeRange(start,buffer.length-start)];
            if(end.location==NSNotFound)continue;
            NSString *code=[[NSString alloc] initWithData:[buffer subdataWithRange:NSMakeRange(start,end.location-start)] encoding:NSUTF8StringEncoding];
            NSScanner *scanner=[NSScanner scannerWithString:code?:@""];int value=0;
            if(![scanner scanInt:&value]||!scanner.isAtEnd){failure(error,@"Invalid Android status frame");[self close];return nil;}
            if(status)*status=value;
            return [[NSString alloc] initWithData:[buffer subdataWithRange:NSMakeRange(0,marker.location)] encoding:NSUTF8StringEncoding]?:@"";
        }
    }
    // Never replay a command after timeout: installation/shutdown can already
    // have succeeded. Discard the connection so late output cannot cross calls.
    failure(error,@"Android bridge command timed out; command was not retried");[self close];return nil;
}
- (NSString *)shell:(NSString *)command timeout:(double)timeout status:(int *)status error:(NSError **)error {
    [_lock lock];
    if(![self connect:timeout error:error]){[_lock unlock];return nil;}
    NSString *token=[NSString stringWithFormat:@"HUSK_%@_%llu",_nonce,++_sequence];
    NSString *line=[NSString stringWithFormat:@"{ %@; } 2>&1; __husk_status=$?; printf '\\n%@:%%d\\n' \"$__husk_status\"\n",command,token];
    NSString *answer=nil;
    if(sendAll(_fd,[line dataUsingEncoding:NSUTF8StringEncoding],error))answer=[self receive:token timeout:timeout status:status error:error];
    else [self close];
    [_lock unlock];return answer;
}
- (BOOL)push:(NSString *)path remote:(NSString *)remote error:(NSError **)error {
    // Remote name is controlled by the caller; no user path is sent as shell text.
    NSRegularExpression *allowed=[NSRegularExpression regularExpressionWithPattern:@"^/data/local/tmp/husk-install(?:-(?:[0-9]|[12][0-9]|3[01]))?\\.apk$" options:0 error:nil];
    if(![allowed firstMatchInString:remote options:0 range:NSMakeRange(0,remote.length)]){failure(error,@"Invalid transfer destination");return NO;}
    NSFileHandle *file=[NSFileHandle fileHandleForReadingAtPath:path];
    uint64_t size=[NSFileManager.defaultManager attributesOfItemAtPath:path error:error].fileSize;
    if(!file||!size){failure(error,@"Cannot read APK");return NO;}
    [_lock lock];double timeout=MAX(180,size/300000.0);
    BOOL ok=[self connect:timeout error:error];
    NSString *token=[NSString stringWithFormat:@"HUSK_%@_%llu",_nonce,++_sequence];
    NSString *line=[NSString stringWithFormat:@"head -c %llu > %@; __husk_status=$?; printf '\\n%@:%%d\\n' \"$__husk_status\"\n",size,remote,token];
    if(ok)ok=sendAll(_fd,[line dataUsingEncoding:NSUTF8StringEncoding],error);
    uint64_t sent=0;
    while(ok&&sent<size){@autoreleasepool{
        NSData *chunk=[file readDataOfLength:MIN(256*1024,size-sent)];
        if(!chunk.length){failure(error,@"APK changed during transfer");ok=NO;break;}
        ok=sendAll(_fd,chunk,error);sent+=chunk.length;
    }}
    int status=-1;
    if(ok)ok=[self receive:token timeout:timeout status:&status error:error]!=nil&&status==0;
    if(!ok)[self close];[file closeFile];[_lock unlock];return ok;
}
@end

static NSDictionary *readJSON(int fd, NSMutableData *buffer, NSError **error) {
    double deadline=NSProcessInfo.processInfo.systemUptime+5;
    while(NSProcessInfo.processInfo.systemUptime<deadline){
        const uint8_t *b=buffer.bytes;for(NSUInteger i=0;i<buffer.length;i++)if(b[i]=='\n'){
            NSData *line=[buffer subdataWithRange:NSMakeRange(0,i)];[buffer replaceBytesInRange:NSMakeRange(0,i+1) withBytes:NULL length:0];
            id object=[NSJSONSerialization JSONObjectWithData:line options:0 error:error];
            if([object isKindOfClass:NSDictionary.class])return object;return nil;
        }
        struct pollfd p={.fd=fd,.events=POLLIN};int rc=poll(&p,1,500);if(rc<0&&errno==EINTR)continue;if(rc==0)continue;
        uint8_t bytes[4096];ssize_t n=read(fd,bytes,sizeof(bytes));if(n<0&&errno==EINTR)continue;
        if(n<=0){failure(error,@"QMP disconnected");return nil;}[buffer appendBytes:bytes length:n];
        if(buffer.length>2*1024*1024){failure(error,@"QMP response too large");return nil;}
    }
    failure(error,@"QMP response timed out");return nil;
}
NSDictionary *VMQMP(NSString *path, NSString *command, NSDictionary *arguments, NSError **error) {
    int fd=socket(AF_UNIX,SOCK_STREAM,0),on=1;struct sockaddr_un addr={.sun_len=sizeof(addr),.sun_family=AF_UNIX};
    if(fd<0||strlen(path.fileSystemRepresentation)>=sizeof(addr.sun_path)){if(fd>=0)close(fd);failure(error,@"Invalid QMP socket");return nil;}
    strlcpy(addr.sun_path,path.fileSystemRepresentation,sizeof(addr.sun_path));setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&on,sizeof(on));
    if(connect(fd,(struct sockaddr *)&addr,sizeof(addr))!=0){close(fd);failure(error,@"QMP is not ready");return nil;}
    struct timeval timeout={.tv_sec=5};setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout));
    NSMutableData *buffer=[NSMutableData new];NSDictionary *greeting=readJSON(fd,buffer,error),*answer=nil;
    if(greeting[@"QMP"]){
        NSArray *calls=@[@{@"execute":@"qmp_capabilities",@"id":@1},@{@"execute":command,@"arguments":arguments?:@{},@"id":@2}];
        for(NSDictionary *call in calls){
            NSMutableData *request=[[NSJSONSerialization dataWithJSONObject:call options:0 error:error] mutableCopy];[request appendBytes:"\n" length:1];
            if(!sendAll(fd,request,error))break;
            while((answer=readJSON(fd,buffer,error))&&![answer[@"id"] isEqual:call[@"id"]]){}
            if(!answer||answer[@"error"]){if(answer[@"error"])failure(error,[answer[@"error"] description]);answer=nil;break;}
        }
    }else failure(error,@"Invalid QMP greeting");
    close(fd);return answer;
}
