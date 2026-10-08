/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-ld.h"
#include "husk-tl-xmem.h"
#include <assert.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>

static int (*tls_next)(void), (*tick)(void);
static void (*set_x18)(uint64_t);
static uint64_t (*get_x18)(void);
static void *worker(void *arg)
{
    uint64_t id = (uintptr_t)arg;
    assert(tls_next() == 20);
    for (int i = 0; i < 1000; ++i) {
        set_x18(id);
        sched_yield();
        assert(get_x18() == id);
        assert(tl_vx18_get() == id);
        tick();
        assert(tls_next() == 21 + i);
    }
    return NULL;
}
int main(int argc, char **argv)
{
    assert(argc == 3);
    assert(tl_ld_add_apk(argv[1]));
    if (!strcmp(argv[2], "exhaust")) {
        char error[256];
        assert(tl_xmem_open(4 * TL_XMEM_PAGE, error, sizeof(error)));
        tl_lib *small = tl_ld_load("libclassic4.so");
        assert(small);
        size_t used = tl_xmem_used();
        assert(!tl_ld_load("libclassic16.so") && tl_xmem_used() == used);
        int (*increment)(void) = tl_ld_sym(small, "fixture_tick");
        assert(increment && increment() == 1);
        puts("PASS loader exhaustion leaves existing code/data intact"); return 0;
    }
    tl_lib *lib = tl_ld_load(argv[2]);
    if (strstr(argv[2], "initial-exec")) {
        assert(!lib); puts("PASS unsupported initial-exec TLS refused"); return 0;
    }
    assert(lib && tl_ld_unresolved_count() == 0);
    int (*check)(void) = tl_ld_sym(lib, "fixture_check");
    int (*ctor)(void) = tl_ld_sym(lib, "fixture_constructor");
    assert(check && ctor && tl_xmem_is_rx(check));
    assert(ctor() == 0);
    assert(tl_ld_init(lib) && ctor() == 11);
    assert(tl_ld_init(lib) && ctor() == 11);
    assert(check() == 30);
    const char *address_functions[] = { "fixture_code_adr", "fixture_code_adrp", "fixture_code_x18" };
    for (int i = 0; i < 3; ++i) {
        void *(*address)(void) = tl_ld_sym(lib, address_functions[i]);
        assert(address);
        int (*code)(void) = address();
        assert(tl_xmem_is_rx(code) && code() == 42);
    }
    int *global = tl_ld_sym(lib, "fixture_global");
    assert(global && !tl_xmem_is_rx(global) && *global == 9);
    *global = 23; assert(*global == 23);
    tls_next = tl_ld_sym(lib, "fixture_tls");
    tick = tl_ld_sym(lib, "fixture_tick");
    set_x18 = tl_ld_sym(lib, "fixture_x18_set");
    get_x18 = tl_ld_sym(lib, "fixture_x18_get");
    assert(tls_next && tick && set_x18 && get_x18);
    assert(tls_next() == 20);
    set_x18(999);
    pthread_t threads[4];
    for (uintptr_t i = 0; i < 4; ++i) assert(!pthread_create(&threads[i], NULL, worker, (void *)(i + 1)));
    for (int i = 0; i < 4; ++i) assert(!pthread_join(threads[i], NULL));
    assert(get_x18() == 999 && tls_next() == 21);
    assert(*(int *)tl_ld_sym(lib, "fixture_bss") == 4005);
    printf("PASS ELF globals/relocations/constructor/TLS/x18/4 threads: %s used=%zu\n", argv[2], tl_xmem_used());
    return 0;
}
