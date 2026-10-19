/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-ld.h"
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
    const uint32_t *metadata=tl_ld_sym(lib,"mono_data_word");
    if(metadata)CHECK(*metadata==0xd4000001); // only the Mono code range may be rewritten
    puts("PASS ELF PC-relative and relocated data/code pointers; raw syscall NZCV and full q8-q15 preserved");return 0;
}
