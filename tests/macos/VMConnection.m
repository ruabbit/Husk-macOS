/* SPDX-License-Identifier: GPL-2.0-or-later */
#import <Foundation/Foundation.h>
#import "VMConnection.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>

static NSString *readLine(int fd) {
    NSMutableData *data=[NSMutableData new];char b;
    while(read(fd,&b,1)==1){if(b=='\n')break;[data appendBytes:&b length:1];}
    return [[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];
}
static NSString *token(NSString *line) {
    NSRegularExpression *r=[NSRegularExpression regularExpressionWithPattern:@"HUSK_[A-Fa-f0-9-]+_[0-9]+" options:0 error:nil];
    NSTextCheckingResult *m=[r firstMatchInString:line options:0 range:NSMakeRange(0,line.length)];
    return m?[line substringWithRange:m.range]:nil;
}
static void sendText(int fd,NSString *s) {NSData *d=[s dataUsingEncoding:NSUTF8StringEncoding];write(fd,d.bytes,d.length);}
int main(void){@autoreleasepool{
    signal(SIGPIPE,SIG_IGN);
    int server=socket(AF_INET,SOCK_STREAM,0);
    struct sockaddr_in addr={.sin_len=sizeof(addr),.sin_family=AF_INET,.sin_addr.s_addr=htonl(INADDR_LOOPBACK)};
    assert(bind(server,(struct sockaddr *)&addr,sizeof(addr))==0);assert(listen(server,1)==0);
    socklen_t size=sizeof(addr);getsockname(server,(struct sockaddr *)&addr,&size);
    dispatch_semaphore_t done=dispatch_semaphore_create(0);
    __block int seen=0;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{@autoreleasepool{
        int fd=accept(server,NULL,NULL);
        NSString *line=readLine(fd);seen++;NSString *t=token(line);assert(t);
        // A status digit arriving without its newline is not a complete frame.
        sendText(fd,[NSString stringWithFormat:@"hello\n%@:1",t]);usleep(100000);sendText(fd,@"7\n");
        line=readLine(fd);seen++;t=token(line);assert(t);
        sendText(fd,[NSString stringWithFormat:@"second\n%@:0\n",t]);
        line=readLine(fd);seen++;assert(token(line));
        // The client must timeout and close, without replaying the mutation.
        char b;assert(read(fd,&b,1)==0);close(fd);dispatch_semaphore_signal(done);
    }});
    VMConnection *connection=[[VMConnection alloc]initPort:ntohs(addr.sin_port)];
    NSError *error=nil;int status=-1;
    NSString *a=[connection shell:@"first" timeout:2 status:&status error:&error];
    assert(!error&&status==17&&[a isEqual:@"hello"]);
    NSString *b=[connection shell:@"second" timeout:2 status:&status error:&error];
    assert(!error&&status==0&&[b isEqual:@"second"]);
    assert([connection shell:@"mutation" timeout:1 status:&status error:&error]==nil&&error);
    assert(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC))==0&&seen==3);
    close(server);puts("VM bridge: split status, held connection, timeout, no mutation replay passed");
    return 0;
}}
