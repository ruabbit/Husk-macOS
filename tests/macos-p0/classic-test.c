/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Exercise the actual classic ELF core, without DEX/Android UI emulation. */
#include "../../src/translation-layer/husk-tl-load.c"
#include <assert.h>
static int p0_import(int value) { return value * 2; }
void *tl_shim_find(const char *name)
{ return !strcmp(name, "p0_import") ? (void *)p0_import : NULL; }
bool tl_shim_supplies(const char *name) { (void)name; return false; }
int main(int argc, char **argv)
{
    assert(argc == 2);
    FILE *f = fopen(argv[1], "rb"); assert(f);
    fseek(f, 0, SEEK_END); long n = ftell(f); rewind(f);
    uint8_t *bytes = malloc((size_t)n); assert(bytes);
    assert(fread(bytes, 1, (size_t)n, f) == (size_t)n); fclose(f);
    bool loaded = load_library("libfixture.so", bytes, (size_t)n);
    char *log = husk_tl_attempt_log(); fputs(log, stdout); free(log); fflush(stdout);
    if (strstr(argv[1], "tls")) {
        assert(!loaded); puts("PASS classic TLS explicitly refused"); free(bytes); return 0;
    }
    if (!loaded) { free(bytes); return 20; }
    int (*check)(void) = (void *)lib_lookup(&g_run.libs[0], "fixture_check");
    assert(check);
    jit_writable(false);
    assert(check() == 30);
    puts("PASS classic globals/relocations");
    /* Deliberately probe the second MAP_JIT allocation in this process. */
    bool second = load_library("libsecond.so", bytes, (size_t)n);
    log = husk_tl_attempt_log(); fputs(log, stdout); free(log);
    printf("classic second_library=%d\n", second);
    free(bytes); return 0;
}
