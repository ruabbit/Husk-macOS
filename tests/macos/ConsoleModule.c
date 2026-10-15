/* SPDX-License-Identifier: GPL-2.0-or-later */
/* ABI fixture only: no PS4 core, game, graphics or audio. */
#include "husk-console-abi.h"
#include <libkern/OSCacheControl.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

static HuskHostV1 host;
static atomic_int state, pad_calls;
static HuskPadV1 pad;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static void *code;
static int init(const HuskHostV1 *h, const char *dir) {
    if (!h || h->version != 1 || h->struct_size != sizeof(*h) || !dir) return -1;
    host = *h;
    void *rx = NULL;
    code = host.jit_alloc(16384, &rx);
    if (!code || !rx || (uintptr_t)rx != (uintptr_t)code + host.jit_delta) return -1;
    const uint32_t instructions[] = {0x52800540, 0xd65f03c0}; /* return 42 */
    memcpy(code, instructions, sizeof(instructions)); sys_icache_invalidate(rx, sizeof(instructions));
    return ((int (*)(void))rx)() == 42 ? 0 : -1;
}
static int launch(const char *game, const char *args, void *layer, int w, int h, float scale) {
    (void)args;
    if (!game || !layer || w <= 0 || h <= 0 || scale <= 0) return -1;
    atomic_store(&state, HUSK_CONSOLE_RUNNING); return 0;
}
static int get_state(void) { return atomic_load(&state); }
static uint64_t frames(void) { return 0; }
static void pause_game(int pause) { atomic_store(&state, pause ? HUSK_CONSOLE_PAUSED : HUSK_CONSOLE_RUNNING); }
static void set_pad(const HuskPadV1 *value) {
    pthread_mutex_lock(&lock); pad = *value; atomic_fetch_add(&pad_calls, 1); pthread_mutex_unlock(&lock);
}
static void resize(int w, int h) { (void)w; (void)h; }
static void stop(void) {
    const char *mode = getenv("HUSK_CONSOLE_FIXTURE_MODE");
    if (mode && !strcmp(mode, "stop-pending")) return;
    if (code && !host.jit_free(code, 16384)) { atomic_store(&state, HUSK_CONSOLE_FAILED); return; }
    code = NULL; atomic_store(&state, HUSK_CONSOLE_STOPPED);
}
static int restart(char *path, int n, char *args, int m) { (void)path; (void)n; (void)args; (void)m; return 0; }

void console_fixture_pad(HuskPadV1 *out) { pthread_mutex_lock(&lock); *out = pad; pthread_mutex_unlock(&lock); }
int console_fixture_pad_calls(void) { return atomic_load(&pad_calls); }
const HuskConsoleModuleV1 *husk_console_module_v1(void) {
    static HuskConsoleModuleV1 module;
    module = (HuskConsoleModuleV1){sizeof(module), 1, "ps4", 4u << 20, init, launch, get_state, frames, pause_game, set_pad, resize, stop, restart};
    const char *mode = getenv("HUSK_CONSOLE_FIXTURE_MODE");
    if (mode && !strcmp(mode, "missing-callback")) module.stop = NULL;
    if (mode && !strcmp(mode, "wrong-abi")) module.version = 2;
    return &module;
}
