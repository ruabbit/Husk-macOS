/* SPDX-License-Identifier: GPL-2.0-or-later */
#pragma once
#include <stdint.h>
#define ORBIT_ABI 1
#define ORBIT_WIDTH 640
#define ORBIT_HEIGHT 400
typedef struct {
    uint32_t abi, variant, collected, score, wins, steps;
    float x, y;
} OrbitSave;
typedef struct {
    float x, y, pointerX, pointerY;
    uint32_t pointerDown, restart;
} OrbitInput;
int orbit_init(int variant, const OrbitSave *save);
void orbit_step(const OrbitInput *input);
void orbit_draw(int paused);
void orbit_mix(int16_t *samples, int frames);
void orbit_save(OrbitSave *save);
