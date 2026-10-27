/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Godot 4.7 moved these interfaces to Kotlin and sometimes resolves them on
 * GodotNetUtils, NativeBridge or AssetManager. Reuse the canonical handlers:
 * keeping a second descriptor/listing table makes an open on one object fail
 * when a different object is used to read, resize or close the same handle. */
#include "husk-tl-jni.h"
#include <string.h>
#define DA "org/godotengine/godot/io/directory/DirectoryAccessHandler"
#define FA "org/godotengine/godot/io/file/FileAccessHandler"
tl_jhle_fn tl_godot_file_hle(const char *, const char *, const char *);
static void missing_path(tl_jcall *c) { c->ret.j = 0; }
static void kotlin_fileResize(tl_jcall *c) {
    tl_jhle_fn resize = tl_godot_file_hle(FA, "fileResize", "(IJ)I");
    resize(c);
    if (c->ret.i) tl_jni_throw("java/io/IOException", "fileResize");
    c->ret.j = 0;
}
static const char *const k_da_classes[] = {
    DA, "org/godotengine/godot/utils/GodotNetUtils", "org/godotengine/godot/Godot",
    "org/godotengine/godot/nativeapi/GodotNativeBridge", "android/content/res/AssetManager",
};
static const char *const k_fa_classes[] = {
    FA, DA, "org/godotengine/godot/utils/GodotNetUtils",
};

#define MAXK (48 + 6 * 6)
void tl_godot_kotlin_install(void)
{
    static tl_jhle k[MAXK];
    static tl_jhle kf[MAXK];
    static const struct { const char *c, *n, *s; tl_jhle_fn f; } base[] = {
        { FA, "fileOpen", "(Ljava/lang/String;I)I", NULL },
        { FA, "fileRead", "(ILjava/nio/ByteBuffer;)I", NULL },
        { FA, "fileWrite", "(ILjava/nio/ByteBuffer;)Z", NULL },
        { FA, "fileWrite", "(ILjava/nio/ByteBuffer;)V", NULL },
        { FA, "fileResize", "(IJ)V", kotlin_fileResize },
        { FA, "fileResize", "(IJ)I", NULL },
        { FA, "fileSeek", "(IJ)V", NULL },
        { FA, "fileSeekFromEnd", "(IJ)V", NULL },
        { FA, "fileFlush", "(I)V", NULL },
        { FA, "fileClose", "(I)V", NULL },
        { FA, "fileGetPosition", "(I)J", NULL },
        { FA, "fileGetSize", "(I)J", NULL },
        { FA, "isFileEof", "(I)Z", NULL },
        { FA, "setFileEof", "(IZ)V", NULL },
        { FA, "fileExists", "(Ljava/lang/String;)Z", NULL },
        { FA, "fileSize", "(Ljava/lang/String;)J", NULL },
        { FA, "fileLastModified", "(Ljava/lang/String;)J", NULL },
        { FA, "fileLastAccessed", "(Ljava/lang/String;)J", NULL },
        { DA, "dirOpen", "(I)I", missing_path },
        { DA, "dirOpen", "(ILjava/lang/String;)I", missing_path },
        { DA, "dirNext", "(I)Ljava/lang/String;", NULL },
        { DA, "dirClose", "(I)V", NULL },
        { DA, "dirIsDir", "(I)Z", NULL },
        { DA, "isCurrentHidden", "(I)Z", NULL },
        { DA, "dirExists", "(ILjava/lang/String;)Z", NULL },
        { DA, "makeDir", "(ILjava/lang/String;)Z", NULL },
        { DA, "remove", "(ILjava/lang/String;)Z", NULL },
        { DA, "rename", "(ILjava/lang/String;Ljava/lang/String;)Z", NULL },
    };
    size_t n = 0, nf = 0;
    for (size_t i = 0; i < sizeof(base) / sizeof(base[0]) && n + 1 < MAXK; i++) {
        tl_jhle_fn fn = tl_godot_file_hle(base[i].c, base[i].n, base[i].s);
        if (!fn) fn = base[i].f;
        if (!fn) continue;
        for (size_t c = 0; c < sizeof(k_da_classes) / sizeof(k_da_classes[0]) && n + 1 < MAXK; c++) {
            if (strcmp(base[i].c, DA)) continue;
            k[n] = (tl_jhle){ k_da_classes[c], base[i].n, base[i].s, fn };
            n++;
        }
        for (size_t c = 0; c < sizeof(k_fa_classes) / sizeof(k_fa_classes[0]) && nf + 1 < MAXK; c++) {
            if (strcmp(base[i].c, FA)) continue;
            kf[nf] = (tl_jhle){ k_fa_classes[c], base[i].n, base[i].s, fn };
            nf++;
        }
    }
    k[n] = (tl_jhle){ NULL, NULL, NULL, NULL };
    kf[nf] = (tl_jhle){ NULL, NULL, NULL, NULL };
    tl_jni_register_hle(k);
    tl_jni_register_hle(kf);
}
