/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * Drives a NativeActivity game through its NDK entry and lifecycle callbacks.
 * Plain games use their manifest library; Unreal also needs its Java shell.
 *
 * UE4's com.epicgames.ue4.GameActivity extends android.app.NativeActivity: the system loads libUE4.so, calls its ANativeActivity_onCreate with an
 * ANativeActivity (callbacks to fill in, the data directories, the asset manager), and from then on tells it about the activity's life -- start, a window,
 * focus -- through those callbacks, while the engine runs on a thread of its own (android_main) and talks back to Java through GameActivity's methods.
 * Before all that GameActivity.onCreate hands the engine a few facts through native calls. This does the same from C, against the Java world
 * husk-tl-jni-hle.c and husk-tl-jni-ue4.c provide.
 */
#ifndef HUSK_TL_NATIVEACTIVITY_H
#define HUSK_TL_NATIVEACTIVITY_H

#include <stdbool.h>

#include "husk-tl-gameactivity.h"          /* tl_ga_config: the same description of the game and its surface */

#ifdef __cplusplus
extern "C" {
#endif

/* Load the libraries and give the engine what GameActivity.onCreate does. Returns false (with the reason logged) on failure. */
bool tl_na_start(const tl_ga_config *cfg);

/* ANativeActivity_onCreate, then onStart, onResume, the window and focus: the engine takes it from there on its own threads. */
bool tl_na_run(void);

typedef enum {
    TL_NA_UNLOADED, TL_NA_STARTING, TL_NA_RUNNING, TL_NA_PAUSED,
    TL_NA_STOPPING, TL_NA_DESTROYED, TL_NA_FAILED
} tl_na_state;
tl_na_state tl_na_get_state(void);
/* Call from the host lifecycle queue, never the activity thread. Joins after
 * onDestroy returns; FAILED means no storage-close acknowledgement is safe. */
void tl_na_stop(void);
/* Optional android.app.lib_name from the launcher Activity's manifest. */
void tl_na_set_library(const char *name);

unsigned long tl_na_frames(void);
void tl_na_touch(int phase, int id, float x, float y);       /* surface pixels, y down; phase 0 down, 1 move, 2 up, 3 cancel */
void tl_na_set_paused(bool paused);
void tl_na_key(int keycode, bool down);

/* Where a package's OBB goes: tell the file system the OBB `name` is `size` bytes at `offset` in `host_file` (an APK that carries it). */
void tl_vfile_add(const char *guest_name, const char *host_file, unsigned long long offset, unsigned long long size);

#ifdef __cplusplus
}
#endif

#endif
