/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Shared by the Java and SDL hosts; neither host must link the other's driver. */
#include "../translation-layer/husk-tl-internal.h"
#include <string.h>
#include <stdlib.h>

static unsigned u16(const uint8_t *p) { return p[0] | (unsigned)p[1] << 8; }
static uint32_t u32(const uint8_t *p) { return u16(p) | (uint32_t)u16(p + 2) << 16; }

/* Only ASCII XML names are needed here. Refuse truncated pools and strings. */
static bool name_is(const uint8_t *pool, size_t size, uint32_t index, const char *name)
{
    if (!pool || size < 28 || index >= u32(pool + 8) || 28ull + 4ull * index + 4 > size) return false;
    uint64_t off = (uint64_t)u32(pool + 20) + u32(pool + 28 + 4 * index);
    if (off + 2 > size) return false;
    const uint8_t *p = pool + off, *end = pool + size;
    size_t n = strlen(name), len;
    if (u32(pool + 16) & 0x100) {
        if (*p++ & 0x80) { if (p == end) return false; p++; }
        if (p == end) return false;
        len = *p++;
        if (len & 0x80) { if (p == end) return false; len = ((len & 0x7f) << 8) | *p++; }
        return len == n && (size_t)(end - p) > n && p[n] == 0 && !memcmp(p, name, n);
    }
    len = u16(p); p += 2;
    if (len & 0x8000) { if (end - p < 2) return false; len = ((len & 0x7fff) << 16) | u16(p); p += 2; }
    if (len != n || (size_t)(end - p) < (n + 1) * 2) return false;
    for (size_t i = 0; i < n; ++i) if (u16(p + 2 * i) != (unsigned char)name[i]) return false;
    return u16(p + 2 * n) == 0;
}

/* Highest <uses-feature android:glEsVersion>, including stripped attribute names. */
int tl_manifest_gles(const char *apk)
{
    tl_zip z; char err[160]; int best = 0;
    if (!tl_zip_open(&z, apk, err, sizeof(err))) return 0;
    const tl_zip_entry *e = tl_zip_find(&z, "AndroidManifest.xml");
    const uint8_t *data = NULL; size_t len = 0; bool owned = false;
    if (e && tl_zip_data(&z, e, 8u << 20, &data, &len, &owned, err, sizeof(err)) &&
        len >= 8 && u16(data) == 3 && u16(data + 2) >= 8 && u32(data + 4) == len) {
        const uint8_t *pool = NULL, *map = NULL; size_t pool_size = 0, map_count = 0;
        for (size_t off = u16(data + 2); off + 8 <= len;) {
            unsigned type = u16(data + off), header = u16(data + off + 2);
            size_t size = u32(data + off + 4);
            if (header < 8 || header > size || size > len - off) { best = 0; break; }
            const uint8_t *el = data + off;
            if (type == 1) { pool = el; pool_size = size; }
            else if (type == 0x180) { map = el + header; map_count = (size - header) / 4; }
            else if (type == 0x102 && size >= 36 && name_is(pool, pool_size, u32(el + 20), "uses-feature")) {
                size_t start = 16 + u16(el + 24), stride = u16(el + 26), count = u16(el + 28);
                if (stride < 20 || start < 36 || start > size || count > (size - start) / stride) { best = 0; break; }
                for (size_t i = 0; i < count; i++) {
                    const uint8_t *at = el + start + stride * i;
                    uint32_t idx = u32(at + 4), value = u32(at + 16);
                    bool gles = idx < map_count && u32(map + 4 * idx) == 0x01010281;
                    if (!gles) gles = name_is(pool, pool_size, idx, "glEsVersion");
                    if (gles && (at[15] == 0x10 || at[15] == 0x11) && value <= 0x7fffffff && (int)value > best) best = (int)value;
                }
            }
            off += size;
        }
    }
    if (owned) free((void *)data);
    tl_zip_close(&z);
    return best;
}
