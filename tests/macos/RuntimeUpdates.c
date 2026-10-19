/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-bionic.h"
#include "husk-tl-ld.h"
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#define CHECK(x) do{if(!(x)){fprintf(stderr,"FAIL runtime update line %d: %s\n",__LINE__,#x);return 1;}}while(0)
void tl_set_data_dir(const char *);
static volatile sig_atomic_t signal_ok;
static void handler(int sig,void *info,void *ctx) {
    (void)info;
    // Linux arm64 ucontext puts the general registers at byte 184, SP/PC at 432/440.
    uint64_t *words=ctx;
    signal_ok=sig==10 && words && words[54]!=0 && words[55]!=0;
}
int main(int argc,char **argv) {
    if(argc!=2)return 64;
    void *(*map)(void *,size_t,int,int,int,long)=tl_bionic_find("mmap");
    int (*unmap)(void *,size_t)=tl_bionic_find("munmap");
    int (*access_file)(const char *,int)=tl_bionic_find("access");
    int (*open_file)(const char *,int,unsigned)=tl_bionic_find("open");
    int (*action)(int,const void *,void *)=tl_bionic_find("sigaction");
    CHECK(map&&unmap&&access_file&&open_file&&action);
    char file[]="/tmp/husk-runtime-map-XXXXXX";int fd=mkstemp(file);CHECK(fd>=0);unlink(file);
    unsigned char bytes[65536];for(size_t n=0;n<sizeof(bytes);n++)bytes[n]=(unsigned char)(n/4096+40);
    CHECK(write(fd,bytes,sizeof(bytes))==sizeof(bytes));
    void *maps[96];
    for(int n=0;n<96;n++){maps[n]=map(NULL,8192,PROT_READ,2,fd,4096);CHECK(maps[n]!=MAP_FAILED);CHECK(((unsigned char *)maps[n])[0]==41&&((unsigned char *)maps[n])[4096]==42);}
    if(getpagesize()>4096){CHECK(unmap(maps[0],4096)==-1);CHECK(((unsigned char *)maps[0])[4096]==42);}
    for(int n=0;n<96;n++)CHECK(unmap(maps[n],8192)==0);
    CHECK(map(NULL,0,PROT_READ,2,fd,4096)==MAP_FAILED);
    close(fd);
    CHECK(access_file("/proc/self/maps",R_OK)==0&&access_file("/proc/self/maps",W_OK)==-1);
    struct {int flags,pad;void *handler;uint64_t mask;void *restorer;} sa={4,0,(void *)handler,0,NULL};
    CHECK(action(10,&sa,NULL)==0);CHECK(raise(SIGUSR1)==0);CHECK(signal_ok);
    sa.handler=NULL;CHECK(action(10,&sa,NULL)==0);
    char root[]="/tmp/husk-runtime-libs-XXXXXX";CHECK(mkdtemp(root));tl_set_data_dir(root);
    char dir[1024],path[1200];snprintf(dir,sizeof(dir),"%s/lib",root);CHECK(mkdir(dir,0700)==0);
    snprintf(path,sizeof(path),"%s/libcrypto.so",dir);fd=open(path,O_CREAT|O_WRONLY,0600);CHECK(fd>=0);close(fd);
    CHECK(tl_ld_add_apk(argv[1]));
    fd=open_file(path,0,0);CHECK(fd>=0);char magic[4];CHECK(read(fd,magic,4)==4&&!memcmp(magic,"\177ELF",4));close(fd);
    unlink(path);rmdir(dir);rmdir(root);
    puts("PASS 96 shifted mappings, partial-unmap rejection, proc access, Linux signal context and APK library materialization");return 0;
}
