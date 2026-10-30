/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Different implementations of the same soname, like app OpenSSL and runtime
 * BoringSSL. The consumer's constructor must use its own dependency too. */
#ifdef PROVIDER_ID
int namespace_origin(void) { return PROVIDER_ID; }
#else
extern int namespace_origin(void);
static volatile int constructor_origin;
__attribute__((constructor)) static void initialize(void) { constructor_origin = namespace_origin(); }
int namespace_result(void) { return constructor_origin * 100 + namespace_origin(); }
__asm__(".pushsection .text\n.p2align 14\n.global namespace_alias\n.type namespace_alias,%function\n"
        "namespace_alias:\nmov w0,#42\nret\n.size namespace_alias,.-namespace_alias\n.space 16384-8\n.popsection\n");
#endif
