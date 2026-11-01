/* SPDX-License-Identifier: GPL-2.0-or-later */
.syntax unified
.arm
.text
.global a32_ctor
.type a32_ctor,%function
a32_ctor:
    ldr r0, 1f
    mov r1, #37
    str r1, [r0]
    bx lr
1: .word state
.global a32_value
.type a32_value,%function
a32_value:
    ldr r0, 2f
    ldr r0, [r0]
    bx lr
2: .word state
.global JNI_OnLoad
.type JNI_OnLoad,%function
JNI_OnLoad:
    ldr r0, 3f
    bx lr
3: .word 0x00010006
.global a32_loop
.type a32_loop,%function
a32_loop:
    b a32_loop
.thumb
.thumb_func
.global a32_add
.type a32_add,%function
a32_add:
    adds r0, r0, r1
    bx lr
.data
.align 2
state: .word 0
