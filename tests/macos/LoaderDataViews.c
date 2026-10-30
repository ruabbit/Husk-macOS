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
#include <fcntl.h>
#include <string.h>
#include <mach/mach.h>
#define CHECK(c) do { if (!(c)) { fprintf(stderr,"FAIL data view line %d: %s\n",__LINE__,#c); return 1; } } while (0)
typedef struct { uint32_t type,flags; uint64_t offset,vaddr,paddr,filesz,memsz,align; } PH;
typedef struct { uintptr_t symbol; uint64_t file; int found; } Range;
static int locate(uintptr_t bias,const char *name,const void *raw,unsigned count,void *user) {
    (void)name;Range *r=user;const PH *ph=raw;
    for(unsigned i=0;i<count;i++)if(ph[i].type==1 && r->symbol>=bias+ph[i].vaddr && r->symbol<bias+ph[i].vaddr+ph[i].filesz){
        r->file=ph[i].offset+r->symbol-bias-ph[i].vaddr;r->found=1;return 1;
    }
    return 0;
}
int main(int argc,char **argv) {
    if(argc!=2 && argc!=4)return 64;
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
        int (*value)(void)=tl_ld_sym(lib,"static_alias_value");CHECK(value && value()==73);
        Range range={.symbol=(uintptr_t)value};tl_ld_iterate(locate,&range);CHECK(range.found && range.file%16384==0);
        if(getenv("HUSK_REQUIRE_FILE_TRANSLATION"))CHECK(range.file!=(uintptr_t)value-(uintptr_t)tl_ld_lib_base(lib));
        int fd=open(argv[1],O_RDONLY);CHECK(fd>=0);
        void *alias=map(NULL,16384,PROT_READ|PROT_EXEC,2,fd,(long)range.file);CHECK(alias!=MAP_FAILED);
        CHECK(!memcmp(alias,(void *)value,8) && ((int (*)(void))alias)()==73);
        CHECK(vm_protect(mach_task_self(),(vm_address_t)alias,16384,FALSE,VM_PROT_READ|VM_PROT_WRITE|VM_PROT_EXECUTE)!=KERN_SUCCESS);
        CHECK(unmap(alias,16384)==0 && value()==73);
        void *reserved=map(NULL,32768,PROT_READ|PROT_WRITE,0x22,-1,0);CHECK(reserved!=MAP_FAILED);
        CHECK(map(reserved,16384,PROT_READ|PROT_EXEC,0x12,fd,(long)range.file)==reserved);
        CHECK(((int (*)(void))reserved)()==73);((char *)reserved)[16384]=42;
        CHECK(map((void *)value,16384,PROT_READ|PROT_EXEC,0x12,fd,(long)range.file)==MAP_FAILED);
        CHECK(unmap(reserved,32768)==0 && value()==73);
        CHECK(map(NULL,0,PROT_READ|PROT_EXEC,2,fd,(long)range.file)==MAP_FAILED);
        CHECK(map(NULL,SIZE_MAX,PROT_READ|PROT_EXEC,2,fd,(long)range.file)==MAP_FAILED);
        CHECK(map(NULL,16384,PROT_READ|PROT_WRITE|PROT_EXEC,2,fd,(long)range.file)==MAP_FAILED);
        CHECK(map(NULL,16384,PROT_READ|PROT_EXEC,2,fd,0)==MAP_FAILED);
        CHECK(map(NULL,16384,PROT_READ|PROT_EXEC,2,fd,(long)range.file+4096)==MAP_FAILED);
        CHECK(map(NULL,16384,PROT_READ|PROT_EXEC,2,fd,0x7fffffffffffC000L)==MAP_FAILED);
        close(fd);
        if(argc==4){
            fd=open(argv[2],O_RDONLY);CHECK(fd>=0);
            alias=map(NULL,16384,PROT_READ|PROT_EXEC,2,fd,(long)range.file);CHECK(alias!=MAP_FAILED);
            CHECK(((int (*)(void))alias)()==73 && unmap(alias,16384)==0);close(fd);
            fd=open(argv[3],O_RDONLY);CHECK(fd>=0);
            CHECK(map(NULL,16384,PROT_READ|PROT_EXEC,2,fd,(long)range.file)==MAP_FAILED);close(fd);
        }
        puts("PASS signed static code alias: translated file offset, exact copied ELF, RX only, fixed reservation, release and rejection bounds");
    }
    puts("PASS ELF PC-relative and relocated data/code pointers; raw syscall NZCV and full q8-q15 preserved");return 0;
}
