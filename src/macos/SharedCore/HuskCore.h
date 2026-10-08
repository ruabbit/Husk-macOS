/* SPDX-License-Identifier: GPL-2.0-or-later */
#pragma once
#include <stddef.h>
#include <stdbool.h>
char *husk_tl_scan(const char *const *paths, int count);
void *husk_tl_read_entry(const char *apk, const char *name, size_t limit, size_t *out_len);
void husk_tl_free(void *pointer);
/* Both return caller-owned JSON. These functions never execute guest code. */
char *husk_archive_entries(const char *path);
bool husk_archive_extract(const char *path, const char *entry, const char *destination, char *error, size_t capacity);
