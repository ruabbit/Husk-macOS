/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Upstream runtime contracts used by native engines. No app, window or audio. */
#include "husk-tl-bionic.h"
#include "husk-tl-dvm.h"
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

void tl_log_line(const char *format, ...) { (void)format; }
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "runtime line %d: %s\n", __LINE__, #x); return 1; } } while (0)

static pthread_t owner;
static void *choreo;
static void (*post64)(void *, void *, void *);
static unsigned callbacks;
static int repeated, wrong;
static int64_t posted, delayed_at;
static int64_t now(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
    return (int64_t)t.tv_sec * 1000000000ll + t.tv_nsec;
}
static void frame(int64_t ns, void *data) {
    uintptr_t flag = (uintptr_t)data;
    if (!pthread_equal(owner, pthread_self()) || ns < posted || ns > now()) wrong = 1;
    if (flag == 4 && ns < delayed_at + 50000000ll) wrong = 1;
    callbacks |= (unsigned)flag;
    if (flag == 2 && ++repeated == 1) post64(choreo, frame, data);
}
static void legacy_frame(long ns, void *data) { frame(ns, data); }
static void *post_from_worker(void *unused) { (void)unused; post64(choreo, frame, (void *)8); return NULL; }

int main(void) {
    tl_jni_init();
    const uint16_t text[] = {'A', 0, 'B', 0xd83c, 0xdf0d};
    jobj *s = tl_dvm_string_u16(text, 5);
    int32_t count = 0;
    const uint16_t *chars = tl_dvm_string_chars(s, &count);
    CHECK(chars && count == 5 && !memcmp(chars, text, sizeof(text)));
    const void **jni = *(const void ***)tl_jni_env();
    int (*length)(void *, jobj *) = (void *)jni[164];
    CHECK(length(tl_jni_env(), s) == 5);
    tl_jni_unref(s);

    float (*nearby)(float) = tl_bionic_find("nearbyintf");
    float (*remainder)(float, float) = tl_bionic_find("remainderf");
    char *(*message)(int, char *, size_t) = tl_bionic_find("__gnu_strerror_r");
    CHECK(nearby && remainder && message);
    CHECK(nearby(1.25f) == 1 && remainder(5.5f, 2) == -0.5f);
    char error[128]; CHECK(message(2, error, sizeof(error)) == error && error[0]);

    void *(*prepare)(int) = tl_bionic_find("ALooper_prepare");
    void *(*get)(void) = tl_bionic_find("AChoreographer_getInstance");
    int (*poll_once)(int, int *, int *, void **) = tl_bionic_find("ALooper_pollOnce");
    void (*post)(void *, void *, void *) = tl_bionic_find("AChoreographer_postFrameCallback");
    void (*delay)(void *, void *, void *, uint32_t) = tl_bionic_find("AChoreographer_postFrameCallbackDelayed64");
    post64 = tl_bionic_find("AChoreographer_postFrameCallback64");
    CHECK(prepare && get && poll_once && post && post64 && delay);
    CHECK(!get()); CHECK(prepare(0)); choreo = get(); CHECK(choreo && get() == choreo);
    owner = pthread_self(); posted = now();
    post(choreo, legacy_frame, (void *)1); post64(choreo, frame, (void *)2);
    delayed_at = now(); delay(choreo, frame, (void *)4, 50);
    pthread_t worker; CHECK(!pthread_create(&worker, NULL, post_from_worker, NULL)); pthread_join(worker, NULL);
    usleep(20000); CHECK(callbacks == 0); /* callbacks belong to the polling thread */
    for (int i = 0; i < 100 && (callbacks != 15 || repeated != 2); i++)
        CHECK(poll_once(20, NULL, NULL, NULL) != -4);
    CHECK(callbacks == 15 && repeated == 2 && !wrong);
    puts("PASS embedded-NUL UTF-16, native imports, looper-owned frame callbacks, delay and repost");
    return 0;
}
