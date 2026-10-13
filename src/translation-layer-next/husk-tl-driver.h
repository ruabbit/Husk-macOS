/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef HUSK_TL_DRIVER_H
#define HUSK_TL_DRIVER_H
#include <stdbool.h>
#include <stdatomic.h>
/* Host-visible acknowledgements. RUNNING/PAUSED follow the native callback;
 * DESTROYED follows the callback, render-thread join and worker quiescence. */
typedef enum {
    TL_DRIVER_IDLE, TL_DRIVER_STARTING, TL_DRIVER_RUNNING, TL_DRIVER_PAUSED,
    TL_DRIVER_STOPPING, TL_DRIVER_DESTROYED, TL_DRIVER_FAILED
} tl_driver_state;
/* Failure is sticky until the next explicit start. Two SDL threads can report
 * concurrently; a successful callback must never erase a worker failure. */
static inline void tl_driver_transition(atomic_int *state, tl_driver_state next) {
    int previous = atomic_load(state);
    while (previous != TL_DRIVER_FAILED &&
           !atomic_compare_exchange_weak(state, &previous, next)) {}
}
tl_driver_state tl_cocos_state(void);
tl_driver_state tl_godot_state(void);
tl_driver_state tl_gm_state(void);
tl_driver_state tl_sdl_state(void);
tl_driver_state tl_gta_state(void);
void tl_gm_stop(void);
void tl_sdl_stop(void);
void tl_gta_stop(void);
void tl_gta_key(int key, bool down);
#endif
