/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-ld.h"
#include "husk-tl-xmem.h"
#include "husk-tl-bionic.h"
#include <sys/mman.h>
#include <stdlib.h>
#include "MacDiagnostics.h"
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
#define CHECK(c) do { if (!(c)) { fprintf(stderr,"FAIL data view line %d: %s\n",__LINE__,#c); return 1; } } while (0)
int main(int argc,char **argv) {
    if(argc!=2)return 64;
    mac_runtime_diagnostics_install();
    tl_lib *lib=tl_ld_load(argv[1]);CHECK(lib&&tl_ld_init(lib));
    const uint64_t *(*address)(void)=tl_ld_sym(lib,"view_export");
    const uint64_t *(*relocation)(void)=tl_ld_sym(lib,"view_relocation");
    const void *(*code)(void)=tl_ld_sym(lib,"code_relocation");
    int (*syscall_registers)(long)=tl_ld_sym(lib,"raw_syscall_registers");
    CHECK(address&&relocation&&code&&syscall_registers);
    CHECK(address()==relocation());CHECK(address()==tl_ld_sym(lib,"view_value"));
    CHECK(*address()==UINT64_C(0x123456789abcdef));
    const uint64_t *(*indirect)(void)=(void *)code();CHECK(indirect&&indirect()==address());
    CHECK(syscall_registers(getpid()));
    uint32_t (*quad_direction)(void)=tl_ld_sym(lib,"quad_direction");
    CHECK(quad_direction && quad_direction()==0x3f800001);
    const uint32_t *metadata=tl_ld_sym(lib,"mono_data_word");
    if(metadata)CHECK(*metadata==0xd4000001); // only the Mono code range may be rewritten
    if(getenv("TL_NO_XMEM")) {
        CHECK(tl_xmem_size()==0 && tl_xmem_used()==0);
        void *(*map)(void *,size_t,int,int,int,long)=tl_bionic_find("mmap");
        int (*protect)(void *,size_t,int)=tl_bionic_find("mprotect");
        int (*unmap)(void *,size_t)=tl_bionic_find("munmap");
        CHECK(map(NULL,16384,PROT_READ|PROT_EXEC,0x22,-1,0)==MAP_FAILED);
        void *data=map(NULL,16384,PROT_READ|PROT_WRITE,0x22,-1,0);CHECK(data!=MAP_FAILED);
        CHECK(protect(data,16384,PROT_READ|PROT_EXEC)==-1);CHECK(unmap(data,16384)==0);
    }
    puts("PASS ELF PC-relative and relocated data/code pointers; raw syscall NZCV and full q8-q15 preserved");return 0;
}
