/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-jit-arena.h"

#include <dlfcn.h>
#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>

#if defined(__APPLE__)
#include <TargetConditionals.h>
#include <libkern/OSCacheControl.h>
#include <mach/mach.h>
#include <mach/vm_map.h>
#endif

void tl_log_line(const char *fmt, ...);

/* One bit per 16 KiB page, set = in use. A first-fit scan over at most a few thousand words runs
 * only when an engine allocates or frees, which is rare (a code buffer, a trampoline page, a
 * shader walker), so a bitmap beats a free list here: coalescing is free and it cannot fragment
 * its own bookkeeping. */
static struct {
    uint8_t *rw, *rx;
    size_t size, pages, ceiling_pages;
    size_t used_pages, high_pages, refusals;
    uint64_t *bits;
    size_t *alloc_pages;
    pthread_mutex_t lock;
    volatile int open;
} g_a = { .lock = PTHREAD_MUTEX_INITIALIZER };

static bool page_used(size_t i) { return (g_a.bits[i >> 6] >> (i & 63)) & 1u; }
static void page_set(size_t i, bool on)
{
    if (on) g_a.bits[i >> 6] |= (uint64_t)1 << (i & 63);
    else g_a.bits[i >> 6] &= ~((uint64_t)1 << (i & 63));
}

bool husk_jit_arena_open_region(uint8_t *rw, uint8_t *rx, size_t size, size_t ceiling_bytes)
{
    if (!rw || !rx || size < HUSK_JIT_ARENA_PAGE || ((uintptr_t)rw | (uintptr_t)rx | size) & (HUSK_JIT_ARENA_PAGE - 1)) return false;
    pthread_mutex_lock(&g_a.lock);
    if (g_a.open) { pthread_mutex_unlock(&g_a.lock); return false; }
    size_t pages = size / HUSK_JIT_ARENA_PAGE;
    uint64_t *bits = calloc((pages + 63) / 64, sizeof(uint64_t));
    size_t *alloc_pages = calloc(pages, sizeof(size_t));
    if (!bits || !alloc_pages) { free(bits); free(alloc_pages); pthread_mutex_unlock(&g_a.lock); return false; }
    g_a.rw = rw; g_a.rx = rx; g_a.size = size; g_a.pages = pages; g_a.bits = bits;
    g_a.alloc_pages = alloc_pages;
    g_a.ceiling_pages = ceiling_bytes ? (ceiling_bytes - 1) / HUSK_JIT_ARENA_PAGE + 1 : pages;
    if (g_a.ceiling_pages > pages) g_a.ceiling_pages = pages;
    g_a.used_pages = g_a.high_pages = g_a.refusals = 0;
    __atomic_store_n(&g_a.open, 1, __ATOMIC_RELEASE);
    pthread_mutex_unlock(&g_a.lock);
    tl_log_line("jit-arena: %zu MiB region (rw %p, rx %p, delta %td), ceiling %zu MiB", size >> 20, (void *)rw, (void *)rx,
                (ptrdiff_t)((uintptr_t)rx - (uintptr_t)rw), (g_a.ceiling_pages * HUSK_JIT_ARENA_PAGE) >> 20);
    return true;
}

#if defined(__APPLE__)
typedef struct { uint8_t *rw_addr, *rx_addr; size_t size; } arena_dual_mapping;

#if TARGET_OS_OSX
/* Match the macOS Android runtime's RW allocation and RX alias. The Runner keeps
 * Hardened Runtime with its existing unsigned-executable-memory entitlement;
 * neither view is writable and executable at once. */
static bool open_mac(size_t bytes, uint8_t **rw, uint8_t **rx, char *err, size_t errlen)
{
    void *w = mmap(NULL, bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (w == MAP_FAILED) { snprintf(err, errlen, "mmap(rw, %zu MiB) failed: %s", bytes >> 20, strerror(errno)); return false; }
    vm_address_t x = 0;
    vm_prot_t cur, max;
    kern_return_t kr = vm_remap(mach_task_self(), &x, bytes, 0, VM_FLAGS_ANYWHERE, mach_task_self(), (vm_address_t)w, FALSE, &cur, &max, VM_INHERIT_NONE);
    if (kr == KERN_SUCCESS) {
        kr = vm_protect(mach_task_self(), x, bytes, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
        if (kr != KERN_SUCCESS) vm_deallocate(mach_task_self(), x, bytes);
    }
    if (kr != KERN_SUCCESS) { snprintf(err, errlen, "executable alias failed (%d)", kr); munmap(w, bytes); return false; }
    *rw = w; *rx = (uint8_t *)x;
    return true;
}
#endif
#endif

bool husk_jit_arena_open(size_t region_bytes, size_t ceiling_bytes, char *err, size_t errlen)
{
    if (husk_jit_arena_is_open()) return true;
#if defined(__APPLE__) && !TARGET_OS_OSX
    (void)region_bytes;
    arena_dual_mapping *(*get)(void) = (arena_dual_mapping *(*)(void))dlsym(RTLD_DEFAULT, "husk_ios_jit_get_mapping");
    arena_dual_mapping *m = get ? get() : NULL;
    if (!m || !m->rw_addr || !m->rx_addr || !m->size) {
        snprintf(err, errlen, "no JIT region: Husk was not given one by StikDebug at launch");
        return false;
    }
    if (!husk_jit_arena_open_region(m->rw_addr, m->rx_addr, m->size & ~(HUSK_JIT_ARENA_PAGE - 1), ceiling_bytes)) {
        snprintf(err, errlen, "the JIT region (%p, %zu bytes) is not usable", (void *)m->rx_addr, m->size);
        return false;
    }
    return true;
#elif defined(__APPLE__)
    const char *mib = getenv("TL_XMEM_MIB");
    if (mib) {
        char *end = NULL; errno = 0;
        unsigned long long value = strtoull(mib, &end, 10);
        if (errno || end == mib || *end || *mib == '-' || !value || value > (SIZE_MAX >> 20)) {
            snprintf(err, errlen, "TL_XMEM_MIB must be a positive, representable region size"); return false;
        }
        region_bytes = (size_t)value << 20;
    }
    if (!region_bytes || region_bytes > SIZE_MAX - (HUSK_JIT_ARENA_PAGE - 1)) {
        snprintf(err, errlen, "invalid executable region size"); return false;
    }
    region_bytes = (region_bytes + HUSK_JIT_ARENA_PAGE - 1) & ~(HUSK_JIT_ARENA_PAGE - 1);
    uint8_t *rw, *rx;
    if (!open_mac(region_bytes, &rw, &rx, err, errlen)) return false;
    if (husk_jit_arena_open_region(rw, rx, region_bytes, ceiling_bytes)) return true;
    munmap(rw, region_bytes); munmap(rx, region_bytes);
    snprintf(err, errlen, "could not initialize the JIT arena"); return false;
#else
    (void)region_bytes; (void)ceiling_bytes;
    snprintf(err, errlen, "no JIT arena on this platform");
    return false;
#endif
}

bool husk_jit_arena_is_open(void) { return __atomic_load_n(&g_a.open, __ATOMIC_ACQUIRE) != 0; }

void *husk_jit_arena_alloc(size_t bytes, void **rx_out)
{
    if (rx_out) *rx_out = NULL;
    if (!husk_jit_arena_is_open() || bytes == 0) return NULL;
    size_t want = (bytes - 1) / HUSK_JIT_ARENA_PAGE + 1;
    pthread_mutex_lock(&g_a.lock);
    size_t found = (size_t)-1;
    if (want <= g_a.ceiling_pages - g_a.used_pages) {
        size_t run = 0;
        for (size_t i = 0; i < g_a.pages; i++) {
            /* skip whole used words quickly */
            if (run == 0 && (i & 63) == 0 && g_a.bits[i >> 6] == ~(uint64_t)0) { i += 63; continue; }
            if (page_used(i)) { run = 0; continue; }
            if (++run == want) { found = i + 1 - want; break; }
        }
    }
    if (found == (size_t)-1) {
        g_a.refusals++;
        size_t used = g_a.used_pages;
        pthread_mutex_unlock(&g_a.lock);
        tl_log_line("jit-arena: refused %zu KiB (%zu KiB in use of a %zu KiB ceiling)", (want * HUSK_JIT_ARENA_PAGE) >> 10,
                    (used * HUSK_JIT_ARENA_PAGE) >> 10, (g_a.ceiling_pages * HUSK_JIT_ARENA_PAGE) >> 10);
        return NULL;
    }
    for (size_t i = found; i < found + want; i++) page_set(i, true);
    g_a.alloc_pages[found] = want;
    g_a.used_pages += want;
    if (g_a.used_pages > g_a.high_pages) g_a.high_pages = g_a.used_pages;
    pthread_mutex_unlock(&g_a.lock);
    uint8_t *rw = g_a.rw + found * HUSK_JIT_ARENA_PAGE;
    if (rx_out) *rx_out = g_a.rx + found * HUSK_JIT_ARENA_PAGE;
    return rw;
}

bool husk_jit_arena_free(void *rw, size_t bytes)
{
    if (!husk_jit_arena_is_open() || !rw || bytes == 0) return false;
    uintptr_t off = (uintptr_t)rw - (uintptr_t)g_a.rw;
    size_t n = (bytes - 1) / HUSK_JIT_ARENA_PAGE + 1;
    if ((uintptr_t)rw < (uintptr_t)g_a.rw || off >= g_a.size || off % HUSK_JIT_ARENA_PAGE || n > g_a.pages - off / HUSK_JIT_ARENA_PAGE) return false;
    size_t first = off / HUSK_JIT_ARENA_PAGE;
    pthread_mutex_lock(&g_a.lock);
    if (g_a.alloc_pages[first] != n) { pthread_mutex_unlock(&g_a.lock); return false; }
    for (size_t i = first; i < first + n; i++) {
        if (!page_used(i)) {
            pthread_mutex_unlock(&g_a.lock);
            tl_log_line("jit-arena: free of %p (+%zu KiB) covers a page that is not in use; ignored", rw, (n * HUSK_JIT_ARENA_PAGE) >> 10);
            return false;
        }
    }
    /* Zero (UDF #0) before the pages can be handed out again, and drop stale instructions. */
    memset(rw, 0, n * HUSK_JIT_ARENA_PAGE);
#if defined(__APPLE__)
    sys_icache_invalidate(g_a.rx + first * HUSK_JIT_ARENA_PAGE, n * HUSK_JIT_ARENA_PAGE);
#else
    __builtin___clear_cache((char *)g_a.rx + first * HUSK_JIT_ARENA_PAGE, (char *)g_a.rx + (first + n) * HUSK_JIT_ARENA_PAGE);
#endif
    for (size_t i = first; i < first + n; i++) page_set(i, false);
    g_a.alloc_pages[first] = 0;
    g_a.used_pages -= n;
    pthread_mutex_unlock(&g_a.lock);
    return true;
}

intptr_t husk_jit_arena_delta(void) { return (intptr_t)((uintptr_t)g_a.rx - (uintptr_t)g_a.rw); }

void *husk_jit_arena_rx_of(const void *rw)
{
    uintptr_t p = (uintptr_t)rw, b = (uintptr_t)g_a.rw;
    return husk_jit_arena_is_open() && p >= b && p - b < g_a.size ? (void *)(g_a.rx + (p - b)) : NULL;
}

void *husk_jit_arena_rw_of(const void *rx)
{
    uintptr_t p = (uintptr_t)rx, b = (uintptr_t)g_a.rx;
    return husk_jit_arena_is_open() && p >= b && p - b < g_a.size ? (void *)(g_a.rw + (p - b)) : NULL;
}

uint8_t *husk_jit_arena_rw_base(void) { return g_a.rw; }
size_t husk_jit_arena_held_bytes(void) { return g_a.size; }
size_t husk_jit_arena_ceiling_bytes(void) { return g_a.ceiling_pages * HUSK_JIT_ARENA_PAGE; }
size_t husk_jit_arena_used_bytes(void) { pthread_mutex_lock(&g_a.lock); size_t n = g_a.used_pages * HUSK_JIT_ARENA_PAGE; pthread_mutex_unlock(&g_a.lock); return n; }
size_t husk_jit_arena_high_water_bytes(void) { pthread_mutex_lock(&g_a.lock); size_t n = g_a.high_pages * HUSK_JIT_ARENA_PAGE; pthread_mutex_unlock(&g_a.lock); return n; }
size_t husk_jit_arena_refusals(void) { pthread_mutex_lock(&g_a.lock); size_t n = g_a.refusals; pthread_mutex_unlock(&g_a.lock); return n; }
