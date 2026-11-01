/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * JNI natives for AOSP android.os.Parcel / Binder / BinderProxy, so framework.jar
 * talks the in-process binder without libandroid_runtime.
 */
#include "husk-tl-dvm-internal.h"
#include "husk-tl-binder.h"

#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>

#define NAT(fn) static bool fn(jobj *self, const jvalue *a, jvalue *ret)
#define UNUSED (void)self; (void)a; (void)ret


typedef struct {
    uint64_t handle;
    uint8_t *buf;
    uint32_t cap, pos, size;
} npcl;

#define PARCEL_LIMIT (1u << 20)
static npcl *parcels[256];
static uint64_t generation;
static pthread_mutex_t parcels_lock = PTHREAD_MUTEX_INITIALIZER;
/* Serialize each Parcel operation, including destruction. No guest pointer is
 * ever used as a native handle. Binder callbacks run outside this lock. */
#define PNAT(fn) \
    static bool fn##_impl(jobj *, const jvalue *, jvalue *); \
    NAT(fn) { pthread_mutex_lock(&parcels_lock); if (ret) ret->j = 0; \
        bool ok = fn##_impl(self, a, ret) && !tl_jni_pending(); \
        pthread_mutex_unlock(&parcels_lock); return ok; } \
    static bool fn##_impl(jobj *self, const jvalue *a, jvalue *ret)
static npcl *of(int64_t handle)
{
    npcl *n = NULL;
    for (size_t i = 0; i < 256; ++i) if (parcels[i] && parcels[i]->handle == (uint64_t)handle) { n = parcels[i]; break; }
    if (!n) tl_jni_throw("java/lang/IllegalStateException", "stale or invalid Parcel handle");
    return n;
}
static bool grow(npcl *n, uint32_t need)
{
    if (need > PARCEL_LIMIT) { tl_jni_throw("java/lang/IllegalArgumentException", "Parcel exceeds size limit"); return false; }
    if (need <= n->cap) return true;
    uint32_t c = n->cap ? n->cap : 64;
    while (c < need) c *= 2;
    uint8_t *q = realloc(n->buf, c);
    if (!q) { tl_jni_throw("java/lang/OutOfMemoryError", "Parcel allocation"); return false; }
    memset(q + n->cap, 0, c - n->cap);
    n->buf = q; n->cap = c;
    return true;
}

static void w_i32(npcl *n, int32_t v)
{
    if (!grow(n, n->pos + 4)) return;
    if (n->pos + 4 > n->cap) return;
    memcpy(n->buf + n->pos, &v, 4);
    n->pos += 4;
    if (n->pos > n->size) n->size = n->pos;
}

static int32_t r_i32(npcl *n)
{
    if (n->pos + 4 > n->size) { tl_jni_throw("android/os/BadParcelableException", "truncated Parcel integer"); return 0; }
    int32_t v;
    memcpy(&v, n->buf + n->pos, 4);
    n->pos += 4;
    return v;
}

static jvalue J(int64_t v) { jvalue r; r.j = v; return r; }
static jvalue I(int32_t v) { jvalue r; r.j = 0; r.i = v; return r; }
static jvalue L(void *p) { jvalue r; r.j = 0; r.l = p; return r; }
static jvalue Z(bool v) { jvalue r; r.j = 0; r.z = v; return r; }

static int64_t field_j(jobj *o, const char *name)
{
    if (!o) return 0;
    return tl_jni_get_field(o, name, "J").j;
}

static void set_field_j(jobj *o, const char *name, int64_t v)
{
    if (!o) return;
    tl_jni_set_field(o, name, "J", J(v));
}

PNAT(P_create)
{
    UNUSED;
    npcl *n = NULL;
    for (int i = 0; i < 256; ++i) if (!parcels[i]) {
        n = calloc(1, sizeof(*n));
        if (n) { n->handle = ++generation; parcels[i] = n; }
        break;
    }
    if (!n) { tl_jni_throw("java/lang/OutOfMemoryError", "Parcel table full"); return false; }
    *ret = J((int64_t)n->handle);
    return true;
}

PNAT(P_destroy)
{
    UNUSED;
    npcl *n = of(a[0].j);
    if (!n) return true;
    for (int i = 0; i < 256; ++i) if (parcels[i] == n) { parcels[i] = NULL; break; }
    free(n->buf);
    free(n);
    return true;
}

PNAT(P_writeInt) { UNUSED; npcl *n = of(a[0].j); if (n) w_i32(n, a[1].i); return true; }
PNAT(P_readInt) { UNUSED; npcl *n = of(a[0].j); *ret = I(n ? r_i32(n) : 0); return true; }
PNAT(P_writeLong)
{
    UNUSED;
    npcl *n = of(a[0].j);
    if (!n) return true;
    if (!grow(n, n->pos + 8)) return false;
    memcpy(n->buf + n->pos, &a[1].j, 8);
    n->pos += 8;
    if (n->pos > n->size) n->size = n->pos;
    return true;
}
PNAT(P_readLong)
{
    UNUSED;
    npcl *n = of(a[0].j);
    int64_t v = 0;
    if (n && n->pos + 8 <= n->size) { memcpy(&v, n->buf + n->pos, 8); n->pos += 8; }
    else if (n) tl_jni_throw("android/os/BadParcelableException", "truncated Parcel long");
    *ret = J(v);
    return true;
}
PNAT(P_dataSize) { UNUSED; npcl *n = of(a[0].j); *ret = I(n ? (int32_t)n->size : 0); return true; }
PNAT(P_dataAvail) { UNUSED; npcl *n = of(a[0].j); *ret = I(n && n->size > n->pos ? (int32_t)(n->size - n->pos) : 0); return true; }
PNAT(P_dataPos) { UNUSED; npcl *n = of(a[0].j); *ret = I(n ? (int32_t)n->pos : 0); return true; }
PNAT(P_dataCap) { UNUSED; npcl *n = of(a[0].j); *ret = I(n ? (int32_t)n->cap : 0); return true; }
PNAT(P_setPos) { UNUSED; npcl *n = of(a[0].j); if (n) { if (a[1].i < 0 || (uint32_t)a[1].i > n->size) { tl_jni_throw("java/lang/IllegalArgumentException", "Parcel position"); return false; } n->pos = (uint32_t)a[1].i; } return true; }
PNAT(P_setSize)
{
    UNUSED;
    npcl *n = of(a[0].j);
    if (!n) return true;
    if (a[1].i < 0) { tl_jni_throw("java/lang/IllegalArgumentException", "negative Parcel size"); return false; }
    if (!grow(n, (uint32_t)a[1].i)) return false;
    if ((uint32_t)a[1].i > n->size) memset(n->buf + n->size, 0, (uint32_t)a[1].i - n->size);
    n->size = (uint32_t)a[1].i;
    if (n->pos > n->size) n->pos = n->size;
    return true;
}

PNAT(P_setCap) {
    UNUSED; npcl *n = of(a[0].j); if (!n) return false;
    if (a[1].i < 0) { tl_jni_throw("java/lang/IllegalArgumentException", "negative Parcel capacity"); return false; }
    return grow(n, (uint32_t)a[1].i);
}
PNAT(P_freeBuffer) {
    UNUSED; npcl *n = of(a[0].j); if (!n) return false;
    free(n->buf); n->buf = NULL; n->cap = n->size = n->pos = 0; return true;
}

static void w_str16(npcl *n, jobj *s)
{
    if (!s) { w_i32(n, -1); return; }
    int32_t nc = 0;
    const uint16_t *ch = tl_dvm_string_chars(s, &nc);
    if (nc < 0 || nc > PARCEL_LIMIT / 2 - 8) { tl_jni_throw("java/lang/IllegalArgumentException", "Parcel string length"); return; }
    uint32_t bytes = (uint32_t)(nc + 1) * 2;
    uint32_t pad = (bytes + 3) & ~3u;
    if (!grow(n, n->pos + 4 + pad)) return;
    w_i32(n, nc);
    if (ch && nc) memcpy(n->buf + n->pos, ch, (size_t)nc * 2);
    memset(n->buf + n->pos + (size_t)nc * 2, 0, pad - (size_t)nc * 2);
    n->pos += pad;
    if (n->pos > n->size) n->size = n->pos;
}

PNAT(P_writeString) { UNUSED; npcl *n = of(a[0].j); if (n) w_str16(n, a[1].l); return true; }
PNAT(P_readString)
{
    UNUSED;
    npcl *n = of(a[0].j);
    *ret = L(NULL);
    if (!n) return true;
    int32_t nc = r_i32(n);
    if (tl_jni_pending()) return false;
    if (nc == -1) return true;
    if (nc < -1) { tl_jni_throw("android/os/BadParcelableException", "negative Parcel string length"); return false; }
    if (nc > PARCEL_LIMIT / 2 - 8) { tl_jni_throw("java/lang/IllegalArgumentException", "Parcel string length"); return false; }
    uint32_t bytes = (uint32_t)(nc + 1) * 2;
    uint32_t pad = (bytes + 3) & ~3u;
    if (pad > n->size - n->pos) { tl_jni_throw("java/lang/IllegalArgumentException", "truncated Parcel string"); return false; }
    uint16_t nul; memcpy(&nul, n->buf + n->pos + (size_t)nc * 2, 2);
    if (nul) { tl_jni_throw("android/os/BadParcelableException", "unterminated Parcel string"); return false; }
    *ret = L(tl_dvm_string_u16((const uint16_t *)(n->buf + n->pos), nc));
    n->pos += pad;
    return true;
}

PNAT(P_writeToken)
{
    UNUSED;
    npcl *n = of(a[0].j);
    if (!n) return true;
    w_i32(n, 0x01000000);
    w_i32(n, -1);
    w_str16(n, a[1].l);
    return true;
}

PNAT(P_enforce)
{
    UNUSED;
    npcl *n = of(a[0].j); if (!n) return false;
    if (n->size - n->pos < 12) { tl_jni_throw("java/lang/SecurityException", "missing interface token"); return false; }
    r_i32(n); r_i32(n);
    int32_t nc = r_i32(n), expected_count = 0;
    const uint16_t *expected = tl_dvm_string_chars(a[1].l, &expected_count);
    if (nc < 0 || nc != expected_count || !expected || nc > PARCEL_LIMIT / 2 - 8) {
        tl_jni_throw("java/lang/SecurityException", "interface token mismatch"); return false;
    }
    uint32_t pad = ((uint32_t)(nc + 1) * 2 + 3) & ~3u;
    if (pad > n->size - n->pos || memcmp(n->buf + n->pos, expected, (size_t)nc * 2)) {
        tl_jni_throw("java/lang/SecurityException", "interface token mismatch"); return false;
    }
    n->pos += pad; return true;
}

static jobj *proxy_for(uint32_t handle)
{
    void *p = husk_binder_ptr(handle);
    if (p) return p;
    tl_jclass *jc = dvm_class_named("android/os/BinderProxy");
    if (!jc) jc = dvm_class_named("android/os/Binder");
    if (!jc) return NULL;
    jobj *o = dvm_new_object(jc);
    if (!o) return NULL;
    o->refs = 1u << 30;
    set_field_j(o, "mNativeData", (int64_t)handle);
    set_field_j(o, "mObject", (int64_t)handle);
    husk_binder_set_ptr(handle, o);
    return o;
}

PNAT(P_marshall)
{
    UNUSED;
    npcl *n = of(a[0].j);
    if (!n) { *ret = L(NULL); return true; }
    jobj *arr = tl_jni_new_prim_array('B', n->size);
    if (arr && n->buf && n->size) memcpy(arr->arr.data, n->buf, n->size);
    *ret = L(arr);
    return true;
}

NAT(B_transact)
{
    /* Snapshot input before calling a service; revalidate output after it returns.
     * Object offsets remain unsupported until a real managed-object bridge exists. */
    uint32_t handle = (uint32_t)field_j(self, "mNativeData");
    int64_t out_handle = field_j(a[2].l, "mNativePtr");
    pthread_mutex_lock(&parcels_lock);
    npcl *in = of(field_j(a[1].l, "mNativePtr"));
    size_t len = in ? in->size : 0;
    uint8_t *data = len ? malloc(len) : NULL;
    if (in && len && data) memcpy(data, in->buf, len);
    bool valid = in && (!len || data);
    pthread_mutex_unlock(&parcels_lock);
    if (!valid) { if (!tl_jni_pending()) tl_jni_throw("java/lang/OutOfMemoryError", "Binder input"); return false; }
    husk_binder_reply r = {0};
    int rc = husk_binder_transact(handle, (uint32_t)a[0].i, (uint32_t)a[3].i, data, len, NULL, 0, &r);
    free(data);
    if (rc == 0 && (r.n_offsets || r.data_size > PARCEL_LIMIT || (r.data_size && !r.data))) {
        tl_jni_throw("java/lang/UnsupportedOperationException", "Binder object reply or oversized data");
        husk_binder_reply_free(&r); return false;
    }
    if (rc == 0 && out_handle) {
        pthread_mutex_lock(&parcels_lock);
        npcl *out = of(out_handle);
        if (out && grow(out, (uint32_t)r.data_size)) {
            if (r.data_size) memcpy(out->buf, r.data, r.data_size);
            out->size = (uint32_t)r.data_size; out->pos = 0;
        }
        pthread_mutex_unlock(&parcels_lock);
    }
    husk_binder_reply_free(&r); *ret = Z(rc == 0); return !tl_jni_pending();
}

NAT(B_context)
{
    UNUSED;
    *ret = L(proxy_for(0));
    return true;
}

NAT(B_pid) { UNUSED; *ret = I((int32_t)getpid()); return true; }
NAT(B_uid) { UNUSED; *ret = I((int32_t)geteuid()); return true; }

dvm_native_fn dvm_binder_native(const char *cls, const char *name, const char *sig);

dvm_native_fn dvm_binder_native(const char *cls, const char *name, const char *sig)
{
    if (!cls || !name || !sig) return NULL;
    /* Android 14 Parcel signatures. String8, binder objects and unimplemented
     * methods must not alias String16/integers or silently return success. */
    static const struct { const char *name, *sig; dvm_native_fn fn; } parcel[] = {
        {"nativeCreate", "()J", P_create}, {"nativeDestroy", "(J)V", P_destroy},
        {"nativeFreeBuffer", "(J)V", P_freeBuffer},
        {"nativeWriteInt", "(JI)I", P_writeInt}, {"nativeReadInt", "(J)I", P_readInt},
        {"nativeWriteLong", "(JJ)I", P_writeLong}, {"nativeReadLong", "(J)J", P_readLong},
        {"nativeDataSize", "(J)I", P_dataSize}, {"nativeDataAvail", "(J)I", P_dataAvail},
        {"nativeDataPosition", "(J)I", P_dataPos}, {"nativeDataCapacity", "(J)I", P_dataCap},
        {"nativeSetDataPosition", "(JI)V", P_setPos}, {"nativeSetDataSize", "(JI)V", P_setSize},
        {"nativeSetDataCapacity", "(JI)V", P_setCap},
        {"nativeWriteString16", "(JLjava/lang/String;)V", P_writeString},
        {"nativeReadString16", "(J)Ljava/lang/String;", P_readString},
        {"nativeWriteInterfaceToken", "(JLjava/lang/String;)V", P_writeToken},
        {"nativeEnforceInterface", "(JLjava/lang/String;)V", P_enforce},
        {"nativeMarshall", "(J)[B", P_marshall}
    };
    if (!strcmp(cls, "android/os/Parcel")) {
        for (size_t i = 0; i < sizeof(parcel)/sizeof(parcel[0]); ++i)
            if (!strcmp(name, parcel[i].name) && !strcmp(sig, parcel[i].sig)) return parcel[i].fn;
    } else if (!strcmp(cls, "android/os/BinderProxy")) {
        if (!strcmp(name, "transactNative") && !strcmp(sig, "(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z")) return B_transact;
    } else if (!strcmp(cls, "android/os/Binder")) {
        if (!strcmp(name, "getCallingPid") && !strcmp(sig, "()I")) return B_pid;
        if (!strcmp(name, "getCallingUid") && !strcmp(sig, "()I")) return B_uid;
    } else if (!strcmp(cls, "com/android/internal/os/BinderInternal") || !strcmp(cls, "android/os/BinderInternal")) {
        if (!strcmp(name, "getContextObject") && !strcmp(sig, "()Landroid/os/IBinder;")) return B_context;
    }
    return NULL;
}
