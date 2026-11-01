/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-dvm-internal.h"
#include <stdio.h>
#include <string.h>
#include <unistd.h>

extern dvm_native_fn dvm_binder_native(const char *, const char *, const char *);
#define CHECK(v) do { if (!(v)) { fprintf(stderr, "FAIL native Parcel line %d: %s\n", __LINE__, #v); return false; } } while (0)
static bool call(const char *name, const char *sig, const jvalue *args, jvalue *ret)
{
    dvm_native_fn fn = dvm_binder_native("android/os/Parcel", name, sig);
    return fn && fn(NULL, args, ret);
}
bool mac_parcel_checks(void)
{
    jvalue ret, a[2];
    CHECK(call("nativeCreate", "()J", NULL, &ret) && ret.j > 0);
    int64_t handle = ret.j;
    a[0].j = handle; a[1].i = 256;
    CHECK(call("nativeSetDataCapacity", "(JI)V", a, &ret));
    CHECK(call("nativeDataCapacity", "(J)I", a, &ret) && ret.i >= 256);
    CHECK(call("nativeDataSize", "(J)I", a, &ret) && ret.i == 0);
    a[1].i = 0x12345678;
    CHECK(call("nativeWriteInt", "(JI)I", a, &ret) && ret.i == 0);
    a[1].j = INT64_C(0x123456789abcdef);
    CHECK(call("nativeWriteLong", "(JJ)I", a, &ret) && ret.i == 0);
    a[1].i = 0;
    CHECK(call("nativeSetDataPosition", "(JI)V", a, &ret));
    CHECK(call("nativeReadInt", "(J)I", a, &ret) && ret.i == 0x12345678);
    CHECK(call("nativeReadLong", "(J)J", a, &ret) && ret.j == INT64_C(0x123456789abcdef));
    CHECK(!call("nativeReadInt", "(J)I", a, &ret) && tl_jni_pending()); tl_jni_clear();
    a[1].i = -1;
    CHECK(!call("nativeSetDataSize", "(JI)V", a, &ret) && tl_jni_pending()); tl_jni_clear();
    a[1].i = (1 << 20) + 1;
    CHECK(!call("nativeSetDataCapacity", "(JI)V", a, &ret) && tl_jni_pending()); tl_jni_clear();
    a[1].i = 13;
    CHECK(!call("nativeSetDataPosition", "(JI)V", a, &ret) && tl_jni_pending()); tl_jni_clear();
    CHECK(call("nativeFreeBuffer", "(J)V", a, &ret));
    CHECK(call("nativeDataSize", "(J)I", a, &ret) && ret.i == 0);
    jobj *token = tl_jni_new_string("org.husk.Parcel");
    a[1].l = token;
    CHECK(call("nativeWriteString16", "(JLjava/lang/String;)V", a, &ret));
    a[1].i = 0; CHECK(call("nativeSetDataPosition", "(JI)V", a, &ret));
    CHECK(call("nativeReadString16", "(J)Ljava/lang/String;", a, &ret));
    int32_t nc = 0; const uint16_t *chars = tl_dvm_string_chars(ret.l, &nc);
    CHECK(chars && nc == 15 && chars[0] == 'o' && chars[14] == 'l');
    CHECK(call("nativeFreeBuffer", "(J)V", a, &ret));
    a[1].l = token; CHECK(call("nativeWriteInterfaceToken", "(JLjava/lang/String;)V", a, &ret));
    a[1].i = 0; CHECK(call("nativeSetDataPosition", "(JI)V", a, &ret));
    a[1].l = token; CHECK(call("nativeEnforceInterface", "(JLjava/lang/String;)V", a, &ret));
    a[1].i = 0; CHECK(call("nativeSetDataPosition", "(JI)V", a, &ret));
    a[1].l = tl_jni_new_string("different");
    CHECK(!call("nativeEnforceInterface", "(JLjava/lang/String;)V", a, &ret) && tl_jni_pending()); tl_jni_clear();
    CHECK(call("nativeDestroy", "(J)V", a, &ret));
    CHECK(!call("nativeDataSize", "(J)I", a, &ret) && tl_jni_pending()); tl_jni_clear();
    CHECK(call("nativeCreate", "()J", NULL, &ret) && ret.j != handle);
    a[0].j = ret.j; CHECK(call("nativeDestroy", "(J)V", a, &ret));
    CHECK(!dvm_binder_native("android/os/Parcel", "nativeCreateByteArray", "(J)[B"));
    CHECK(!dvm_binder_native("android/os/Parcel", "nativeWriteInt", "(JI)V"));
    CHECK(!dvm_binder_native("android/os/Parcel", "nativeWriteString8", "(JLjava/lang/String;)V"));
    CHECK(!dvm_binder_native("android/os/Parcel", "nativeReadStrongBinder", "(J)Landroid/os/IBinder;"));
    dvm_native_fn uid = dvm_binder_native("android/os/Binder", "getCallingUid", "()I");
    CHECK(uid && uid(NULL, NULL, &ret) && ret.i == (int32_t)getuid());
    CHECK(!dvm_binder_native("android/os/Binder", "getCallingUidOrThrow", "()I"));
    CHECK(!tl_jni_pending());
    puts("PASS native Parcel exact signatures, bounds, token mismatch, stale handles and local caller identity");
    return true;
}
