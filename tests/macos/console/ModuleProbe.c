/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-console-abi.h"
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <stddef.h>
#define CHECK(x) do { if (!(x)) { fprintf(stderr,"FAIL actual console module line %d: %s\n",__LINE__,#x); return 1; } } while (0)
int main(int argc,char **argv) {
    CHECK(argc==4);
    void *handle=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);
    if(!handle){fprintf(stderr,"%s\n",dlerror());return 1;}
    husk_console_module_v1_fn entry=(husk_console_module_v1_fn)dlsym(handle,"husk_console_module_v1");CHECK(entry);
    const HuskConsoleModuleV1 *module=entry();
    CHECK(module && module->version==HUSK_CONSOLE_ABI_VERSION && !strcmp(module->platform,"ps4"));
    CHECK(module->struct_size>=offsetof(HuskConsoleModuleV1,join_worker)+sizeof(module->join_worker));
    CHECK(module->join_worker && module->join_worker()==0 && module->join_worker()==0);
    CHECK(module->init && module->launch && module->state && module->frames && module->set_paused && module->set_pad && module->resize && module->stop && module->install_package);
    CHECK(module->jit_ceiling_bytes>0 && module->state()==HUSK_CONSOLE_IDLE && module->frames()==0);
    CHECK(module->init(NULL,argv[3])!=0); // Does not initialize audio, graphics, a game or guest workers.
    char error[512]={0};CHECK(module->install_package(argv[2],argv[3],NULL,NULL,error,sizeof(error))!=0 && error[0]);
    printf("PASS actual PS4 module loads with ABI v1, rejects missing host and invalid PKG: %s\n",error);
    // Module contract is one load per process; do not dlclose static worker owners.
    return 0;
}
