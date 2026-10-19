/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Android ELF with Go's data marker and real PC-relative/relocated pointers. */
.section .rodata
#ifdef GO_DATA
.ascii "\377 Go buildinf:"
#endif
.p2align 3
.global view_value
.protected view_value
view_value: .xword 0x123456789abcdef
.data
.p2align 3
.global view_pointer
.hidden view_pointer
view_pointer: .xword view_value
.global code_pointer
.hidden code_pointer
code_pointer: .xword view_address
.text
.p2align 2
.global view_address
.hidden view_address
.type view_address,%function
view_address:
    adrp x0, view_value
    add x0, x0, :lo12:view_value
    ret
.size view_address,.-view_address
.global view_relocation
.type view_relocation,%function
view_relocation:
    adrp x1, view_pointer
    ldr x0, [x1, :lo12:view_pointer]
    ret
.size view_relocation,.-view_relocation
.global code_relocation
.type code_relocation,%function
code_relocation:
    adrp x1, code_pointer
    ldr x0, [x1, :lo12:code_pointer]
    ret
.size code_relocation,.-code_relocation
.global view_export
.type view_export,%function
view_export:
    b view_address
.size view_export,.-view_export
.global raw_syscall_registers
.type raw_syscall_registers,%function
raw_syscall_registers:
    stp q8, q9, [sp, #-128]!
    stp q10, q11, [sp, #32]
    stp q12, q13, [sp, #64]
    stp q14, q15, [sp, #96]
    mov x14, x0
    movi v8.16b, #8
    movi v9.16b, #9
    movi v10.16b, #10
    movi v11.16b, #11
    movi v12.16b, #12
    movi v13.16b, #13
    movi v14.16b, #14
    movi v15.16b, #15
    mov x10, #0xa0000000
    msr nzcv, x10
    mov x8, #172 /* Linux getpid, with no file or process side effects. */
    svc #0
    mrs x11, nzcv
    cmp x11, x10
    b.ne 1f
    cmp x0, x14
    b.ne 1f
.macro check_vector n
    movi v0.16b, #\n
    cmeq v0.16b, v\n\().16b, v0.16b
    uminv b0, v0.16b
    fmov w1, s0
    and w1, w1, #255
    cmp w1, #255
    b.ne 1f
.endm
    check_vector 8
    check_vector 9
    check_vector 10
    check_vector 11
    check_vector 12
    check_vector 13
    check_vector 14
    check_vector 15
    mov x0, #1
    b 2f
1:  mov x0, #0
2:  ldp q10, q11, [sp, #32]
    ldp q12, q13, [sp, #64]
    ldp q14, q15, [sp, #96]
    ldp q8, q9, [sp], #128
    ret
.size raw_syscall_registers,.-raw_syscall_registers
#ifdef MONO_DATA
.hidden mono_code_end
mono_code_end:
.global mono_data_word
.type mono_data_word,%object
mono_data_word: .word 0xd4000001 /* metadata that looks like a syscall, never executable */
.size mono_data_word,.-mono_data_word
.data
.p2align 3
.global mono_aot_file_info
.type mono_aot_file_info,%object
mono_aot_file_info:
    .zero 6*8
    .xword view_address,mono_code_end
    .zero 30*8
.size mono_aot_file_info,.-mono_aot_file_info
#endif
