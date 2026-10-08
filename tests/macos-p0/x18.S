/* SPDX-License-Identifier: GPL-2.0-or-later */
.text
.global fixture_x18_set
.type fixture_x18_set, %function
fixture_x18_set:
    .cfi_startproc
    mov x18, x0
    ret
    .cfi_endproc
.size fixture_x18_set, .-fixture_x18_set
.global fixture_x18_get
.type fixture_x18_get, %function
fixture_x18_get:
    .cfi_startproc
    mov x0, x18
    ret
    .cfi_endproc
.size fixture_x18_get, .-fixture_x18_get

.global fixture_code_adr
.type fixture_code_adr, %function
fixture_code_adr:
    .cfi_startproc
    adr x0, .Lp0_constant
    ret
    .cfi_endproc
.size fixture_code_adr, .-fixture_code_adr
.global fixture_code_adrp
.type fixture_code_adrp, %function
fixture_code_adrp:
    .cfi_startproc
    adrp x0, .Lp0_constant
    add x0, x0, :lo12:.Lp0_constant
    ret
    .cfi_endproc
.size fixture_code_adrp, .-fixture_code_adrp
.global fixture_code_x18
.type fixture_code_x18, %function
fixture_code_x18:
    .cfi_startproc
    adr x18, .Lp0_constant
    mov x0, x18
    ret
    .cfi_endproc
.size fixture_code_x18, .-fixture_code_x18
.Lp0_constant:
    mov w0, #42
    ret
