/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-bionic.h"
#include "husk-tl-ld.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/ucontext.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <net/if.h>
#define CHECK(c) do{if(!(c)){fprintf(stderr,"FAIL runtime compat line %d: %s\n",__LINE__,#c);return 1;}}while(0)
long tl_linux_syscall(long,long,long,long,long,long,long);
static long fut(uint32_t *a,int op,int n,long second,uint32_t *b,uint32_t encoded) {
    return tl_linux_syscall((long)a,op,n,second,(long)b,encoded,98);
}
int main(void) {
    uint32_t a=3,b=7;
    CHECK(fut(&a,5,0,0,&b,(1u<<28)|(7u<<12)|7)==0 && b==14);
    CHECK(fut(&a,5,0,0,&b,(1u<<28)|(15u<<24)|(1u<<12))==-38 && b==14);
    CHECK(fut(&a,5,0,0,NULL,0)==-22);
    CHECK(fut(&a,5,0,0,&b,(9u<<28)|(32u<<12))==-22 && b==14);
    CHECK(fut(&a,4,0,0,&b,2)==-11 && a==3);
    CHECK(fut(&a,4,0,0,&b,3)==0 && a==3);
    CHECK(fut(&a,0,4,0,NULL,0)==-11);
    puts("PASS futex wake-op arithmetic, pre-mutation rejection and requeue comparison");
    int (*guest_socket)(int,int,int)=tl_bionic_find("socket");
    int (*guest_opt)(int,int,int,const void *,unsigned)=tl_bionic_find("setsockopt");
    int (*guest_ioctl)(int,unsigned long,long)=tl_bionic_find("ioctl");
    CHECK(guest_socket && guest_opt && guest_ioctl);
    int fd=guest_socket(2,2,0);CHECK(fd>=0);
    uint8_t ifr[40]={0};strcpy((char *)ifr,"lo0");
    CHECK(guest_ioctl(fd,0x8933,(long)ifr)==0);
    uint32_t index;memcpy(&index,ifr+16,4);CHECK(index==if_nametoindex("lo0") && index>0);
    CHECK(guest_ioctl(fd,0x8913,(long)ifr)==0);uint16_t flags;memcpy(&flags,ifr+16,2);CHECK(flags&8);
    CHECK(guest_ioctl(fd,0x8921,(long)ifr)==0);int mtu;memcpy(&mtu,ifr+16,4);CHECK(mtu>0);
    uint8_t ttl=3;CHECK(guest_opt(fd,0,33,&ttl,1)==0);
    socklen_t n=1;uint8_t actual=0;CHECK(getsockopt(fd,IPPROTO_IP,IP_MULTICAST_TTL,&actual,&n)==0 && actual==3);
    int request[3]={0,0,(int)index};CHECK(guest_opt(fd,0,32,request,sizeof(request))==0);close(fd);
    fd=guest_socket(10,2,0);CHECK(fd>=0);
    CHECK(guest_opt(fd,0,33,&ttl,1)==0);int hops=0;n=sizeof(hops);
    CHECK(getsockopt(fd,IPPROTO_IPV6,IPV6_MULTICAST_HOPS,&hops,&n)==0 && hops==3);close(fd);
    puts("PASS loopback interface ioctl and IPv4/IPv6 multicast option layouts; no packets sent");
    char *(*guest_getenv)(const char *)=tl_bionic_find("getenv");CHECK(guest_getenv);
    CHECK(!strcmp(guest_getenv("JSC_useJIT"),"false") && !strcmp(guest_getenv("JSC_useWasm"),"false"));
    // Exercise the real trap decoder with an explicit saved context. Never raise a
    // signal, execute an illegal instruction, or kill a process to test recovery.
    uint32_t *page=mmap(NULL,16384,PROT_READ|PROT_WRITE,MAP_ANON|MAP_PRIVATE,-1,0);CHECK(page!=MAP_FAILED);
    page[0]=0xd4000001;page[1]=0xd503201f;
    struct __darwin_mcontext64 saved={0};ucontext_t context={0};context.uc_mcontext=&saved;
    __darwin_arm_thread_state64_set_pc_fptr(saved.__ss,(void *)page);saved.__ss.__x[8]=172;
    CHECK(!tl_ld_handle_guest_trap(SIGILL,&context));
    CHECK(tl_ld_track_generated(page,16384));tl_ld_mark_svcs(page,8);
    CHECK(page[0]==0x5c5 && page[1]==0xd503201f);
    CHECK(tl_ld_handle_guest_trap(SIGILL,&context) && saved.__ss.__x[0]==(uint64_t)getpid());
    CHECK((uintptr_t)__darwin_arm_thread_state64_get_pc(saved.__ss)==(uintptr_t)(page+1));
    saved.__es.__esr=0x2cu<<26;saved.__ns.__fpcr=0x9f00;
    CHECK(tl_ld_handle_guest_trap(SIGILL,&context) && saved.__ns.__fpcr==0);
    CHECK(!tl_ld_handle_guest_trap(SIGILL,&context)); // No retry loop with cleared enables.
    tl_ld_forget_generated(page,16384);saved.__ns.__fpcr=0x9f00;
    CHECK(!tl_ld_handle_guest_trap(SIGILL,&context) && saved.__ns.__fpcr==0x9f00);
    CHECK(tl_ld_track_generated(page,16384));CHECK(munmap(page,16384)==0);
    CHECK(!tl_ld_handle_guest_trap(SIGILL,&context)); // Stale mapped metadata cannot dereference an unmapped PC.
    tl_ld_forget_generated(page,16384);
    CHECK(!tl_ld_track_generated((void *)(UINTPTR_MAX-3),16));
    puts("PASS generated SVC rewrite and saved-context decoding, FP masking, host/stale/overflow rejection without injected faults");
    return 0;
}
