/* SPDX-License-Identifier: GPL-2.0-or-later */
/* A repository-owned Android arm64 ELF game. All gameplay, drawing and PCM
 * synthesis run inside the guest library, reached through Husk's real loader.
 * This deliberately small host ABI is not an Android engine compatibility claim. */
#include "orbit.h"
extern void glClearColor(float, float, float, float);
extern void glClear(unsigned);
extern void glEnable(unsigned);
extern void glDisable(unsigned);
extern void glScissor(int, int, int, int);

static OrbitSave game;
static int toneLeft, toneHz, phase;
static const float stars[8][2] = {{110,105},{250,85},{390,105},{530,85},{110,300},{250,320},{390,300},{530,320}};
static float absf(float x) { return x < 0 ? -x : x; }
static float clamp(float x, float lo, float hi) { return x < lo ? lo : x > hi ? hi : x; }
static void sound(int hz) { toneLeft = 7200; toneHz = hz; }

int orbit_init(int variant, const OrbitSave *save)
{
    game = (OrbitSave){ORBIT_ABI, (uint32_t)variant, 0, 0, 0, 0, 320, 210};
    if (variant < 0 || variant > 1) return 0;
    if (save) {
        if (save->abi != ORBIT_ABI || save->variant != (uint32_t)variant || save->collected > 255 ||
            !(save->x >= 20 && save->x <= 620 && save->y >= 65 && save->y <= 375) || save->score > 999999) return 0;
        game = *save;
    }
    return 1;
}

void orbit_step(const OrbitInput *input)
{
    if (input->restart) {
        game.collected = 0; game.score = 0; game.x = 320; game.y = 210;
        sound(440);
    }
    if (game.collected == 255) return;
    game.steps++;
    float dx = clamp(input->x, -1, 1), dy = clamp(input->y, -1, 1);
    if (input->pointerDown) {
        dx = clamp((input->pointerX - game.x) / 4.0f, -1, 1);
        dy = clamp((input->pointerY - game.y) / 4.0f, -1, 1);
    }
    game.x = clamp(game.x + dx * 4, 20, 620);
    game.y = clamp(game.y + dy * 4, 65, 375);
    for (int i = 0; i < 8; i++) {
        if (!(game.collected & (1u << i)) && absf(game.x - stars[i][0]) < 18 && absf(game.y - stars[i][1]) < 18) {
            game.collected |= 1u << i; game.score += 100;
            sound(440 + i * 90);
            if (game.collected == 255) { game.wins++; sound(1320); }
        }
    }
    // A moving obstacle crosses the middle lane. Contact costs points and
    // returns the player to the center; collectible progress is preserved.
    float obstacle = 40 + (float)((game.steps * (game.variant + 1)) % 560);
    if (absf(game.x - obstacle) < 16 && absf(game.y - 205) < 12) {
        game.score = game.score >= 25 ? game.score - 25 : 0;
        game.x = 320; game.y = 245; sound(160);
    }
}

static void rect(int x, int y, int w, int h, float r, float g, float b)
{
    glScissor(x, ORBIT_HEIGHT - y - h, w, h); glClearColor(r, g, b, 1); glClear(0x4000);
}
static const uint16_t digits[10] = {31599,11415,29671,29647,23497,31183,31215,29257,31727,31695};
static void number(unsigned value, int x, int y)
{
    unsigned divisor = 10000;
    for (int col = 0; col < 5; col++, divisor /= 10) {
        unsigned digit = (value / divisor) % 10;
        for (int bit = 0; bit < 15; bit++) if (digits[digit] & (1 << (14 - bit)))
            rect(x + col * 16 + bit % 3 * 4, y + bit / 3 * 4, 3, 3, .85f, .92f, 1);
    }
}
void orbit_draw(int paused)
{
    glDisable(0x0c11); glClearColor(.035f, .055f, .09f, 1); glClear(0x4000); glEnable(0x0c11);
    rect(18, 49, 604, 1, .15f, .22f, .3f);
    number(game.score, 20, 18); number(game.wins, 538, 18);
    for (int i = 0; i < 8; i++) {
        float brightness = (game.collected & (1u << i)) ? .17f : .9f;
        int x = (int)stars[i][0], y = (int)stars[i][1];
        rect(x-11,y-11,22,22,brightness,.58f*brightness,.2f*brightness);
        rect(x-7,y-7,14,14,.035f,.055f,.09f);
        if (game.collected & (1u << i)) rect(x-3,y-3,6,6,.2f,.7f,.55f);
    }
    int obstacle = 40 + (int)((game.steps * (game.variant + 1)) % 560);
    rect(obstacle-12,197,24,16,.85f,.22f,.35f);
    int x = (int)game.x, y = (int)game.y;
    rect(x-10,y-10,20,20,game.variant ? .6f : .25f, .8f, .9f);
    rect(x-4,y-4,8,8,.93f,.97f,1);
    if (game.collected == 255) {
        rect(185,163,270,72,.05f,.23f,.2f);
        for (int i=0; i<8; ++i) rect(209+i*29,186,17,24,.4f,.95f,.7f);
    }
    if (paused) { rect(293,170,18,60,.9f,.94f,1); rect(329,170,18,60,.9f,.94f,1); }
    glDisable(0x0c11);
}

void orbit_mix(int16_t *samples, int frames)
{
    for (int i=0; i<frames; i++) {
        int sample = 0;
        if (toneLeft > 0) {
            phase = (phase + toneHz) % 48000;
            sample = (phase < 24000 ? 1 : -1) * toneLeft / 3;
            toneLeft--;
        }
        samples[i*2] = (int16_t)sample; samples[i*2+1] = (int16_t)sample;
    }
}
void orbit_save(OrbitSave *save) { *save = game; }
