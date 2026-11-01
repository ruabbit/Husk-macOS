/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-binder.h"
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
void tl_log_line(const char *fmt, ...) { (void)fmt; }
typedef struct { uint64_t ws, wc, wb, rs, rc, rb; } wr;
static atomic_bool entered;
static int descriptor, result, error;
static void *reader(void *unused) {
    (void)unused; uint8_t data[128]; wr w = {.rs=sizeof(data),.rb=(uintptr_t)data};
    atomic_store(&entered,true);
    result = husk_binder_ioctl(descriptor,0xC0306201UL,&w); error=errno; return NULL;
}
static void echo(uint32_t c,uint32_t f,const uint8_t *d,size_t n,const uint64_t *o,size_t no,husk_binder_reply *r,void *cookie) {
    (void)c;(void)f;(void)o;(void)no;(void)cookie;
    r->data=malloc(n);assert(r->data);memcpy(r->data,d,n);r->data_size=n;
}
int main(void) {
    descriptor=husk_binder_open();assert(descriptor>=0);
    assert(fcntl(descriptor,F_GETFD)&FD_CLOEXEC);
    assert(husk_binder_mmap(descriptor,4096)!=MAP_FAILED);
    assert(husk_binder_mmap(descriptor,4096)==MAP_FAILED&&errno==EBUSY);
    assert(husk_binder_ioctl(descriptor,0xC0306201UL,NULL)<0&&errno==EINVAL);
    uint32_t truncated=0x40406300; wr bad={.ws=4,.wb=(uintptr_t)&truncated};
    assert(husk_binder_ioctl(descriptor,0xC0306201UL,&bad)<0);
    husk_binder_reply reply={0};uint8_t data[32]={0};uint64_t offset=UINT64_MAX;
    uint32_t h=husk_binder_add_local(echo,NULL);assert(h);
    assert(husk_binder_transact(h,1,0,data,sizeof(data),&offset,1,&reply)<0&&errno==EINVAL);
    assert(husk_binder_transact(h,1,0,data,SIZE_MAX,NULL,0,&reply)<0);
    assert(!husk_binder_transact(h,1,0,(void *)"persist",8,NULL,0,&reply));
    assert(reply.data_size==8&&!memcmp(reply.data,"persist",8));husk_binder_reply_free(&reply);
    pthread_t t;assert(!pthread_create(&t,NULL,reader,NULL));
    while(!atomic_load(&entered))usleep(1000);
    usleep(10000);husk_binder_close(descriptor);assert(!pthread_join(t,NULL));
    assert(result<0&&error==EBADF);close(descriptor);
    for(int i=0;i<80;i++){int fd=husk_binder_open();assert(fd>=0);husk_binder_close(fd);close(fd);}
    puts("PASS Binder bounded parcels, close wakes admitted reader, descriptor reuse and CLOEXEC");return 0;
}
