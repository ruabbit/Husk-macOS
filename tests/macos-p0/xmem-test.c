/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-xmem.h"
#include <assert.h>
#include <libkern/OSCacheControl.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

static void *worker(void *unused)
{
    (void)unused;
    for (int i = 0; i < 64; ++i) {
        uint8_t *rx, *rw;
        assert(tl_xmem_alloc(8, &rx, &rw));
        uint32_t code[] = { 0x52800540, 0xd65f03c0 }; /* mov w0,42; ret */
        memcpy(rw, code, sizeof(code)); tl_xmem_flush(rx, sizeof(code));
        assert(((int (*)(void))rx)() == 42);
        assert((intptr_t)rw - (intptr_t)rx == tl_xmem_delta());
    }
    return NULL;
}
int main(int argc, char **argv)
{
    setbuf(stdout, NULL);
    if (argc > 1 && !strcmp(argv[1], "map-jit")) {
        size_t size = (size_t)getpagesize();
        uint32_t *p = mmap(NULL, size, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANON | MAP_JIT, -1, 0);
        if (p == MAP_FAILED) { perror("MAP_JIT"); return 10; }
        pthread_jit_write_protect_np(0);
        p[0] = 0x52800540; p[1] = 0xd65f03c0;
        /* str w0,[x1]; ret: model a guest storing to its adjacent data. */
        p[2] = 0xb9000020; p[3] = 0xd65f03c0;
        sys_icache_invalidate(p, 16);
        pthread_jit_write_protect_np(1);
        assert(((int (*)(void))p)() == 42);
        puts("MAP_JIT constant=42");
        if (argc > 2) {
            puts("MAP_JIT attempting guest store while executable");
            ((void (*)(int, void *))(p + 2))(7, p + 128);
            puts("MAP_JIT guest store succeeded");
        }
        munmap(p, size); return 0;
    }
    char error[256] = {0};
    if (argc > 1 && !strcmp(argv[1], "invalid")) {
        assert(!tl_xmem_open(0, error, sizeof(error)));
        assert(!tl_xmem_open(SIZE_MAX, error, sizeof(error)));
        puts("PASS invalid region size"); return 0;
    }
    if (!tl_xmem_open(8u << 20, error, sizeof(error))) { fprintf(stderr, "%s\n", error); return 11; }
    uint8_t *rx = (void *)1, *rw = (void *)2;
    assert(!tl_xmem_alloc(0, &rx, &rw));
    assert(!tl_xmem_alloc(SIZE_MAX, &rx, &rw));
    assert(rx == (void *)1 && rw == (void *)2 && tl_xmem_used() == 0);
    pthread_t threads[4];
    for (int i = 0; i < 4; ++i) assert(!pthread_create(&threads[i], NULL, worker, NULL));
    for (int i = 0; i < 4; ++i) assert(!pthread_join(threads[i], NULL));
    assert(tl_xmem_used() == 256 * TL_XMEM_PAGE);
    assert(tl_xmem_alloc(tl_xmem_size() - tl_xmem_used(), &rx, &rw));
    assert(!tl_xmem_alloc(1, NULL, NULL));
    printf("PASS dual alias / 256 allocations / 4 threads / exhaustion; page=%d region=%zu\n", getpagesize(), tl_xmem_size());
    return 0;
}
