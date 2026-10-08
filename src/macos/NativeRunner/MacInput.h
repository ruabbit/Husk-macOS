/* SPDX-License-Identifier: GPL-2.0-or-later */
#pragma once
#include "orbit.h"
#include <stdbool.h>
typedef struct {
    bool keys[128];
    float padX, padY;
    OrbitInput value;
} MacInput;
void mac_input_clear(MacInput *input);
void mac_input_key(MacInput *input, unsigned code, bool down);
void mac_input_pointer(MacInput *input, float x, float y, float width, float height, bool down);
void mac_input_controller(MacInput *input, float x, float y, bool restart);
OrbitInput mac_input_frame(MacInput *input);
