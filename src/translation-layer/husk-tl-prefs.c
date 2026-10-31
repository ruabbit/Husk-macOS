/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-prefs.h"

#include <stdio.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <ctype.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>

typedef enum { K_INT, K_LONG, K_FLOAT, K_BOOL, K_STRING } kind_t;

typedef struct {
    char *key;
    kind_t kind;
    union { int32_t i; int64_t j; float f; bool z; char *s; } v;
} entry_t;

struct tl_prefs {
    entry_t *items;
    int count, cap;
    char *path;
    bool allocation_failed;
};

/* ------------------------------------------------------------------ store */

static entry_t *find(const tl_prefs *p, const char *key)
{
    if (!p || !key) return NULL;
    for (int i = 0; i < p->count; i++) {
        if (!strcmp(p->items[i].key, key)) return &p->items[i];
    }
    return NULL;
}

static void free_value(entry_t *e)
{
    if (e->kind == K_STRING) free(e->v.s);
    e->v.s = NULL;
}

/* The slot for `key`, made if needed, with any previous value released. */
static entry_t *slot(tl_prefs *p, const char *key, kind_t kind)
{
    if (!p || !key) return NULL;
    entry_t *e = find(p, key);
    if (e) {
        free_value(e);
    } else {
        if (p->count == p->cap) {
            int cap = p->cap ? p->cap * 2 : 32;
            entry_t *grown = realloc(p->items, (size_t)cap * sizeof(*grown));
            if (!grown) { p->allocation_failed = true; return NULL; }
            p->items = grown;
            p->cap = cap;
        }
        e = &p->items[p->count];
        memset(e, 0, sizeof(*e));
        e->key = strdup(key);
        if (!e->key) { p->allocation_failed = true; return NULL; }
        p->count++;
    }
    e->kind = kind;
    return e;
}

tl_prefs *tl_prefs_create(void) { return calloc(1, sizeof(tl_prefs)); }

void tl_prefs_destroy(tl_prefs *p)
{
    if (!p) return;
    tl_prefs_clear(p);
    free(p->items);
    free(p->path);
    free(p);
}

void tl_prefs_clear(tl_prefs *p)
{
    if (!p) return;
    for (int i = 0; i < p->count; i++) {
        free_value(&p->items[i]);
        free(p->items[i].key);
    }
    p->count = 0;
}

int tl_prefs_count(const tl_prefs *p) { return p ? p->count : 0; }

const char *tl_prefs_key(const tl_prefs *p, int index)
{ return p && index >= 0 && index < p->count ? p->items[index].key : NULL; }
char tl_prefs_type(const tl_prefs *p, const char *key)
{ const entry_t *e = find(p, key); return e ? "IJFZS"[e->kind] : 0; }

void tl_prefs_remove(tl_prefs *p, const char *key)
{
    entry_t *e = find(p, key);
    if (!e) return;
    free_value(e);
    free(e->key);
    *e = p->items[--p->count];
}

/* ----------------------------------------------------------------- access */

bool tl_prefs_contains(const tl_prefs *p, const char *key) { return find(p, key) != NULL; }

#define GETTER(name, ctype, kindval, field) \
    ctype name(const tl_prefs *p, const char *key, ctype def) \
    { const entry_t *e = find(p, key); return (e && e->kind == (kindval)) ? e->v.field : def; }
GETTER(tl_prefs_get_int,   int32_t, K_INT,   i)
GETTER(tl_prefs_get_long,  int64_t, K_LONG,  j)
GETTER(tl_prefs_get_float, float,   K_FLOAT, f)
GETTER(tl_prefs_get_bool,  bool,    K_BOOL,  z)

const char *tl_prefs_get_string(const tl_prefs *p, const char *key, const char *def)
{
    const entry_t *e = find(p, key);
    return (e && e->kind == K_STRING) ? e->v.s : def;
}

void tl_prefs_put_int(tl_prefs *p, const char *key, int32_t v)
{ entry_t *e = slot(p, key, K_INT); if (e) e->v.i = v; }
void tl_prefs_put_long(tl_prefs *p, const char *key, int64_t v)
{ entry_t *e = slot(p, key, K_LONG); if (e) e->v.j = v; }
void tl_prefs_put_float(tl_prefs *p, const char *key, float v)
{ entry_t *e = slot(p, key, K_FLOAT); if (e) e->v.f = v; }
void tl_prefs_put_bool(tl_prefs *p, const char *key, bool v)
{ entry_t *e = slot(p, key, K_BOOL); if (e) e->v.z = v; }

void tl_prefs_put_string(tl_prefs *p, const char *key, const char *v)
{
    if (!v) { tl_prefs_remove(p, key); return; }
    char *copy = strdup(v);
    if (!copy) { if (p) p->allocation_failed = true; return; }
    entry_t *e = slot(p, key, K_STRING);
    if (e) e->v.s = copy; else free(copy);
}

/* ------------------------------------------------------------ persistence */

/* Tab and newline delimit the file, so they -- and the backslash that escapes
 * them -- are written escaped, and a value can hold any of them. */
static void put_escaped(FILE *f, const char *s)
{
    for (; *s; s++) {
        switch (*s) {
            case '\\': fputs("\\\\", f); break;
            case '\t': fputs("\\t", f);  break;
            case '\n': fputs("\\n", f);  break;
            case '\r': fputs("\\r", f);  break;
            default:   fputc(*s, f);
        }
    }
}

static char *unescape(const char *s)
{
    char *out = malloc(strlen(s) + 1), *w = out;
    if (!out) return NULL;
    for (; *s; s++) {
        if (*s == '\\') {
            s++;
            if (!*s || !strchr("tnr\\", *s)) { free(out); return NULL; }
            *w++ = (*s == 't') ? '\t' : (*s == 'n') ? '\n' : (*s == 'r') ? '\r' : *s;
        } else {
            *w++ = *s;
        }
    }
    *w = 0;
    return out;
}

bool tl_prefs_save(const tl_prefs *p)
{
    if (p && p->allocation_failed) return false;
    if (!p || !p->path) return true;

    /* Written beside the real file and renamed over it, so a crash or a power
     * cut mid-write leaves the previous settings, not a half-file. */
    size_t n = strlen(p->path) + 12;
    char *tmp = malloc(n);
    if (!tmp) return false;
    snprintf(tmp, n, "%s.XXXXXX", p->path);
    int fd = mkstemp(tmp);
    if (fd < 0) { free(tmp); return false; }
    FILE *f = fdopen(fd, "w");
    if (!f) { close(fd); unlink(tmp); free(tmp); return false; }

    fputs("husk-prefs 1\n", f);
    for (int i = 0; i < p->count; i++) {
        const entry_t *e = &p->items[i];
        static const char tag[] = { 'I', 'J', 'F', 'Z', 'S' };
        fputc(tag[e->kind], f);
        fputc('\t', f);
        put_escaped(f, e->key);
        fputc('\t', f);
        switch (e->kind) {
            case K_INT:    fprintf(f, "%d", e->v.i); break;
            case K_LONG:   fprintf(f, "%lld", (long long)e->v.j); break;
            case K_FLOAT:  { uint32_t bits; memcpy(&bits, &e->v.f, 4); fprintf(f, "%08x", bits); break; }
            case K_BOOL:   fputs(e->v.z ? "1" : "0", f); break;
            case K_STRING: put_escaped(f, e->v.s ? e->v.s : ""); break;
        }
        fputc('\n', f);
    }
    bool ok = fflush(f) == 0 && ferror(f) == 0 && fsync(fd) == 0;
    ok = (fclose(f) == 0) && ok;
    if (ok) ok = rename(tmp, p->path) == 0;
    if (!ok) remove(tmp);
    free(tmp);
    return ok;
}

bool tl_prefs_attach(tl_prefs *p, const char *path)
{
    if (!p) return false;
    free(p->path);
    p->path = path ? strdup(path) : NULL;
    if (!path) return true;

    if (!p->path) return false;
    int fd = open(path, O_RDONLY | O_NOFOLLOW);
    if (fd < 0) return errno == ENOENT;
    struct stat st;
    if (fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_uid != getuid() || st.st_size > 8 * 1024 * 1024) {
        close(fd); return false;
    }
    FILE *f = fdopen(fd, "r");
    if (!f) { close(fd); return false; }

    char *line = NULL;
    size_t cap = 0;
    ssize_t len;
    bool first = true, ok = true;
    tl_prefs *seen = tl_prefs_create();
    if (!seen) { fclose(f); return false; }
    while ((len = getline(&line, &cap, f)) >= 0) {
        if (memchr(line, 0, (size_t)len)) { ok = false; break; }
        while (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r')) line[--len] = 0;
        if (first) {
            first = false;
            if (strcmp(line, "husk-prefs 1") != 0) { ok = false; break; }
            continue;
        }
        /* TAG <tab> key <tab> value */
        char *t1 = strchr(line, '\t');
        char *t2 = t1 ? strchr(t1 + 1, '\t') : NULL;
        if (!t1 || !t2 || t1 != line + 1) { ok = false; break; }
        *t1 = 0; *t2 = 0;
        char *key = unescape(t1 + 1);
        if (!key) { ok = false; break; }
        const char *val = t2 + 1;
        if (strchr(val, '\t') || tl_prefs_contains(seen, key)) { free(key); ok = false; break; }
        tl_prefs_put_bool(seen, key, true);
        if (seen->allocation_failed) { free(key); ok = false; break; }
        char *end = NULL;
        errno = 0;
        switch (line[0]) {
            case 'I': case 'J': {
                long long v = strtoll(val, &end, 10);
                ok = *val && !isspace((unsigned char)*val) && end != val && !*end && errno != ERANGE;
                if (line[0] == 'I') {
                    ok = ok && v >= INT32_MIN && v <= INT32_MAX;
                    if (ok) tl_prefs_put_int(p, key, (int32_t)v);
                } else if (ok) tl_prefs_put_long(p, key, (int64_t)v);
                break;
            }
            case 'F': {
                unsigned long v = strtoul(val, &end, 16);
                ok = strlen(val) == 8 && strspn(val,"0123456789abcdefABCDEF") == 8 && !*end && errno != ERANGE && v <= UINT32_MAX;
                if (ok) { uint32_t bits = (uint32_t)v; float fv; memcpy(&fv, &bits, 4); tl_prefs_put_float(p, key, fv); }
                break;
            }
            case 'Z':
                ok = !strcmp(val, "0") || !strcmp(val, "1");
                if (ok) tl_prefs_put_bool(p, key, val[0] == '1');
                break;
            case 'S': {
                char *sv = unescape(val); ok = sv != NULL;
                if (sv) { tl_prefs_put_string(p, key, sv); free(sv); }
                break;
            }
            default: ok = false; break;
        }
        free(key);
        if (!ok) break;
    }
    ok = ok && !first && !ferror(f) && !p->allocation_failed;
    tl_prefs_destroy(seen);
    free(line);
    fclose(f);
    return ok;
}
