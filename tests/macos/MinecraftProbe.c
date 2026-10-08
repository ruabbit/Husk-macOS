/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Explicit, bounded, offscreen diagnostics for a user-supplied Minecraft APK. */
#define _DARWIN_C_SOURCE
#include "husk-tl-gameactivity.h"
#include "husk-tl-gamepad.h"
#include "husk-tl-audio.h"
#include "husk-tl-jni.h"
#include "husk-tl-ld.h"
#include "husk-tl-xmem.h"
#include <mach/mach.h>
#include <pthread.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ucontext.h>
#include <time.h>
#include <unistd.h>

void tl_log_line(const char *format, ...)
{
    va_list args; va_start(args,format);
    flockfile(stderr); vfprintf(stderr,format,args); fputc('\n',stderr); funlockfile(stderr);
    va_end(args);
}

static void describe(const char *label, uintptr_t address)
{
    const char *library=NULL; const void *symbolAddress=NULL;
    const char *symbol=tl_ld_symbol_at((void *)address,&library,&symbolAddress);
    dprintf(STDERR_FILENO,"%s=%#lx %s %s+%#lx\n",label,(unsigned long)address,
        library?library:"host",symbol?symbol:"?",symbolAddress?(unsigned long)(address-(uintptr_t)symbolAddress):0);
}

static void failedSignal(int signal, siginfo_t *info, void *context)
{
    ucontext_t *uc=context; _STRUCT_ARM_THREAD_STATE64 *registers=&uc->uc_mcontext->__ss;
    dprintf(STDERR_FILENO,"guest failure: signal=%d address=%p\n",signal,info->si_addr);
    describe("pc",registers->__pc); describe("lr",registers->__lr);
    uintptr_t frame=registers->__fp;
    for(int i=0;i<16&&frame&&!(frame&7);i++) {
        uint64_t pair[2];vm_size_t size=0;
        if(vm_read_overwrite(mach_task_self(),frame,sizeof(pair),(vm_address_t)pair,&size)!=KERN_SUCCESS||size!=sizeof(pair))break;
        describe("frame",pair[1]);frame=pair[0];
    }
    for(int i=0;i<29;i++)dprintf(STDERR_FILENO,"x%d=%#llx%s",i,registers->__x[i],i%4==3?"\n":" ");
    dprintf(STDERR_FILENO,"\nsp=%#llx fp=%#llx\n",registers->__sp,registers->__fp);
    _exit(128+signal);
}

static void *deadline(void *seconds)
{
    sleep((unsigned)(uintptr_t)seconds);
    const char message[]="probe deadline exceeded\n";write(STDERR_FILENO,message,sizeof(message)-1);
    _exit(124);
}

int main(int argc,char **argv)
{
    if(argc!=6){fprintf(stderr,"usage: MinecraftProbe APK DATA ANGLE FRAMES SECONDS\n");return 64;}
    int seconds=atoi(argv[5]);if(seconds<1||seconds>1800)return 64;
    static unsigned char stack[65536];stack_t alternate={.ss_sp=stack,.ss_size=sizeof(stack)};sigaltstack(&alternate,NULL);
    struct sigaction action={0};action.sa_sigaction=failedSignal;action.sa_flags=SA_SIGINFO|SA_ONSTACK;
    int signals[]={SIGSEGV,SIGBUS,SIGILL,SIGABRT,SIGTRAP};
    for(unsigned i=0;i<sizeof(signals)/sizeof(signals[0]);i++)sigaction(signals[i],&action,NULL);
    pthread_t timeout;pthread_create(&timeout,NULL,deadline,(void *)(uintptr_t)(seconds+120));
    setenv("TL_AUDIO_MUTE","1",1);if(!getenv("TL_XMEM_MIB"))setenv("TL_XMEM_MIB","1024",1);
    tl_ld_set_verbosity(1);tl_jni_set_trace(1);tl_audio_install();
    tl_ga_config configuration={.apk_path=argv[1],.data_dir=argv[2],.package_name="com.mojang.minecraftpe",
        .width=1280,.height=720,.angle_egl=argv[3],.frame_dir=argv[4],.frame_every=-120};
    if(!tl_ga_start(&configuration)){fprintf(stderr,"probe: load failed\n");return 70;}
    fprintf(stderr,"probe: loaded, unresolved=%zu, executable=%zu MiB\n",tl_ld_unresolved_count(),tl_xmem_used()>>20);
    if(!tl_ga_run()){fprintf(stderr,"probe: activity failed\n");return 70;}
    for(int i=0;i<seconds;i++){sleep(1);if(i%5==0)fprintf(stderr,"probe: %ds frames=%lu\n",i+1,tl_ga_frames());}
    fprintf(stderr,"probe: completed %ds frames=%lu\n",seconds,tl_ga_frames());
    return tl_ga_frames()>0?0:71;
}
