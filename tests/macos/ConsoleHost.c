/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-console-host.h"
#include "husk-jit-arena.h"
#include "husk-tl-gamepad.h"
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static bool android_loaded;
const char *husk_native_loaded_apk(void) { return android_loaded ? "android-fixture" : NULL; }
void tl_log_line(const char *fmt, ...) { (void)fmt; }
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL console line %d: %s\n", __LINE__, #c); return 1; } } while (0)
static void (*snapshot)(HuskPadV1 *);
static int (*pad_calls)(void);
static bool wait_pad(uint32_t buttons, int lx, int ly, int l2) {
    for (int i = 0; i < 1000; i++) {
        HuskPadV1 p; snapshot(&p);
        if (p.buttons == buttons && p.left_x == lx && p.left_y == ly && p.l2 == l2) return true;
        usleep(1000);
    }
    return false;
}
int main(int argc, char **argv) {
    if (argc != 3) return 64;
    setenv("HUSK_CONSOLE_FIXTURE_MODE", argv[2], 1);
    char error[512] = "";
    husk_console_launch_args a = {.module_path=argv[1], .game_id="ps4:fixture", .game="fixture", .user_dir="unused",
        .metal_layer=&a, .width_px=1280, .height_px=720, .scale=1, .region_bytes=8u<<20};
    CHECK(!husk_console_join());
    android_loaded = true;
    CHECK(!husk_console_launch(&a, error, sizeof(error)) && !husk_jit_arena_is_open());
    android_loaded = false;
    if (!strcmp(argv[2], "missing-callback") || !strcmp(argv[2], "wrong-abi")) {
        CHECK(!husk_console_launch(&a, error, sizeof(error)) && !husk_jit_arena_is_open());
        printf("PASS invalid console ABI refused before JIT initialization: %s\n", error); return 0;
    }
    CHECK(husk_console_launch(&a, error, sizeof(error)));
    CHECK(!strcmp(husk_console_loaded_game(), "ps4:fixture"));
    CHECK(!husk_console_launch(&a, error, sizeof(error)));
    void *lib = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    CHECK(lib); snapshot = dlsym(lib, "console_fixture_pad"); pad_calls = dlsym(lib, "console_fixture_pad_calls");
    CHECK(snapshot && pad_calls);
    CHECK(husk_console_frames() == 0 && !husk_console_join());
    CHECK(!tl_pad_read(0, NULL));
    tl_pad_state sample = {.buttons=0xfeed};
    CHECK(!tl_pad_read(-1, &sample) && sample.buttons == 0xfeed);
    CHECK(!tl_pad_read(TL_PADS, &sample));
    tl_pad_connect(0, "fixture one"); tl_pad_connect(1, "fixture two");
    tl_pad_state first = {.buttons=1u<<TL_PAD_A, .lx=.5f, .ly=-.5f, .lt=.8f};
    tl_pad_state second = {.buttons=1u<<TL_PAD_B, .lx=-1, .ly=.2f};
    tl_pad_update(0, &first); tl_pad_update(1, &second);
    CHECK(tl_pad_read(0, &sample) && sample.buttons == first.buttons && sample.lx == .5f);
    CHECK(wait_pad(0x6100, 0, 64, 204));
    husk_console_set_paused(true);
    CHECK(husk_console_state() == HUSK_CONSOLE_PAUSED && wait_pad(0,128,128,0));
    int calls = pad_calls();
    first.buttons = 1u<<TL_PAD_X; tl_pad_update(0,&first);
    usleep(25000); CHECK(pad_calls() == calls);
    husk_console_set_paused(false);
    CHECK(wait_pad(0xa100,0,64,204));
    /* No pump tick between pause and resume: the held state must still be resent. */
    husk_console_set_paused(true); husk_console_set_paused(false);
    CHECK(wait_pad(0xa100,0,64,204));
    tl_pad_disconnect(1); CHECK(wait_pad(0x8100,191,64,204));
    tl_pad_disconnect(0); CHECK(wait_pad(0,128,128,0));
    husk_console_stop();
    if (!strcmp(argv[2], "stop-pending")) {
        CHECK(husk_console_state() != HUSK_CONSOLE_STOPPED && !husk_console_join());
        puts("PASS stop request alone cannot acknowledge a stopped console module"); return 0;
    }
    CHECK(husk_console_state() == HUSK_CONSOLE_STOPPED && husk_console_join() && husk_console_join());
    CHECK(husk_jit_arena_used_bytes() == 0);
    calls = pad_calls(); husk_console_set_pad(&(HuskPadV1){.buttons=0xffff});
    usleep(25000); CHECK(pad_calls() == calls);
    puts("PASS console ABI, Hardened Runtime JIT, merged pads, pause/resume, disconnect and host thread reap; no game/storage claim");
    return 0;
}
