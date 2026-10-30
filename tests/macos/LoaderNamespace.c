/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-ld.h"
#include "husk-tl-bionic.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
typedef struct { uint32_t type,flags; uint64_t offset,vaddr,paddr,filesz,memsz,align; } PH;
typedef struct { uintptr_t symbol; uint64_t offset; bool found; } Alias;
static int alias_offset(uintptr_t bias,const char *name,const void *raw,unsigned count,void *user) {
    (void)name;Alias *a=user;const PH *ph=raw;
    for(unsigned i=0;i<count;i++)if(ph[i].type==1&&a->symbol>=bias+ph[i].vaddr&&a->symbol<bias+ph[i].vaddr+ph[i].filesz){
        a->offset=ph[i].offset+a->symbol-bias-ph[i].vaddr;a->found=true;return 1;
    }
    return 0;
}

#define CHECK(c) do { if (!(c)) { fprintf(stderr,"FAIL namespace line %d: %s\n",__LINE__,#c); return 1; } } while (0)
int main(int argc, char **argv)
{
    if (argc != 3) return 64;
    char system[1200], app[1200], apk[1200];
    snprintf(system,sizeof(system),"%s/system",argv[1]);
    tl_ld_add_search_dir(system);
    snprintf(system,sizeof(system),"%s/system/libclient.so",argv[1]);
    bool unpacked = strstr(argv[2],"unpacked") != NULL;
    snprintf(app,sizeof(app),unpacked ? "%s/system-app/libclient.so" : "libclient.so",argv[1]);
    if (!unpacked) {
        snprintf(apk,sizeof(apk),"%s/app.apk",argv[1]);
        CHECK(tl_ld_add_apk(apk));
    }
    bool system_first = strstr(argv[2],"system-first") != NULL;
    tl_lib *first = tl_ld_load(system_first ? system : app);
    CHECK(first && tl_ld_init(first));
    tl_lib *second = tl_ld_load(system_first ? app : system);
    CHECK(second && first != second && tl_ld_init(second));
    tl_lib *runtime = system_first ? first : second, *game = system_first ? second : first;
    int (*runtime_result)(void) = tl_ld_sym(runtime,"namespace_result");
    int (*app_result)(void) = tl_ld_sym(game,"namespace_result");
    CHECK(runtime_result && app_result);
    CHECK(runtime_result() == 2222 && app_result() == 1111);
    tl_lib *runtime_dependency = NULL, *app_dependency = NULL;
    int (*runtime_origin)(void) = tl_ld_sym_deep(runtime,"namespace_origin",&runtime_dependency);
    int (*app_origin)(void) = tl_ld_sym_deep(game,"namespace_origin",&app_dependency);
    CHECK(runtime_origin && app_origin && runtime_dependency != app_dependency);
    CHECK(runtime_origin() == 22 && app_origin() == 11);
    void *(*guest_dlsym)(void *,const char *)=tl_bionic_find("dlsym");
    CHECK(guest_dlsym&&guest_dlsym(runtime,"namespace_origin")==runtime_origin&&guest_dlsym(game,"namespace_origin")==app_origin);
    CHECK(tl_ld_load(system) == runtime && tl_ld_load(app) == game);
    CHECK(tl_ld_load("libcrypto.so") == app_dependency);
    CHECK(tl_ld_unresolved_count() == 0);
    if(getenv("TL_NO_XMEM")){
        Alias a={.symbol=(uintptr_t)tl_ld_sym(game,"namespace_alias")};tl_ld_iterate(alias_offset,&a);CHECK(a.found);
        char path[1200];snprintf(path,sizeof(path),"%s/system-app/libclient.so",argv[1]);int fd=open(path,O_RDONLY);CHECK(fd>=0);
        CHECK(!tl_ld_map_code(fd,a.offset,16384,NULL,NULL)); /* identical source bytes, distinct dependency bindings */
        void *ga=tl_ld_map_code(fd,a.offset,16384,NULL,app_result),*rt=tl_ld_map_code(fd,a.offset,16384,NULL,runtime_result);
        CHECK(ga&&rt&&ga!=rt&&((int (*)(void))ga)()==42&&((int (*)(void))rt)()==42);
        CHECK(!munmap(ga,16384)&&!munmap(rt,16384));close(fd);
        CHECK(app_result()==1111&&runtime_result()==2222);
        puts("PASS signed aliases require the caller's namespace when exact ELF bytes match two imports");
    }
    printf("PASS %s: independent ELF constructors, relocations, dlsym scopes and repeat loads\n",argv[2]);
    return 0;
}
