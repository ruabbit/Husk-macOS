/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-ld.h"
#include "husk-tl-bionic.h"
#include <stdio.h>
#include <string.h>

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
    printf("PASS %s: independent ELF constructors, relocations, dlsym scopes and repeat loads\n",argv[2]);
    return 0;
}
