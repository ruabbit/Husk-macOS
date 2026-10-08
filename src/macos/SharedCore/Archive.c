/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "HuskCore.h"
#include "husk-tl-internal.h"
#include <fcntl.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

char *husk_archive_entries(const char *path)
{
    tl_json json; tl_json_init(&json); tl_json_begin_object(&json);
    tl_zip zip; char error[256] = "";
    bool ok = tl_zip_open(&zip, path, error, sizeof(error));
    tl_json_key(&json, "error"); tl_json_string(&json, ok ? NULL : error);
    tl_json_key(&json, "entries"); tl_json_begin_array(&json);
    if (ok) {
        for (size_t i = 0; i < zip.count; ++i) {
            const tl_zip_entry *entry = &zip.entries[i];
            tl_json_begin_object(&json);
            tl_json_key(&json, "name"); tl_json_string(&json, entry->name);
            tl_json_key(&json, "size"); tl_json_int(&json, (long long)entry->usize);
            tl_json_key(&json, "method"); tl_json_int(&json, entry->method);
            tl_json_end_object(&json);
        }
        tl_zip_close(&zip);
    }
    tl_json_end_array(&json); tl_json_end_object(&json);
    return tl_json_finish(&json);
}

bool husk_archive_extract(const char *path, const char *name, const char *destination, char *error, size_t capacity)
{
    tl_zip zip;
    if (!tl_zip_open(&zip, path, error, capacity)) return false;
    const tl_zip_entry *entry = tl_zip_find(&zip, name);
    const uint8_t *bytes = NULL; size_t size = 0; bool owned = false;
    bool ok = entry && tl_zip_data(&zip, entry, (size_t)512 << 20, &bytes, &size, &owned, error, capacity);
    int fd = -1;
    if (ok) { fd = open(destination, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600); ok = fd >= 0; }
    size_t at = 0;
    while (ok && at < size) {
        ssize_t n = write(fd, bytes + at, size - at);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) ok = false; else at += (size_t)n;
    }
    if (ok) ok = fsync(fd) == 0;
    if (fd >= 0 && close(fd) != 0) ok = false;
    if (!ok && capacity && !error[0]) snprintf(error, capacity, "Entry missing, too large, or could not be written");
    if (owned) free((void *)bytes);
    tl_zip_close(&zip);
    return ok;
}
