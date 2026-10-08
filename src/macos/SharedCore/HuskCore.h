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
/* Exact user-supplied P4 sample. A scan or package name is not execution proof. */
static inline const char *husk_minecraft_apk_sha256(void) {
    return "83468d0acede2cabe3645ff4025a9c190be3cfb90e1864bcbe0277e97967cd95";
}
