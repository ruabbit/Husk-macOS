// SPDX-License-Identifier: GPL-2.0-or-later
#include <FEXCore/Utils/AllocatorHooks.h>
#include "husk-jit-arena.h"
#include <libkern/OSCacheControl.h>
#include <cstdio>
#include <cstring>
#include <cstdint>
extern "C" void tl_log_line(const char *, ...) {}
#define CHECK(x) do { if (!(x)) { std::fprintf(stderr,"FAIL FEX host line %d: %s\n",__LINE__,#x); return 1; } } while (0)
static int release(void *rw,size_t size) { return husk_jit_arena_free(rw,size)?1:0; }
static bool corrupt;
static int allocations;
static void *allocate(size_t size,void **rx) {
    ++allocations;
    void *rw=husk_jit_arena_alloc(size,rx);
    if(rw && corrupt)*rx=static_cast<char*>(*rx)+1;
    return rw;
}
int main(int argc,char **argv) {
    using namespace FEXCore::Allocator;
    CHECK(argc==2);
    CHECK(iOSJITAlloc(16384)==nullptr); // No implicit private JIT allocation.
    char error[512]{};
    CHECK(husk_jit_arena_open(8*16384,4*16384,error,sizeof(error)));
    JITHostHooks host{allocate,release,husk_jit_arena_delta(),reinterpret_cast<uintptr_t>(husk_jit_arena_rw_base()),husk_jit_arena_held_bytes()};
    if(!std::strcmp(argv[1],"invalid")) {
        auto invalid=host;invalid.Size=SIZE_MAX;
        SetJITHostHooks(invalid);SetJITHostHooks(host);
        CHECK(iOSJITAlloc(16384)==nullptr && allocations==0);
        std::puts("PASS invalid FEX host stays rejected; no fallback or rebinding");return 0;
    }
    SetJITHostHooks(host);
    corrupt=true;CHECK(iOSJITAlloc(16384)==nullptr);corrupt=false;
    auto *rw=static_cast<uint32_t*>(iOSJITAlloc(16384));CHECK(rw);
    auto *rx=static_cast<uint32_t*>(GetExecutableAddress(rw));CHECK(rx && rx!=rw && GetWritableAddress(rx+1)==rw+1);
    rw[0]=0x52800540;rw[1]=0xd65f03c0; // mov w0,#42; ret
    sys_dcache_flush(rw,8);sys_icache_invalidate(rx,8);
    CHECK(reinterpret_cast<int(*)()>(rx)()==42);
    CHECK(iOSJITAlloc(4*16384)==nullptr); // Host's ceiling, not only its reservation size.
    CHECK(iOSJITFreeIfOwned(rw,16384));
    CHECK(iOSJITFreeIfOwned(rw,16384)); // Rejected release must not munmap the host arena.
    auto *again=iOSJITAlloc(4*16384);CHECK(again);
    CHECK(iOSJITFreeIfOwned(again,4*16384));
    std::puts("PASS actual FEX allocator uses Husk RW/RX arena, executes code, honors ceiling, rejects invalid mappings and preserves ownership");
    return 0;
}
