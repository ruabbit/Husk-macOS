/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Freestanding ELF: no Android SDK headers or third-party APKs. */
extern int p0_import(int);
int fixture_global = 7;
int fixture_bss;
int *fixture_pointer = &fixture_global;
static int local_value = 3;
static int *volatile local_pointers[48] = { [0 ... 47] = &local_value };
static volatile int constructed;
__attribute__((constructor)) static void construct(void) { constructed = 11; }
int fixture_check(void)
{
    if (fixture_global != 7 || fixture_bss || *fixture_pointer != 7) return -1;
    for (int i = 0; i < 48; ++i) if (*local_pointers[i] != 3) return -2;
    fixture_global = 9;
    fixture_bss = 5;
    local_value = 4;
    return *fixture_pointer + fixture_bss + *local_pointers[47] + p0_import(6);
}
int fixture_constructor(void) { return constructed; }
int fixture_tick(void) { return __atomic_add_fetch(&fixture_bss, 1, __ATOMIC_RELAXED); }
#ifdef P0_TLS
__thread int fixture_tls_value = 19;
int fixture_tls(void) { return ++fixture_tls_value; }
#endif
