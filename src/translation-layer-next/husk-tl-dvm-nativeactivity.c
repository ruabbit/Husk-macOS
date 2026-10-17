/* SPDX-License-Identifier: GPL-2.0-or-later */
/* NativeActivity's NDK half. Java owns initialization and all callbacks run on
 * its actual app main thread; ELF dependencies are never given synthetic JNI
 * initialization. A Runner has one NDK input queue and one fixed canvas. */
#include "husk-tl-dvm-nativeactivity.h"
#include "husk-tl-nativeactivity-abi.h"
#include "husk-tl-bionic.h"
#include "husk-tl-ld.h"
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern void (*tl_native_activity_finish_hook)(void *);
void tl_inq_touch(int phase, int id, float x, float y);
void tl_inq_key(int device, int source, int action, int keycode);
void tl_inq_axes(int device, const float *axes);

static struct {
    ANativeActivity na;
    ANativeActivityCallbacks callbacks;
    pthread_t owner;
    jobj *activity;
    char *internal, *external, *obb;
    void *window;
    atomic_bool finish, active;
    bool queue, resumed, focused, closed;
} B = { .closed = true };

static bool owned(jobj *self)
{
    if (atomic_load(&B.active) && B.activity == self && pthread_equal(B.owner, pthread_self())) return true;
    return dvm_throw("java/lang/IllegalStateException", "NativeActivity callback outside its app main thread or lifetime");
}
static void finish(void *activity)
{
    if (activity == &B.na && atomic_load(&B.active)) atomic_store(&B.finish, true);
}
static void window_destroy(void)
{
    if (!B.window) return;
    if (B.callbacks.onNativeWindowDestroyed) B.callbacks.onNativeWindowDestroyed(&B.na, B.window);
    void (*release)(void *) = tl_bionic_find("ANativeWindow_release");
    if (release) release(B.window);
    B.window = NULL;
}
static bool destroy(void)
{
    window_destroy();
    if (B.queue && B.callbacks.onInputQueueDestroyed) B.callbacks.onInputQueueDestroyed(&B.na, &B);
    B.queue = false;
    bool acknowledged = B.callbacks.onDestroy != NULL;
    if (B.callbacks.onDestroy) B.callbacks.onDestroy(&B.na);
    B.closed = acknowledged && !tl_jni_pending();
    atomic_store(&B.active, false);
    tl_jni_unref(B.activity); B.activity = NULL;
    free(B.internal); free(B.external); free(B.obb);
    B.internal = B.external = B.obb = NULL;
    tl_log_line("java-nativeactivity: native destroy %s", B.closed ? "returned" : "unconfirmed");
    return B.closed;
}

#define NAT(name) static bool name(jobj *self, const jvalue *a, jvalue *ret)
NAT(create)
{
    (void)ret;
    if (atomic_load(&B.active) || !B.closed) return dvm_throw("java/lang/IllegalStateException", "Previous NativeActivity has not closed");
    const char *library = tl_jni_string(a[0].l), *entry = tl_jni_string(a[1].l);
    char soname[512];
    if (!library || !entry || strlen(library) > 480) return dvm_throw("java/lang/UnsatisfiedLinkError", "Invalid NativeActivity entry");
    snprintf(soname, sizeof(soname), "lib%s.so", library);
    tl_lib *lib = tl_ld_find_lib(soname);
    void (*oncreate)(ANativeActivity *, void *, size_t) = lib ? tl_ld_sym(lib, entry) : NULL;
    if (!oncreate) return dvm_throw("java/lang/UnsatisfiedLinkError", "NativeActivity entry %s missing in %s", entry, soname);
    memset(&B.na, 0, sizeof(B.na)); memset(&B.callbacks, 0, sizeof(B.callbacks));
    B.owner = pthread_self(); B.activity = tl_jni_ref(self);
    B.internal = strdup(tl_jni_string(a[2].l)); B.external = strdup(tl_jni_string(a[3].l)); B.obb = strdup(tl_jni_string(a[4].l));
    B.na.callbacks = &B.callbacks; B.na.vm = tl_jni_vm(); B.na.env = tl_jni_env(); B.na.clazz = self;
    B.na.internalDataPath = B.internal; B.na.externalDataPath = B.external; B.na.obbPath = B.obb; B.na.sdkVersion = 34;
    void *(*assets)(void *, void *) = tl_bionic_find("AAssetManager_fromJava");
    B.na.assetManager = assets ? assets(B.na.env, a[5].l) : NULL;
    B.queue = B.resumed = B.focused = false; B.closed = false;
    atomic_store(&B.finish, false); atomic_store(&B.active, true);
    tl_native_activity_finish_hook = finish;
    jobj *saved = a[6].l;
    tl_log_line("java-nativeactivity: %s in %s on app main", entry, soname);
    oncreate(&B.na, saved ? saved->arr.data : NULL, saved ? saved->arr.len : 0);
    if (tl_jni_pending()) {
        jobj *error = tl_jni_pending_object(); tl_jni_ref(error); tl_jni_clear();
        destroy(); tl_jni_clear();
        // The caller sees the original onCreate error even if cleanup failed.
        tl_jni_set_pending(error);
        tl_jni_unref(error);
        return false;
    }
    return true;
}
NAT(lifecycle)
{
    (void)ret;
    if (!owned(self)) return false;
    switch (a[0].i) {
        case 1: if (B.callbacks.onStart) B.callbacks.onStart(&B.na); break;
        case 2: if (B.callbacks.onResume) B.callbacks.onResume(&B.na); B.resumed = true; break;
        case 3: if (B.callbacks.onPause) B.callbacks.onPause(&B.na); B.resumed = false; break;
        case 4: if (B.callbacks.onStop) B.callbacks.onStop(&B.na); break;
        case 5: if (!destroy()) return tl_jni_pending() ? false : dvm_throw("java/lang/IllegalStateException", "NativeActivity did not confirm native destruction"); break;
        case 6: case 7: {
            bool focused = a[0].i == 6;
            if (B.focused != focused && B.callbacks.onWindowFocusChanged) B.callbacks.onWindowFocusChanged(&B.na, focused);
            B.focused = focused; break;
        }
        case 8:
            if (!B.queue) { B.queue = true; if (B.callbacks.onInputQueueCreated) B.callbacks.onInputQueueCreated(&B.na, &B); }
            if (!B.window) {
                void *(*from_surface)(void *, void *) = tl_bionic_find("ANativeWindow_fromSurface");
                B.window = from_surface ? from_surface(tl_jni_env(), a[1].l) : NULL;
                if (!B.window) return dvm_throw("java/lang/IllegalStateException", "NativeActivity has no native window");
                if (B.callbacks.onNativeWindowCreated) B.callbacks.onNativeWindowCreated(&B.na, B.window);
            }
            break;
        case 9: if (B.window && B.callbacks.onNativeWindowResized) B.callbacks.onNativeWindowResized(&B.na, B.window); break;
        case 10: window_destroy(); break;
        case 11: if (B.window && B.callbacks.onNativeWindowRedrawNeeded) B.callbacks.onNativeWindowRedrawNeeded(&B.na, B.window); break;
        case 12: if (B.callbacks.onLowMemory) B.callbacks.onLowMemory(&B.na); break;
        case 13: if (B.callbacks.onConfigurationChanged) B.callbacks.onConfigurationChanged(&B.na); break;
        default: return dvm_throw("java/lang/IllegalArgumentException", "Invalid NativeActivity lifecycle");
    }
    return !tl_jni_pending();
}
NAT(touch) { (void)ret; if (!owned(self)) return false; if (B.resumed) tl_inq_touch(a[0].i,a[1].i,a[2].f,a[3].f); return true; }
NAT(key) { (void)ret; if (!owned(self)) return false; if (B.resumed) tl_inq_key(a[0].i,a[1].i,a[2].i,a[3].i); return true; }
NAT(axes) {
    (void)ret; if (!owned(self)) return false;
    jobj *values=a[1].l;
    if (!values || values->kind != TL_K_PRIM_ARRAY || values->arr.len != 48) return dvm_throw("java/lang/IllegalArgumentException", "NativeActivity axes");
    if (B.resumed) tl_inq_axes(a[0].i, values->arr.data);
    return true;
}
NAT(save) {
    (void)a; ret->l=NULL; if (!owned(self)) return false;
    if (!B.callbacks.onSaveInstanceState) return true;
    size_t size=0; void *bytes=B.callbacks.onSaveInstanceState(&B.na,&size);
    if (bytes && size <= (16u << 20)) { jobj *array=tl_jni_new_prim_array('B',(uint32_t)size); memcpy(array->arr.data,bytes,size); ret->l=array; }
    free(bytes);
    if (size > (16u << 20)) return dvm_throw("java/lang/IllegalStateException", "NativeActivity saved state exceeds limit");
    return !tl_jni_pending();
}
dvm_native_fn tl_dvm_nativeactivity_native(const char *name, const char *sig)
{
    static const struct { const char *name,*sig; dvm_native_fn fn; } methods[] = {
        {"loadNativeCode","(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Landroid/content/res/AssetManager;[B)V",create},
        {"nativeLifecycle","(ILandroid/view/Surface;)V",lifecycle},
        {"nativeTouch","(IIFF)V",touch}, {"nativeKey","(IIII)V",key},
        {"nativeAxes","(I[F)V",axes}, {"nativeSave","()[B",save}
    };
    for (unsigned i=0;i<sizeof(methods)/sizeof(methods[0]);i++) if (!strcmp(name,methods[i].name)&&!strcmp(sig,methods[i].sig)) return methods[i].fn;
    return NULL;
}
void tl_dvm_nativeactivity_poll(void)
{
    if (atomic_load(&B.active) && pthread_equal(B.owner,pthread_self()) && atomic_exchange(&B.finish,false))
        tl_jni_call(B.activity,"finish","()V",NULL);
}
void tl_dvm_nativeactivity_abort(void)
{
    if (atomic_load(&B.active) && pthread_equal(B.owner,pthread_self())) { destroy(); B.closed=false; }
}
bool tl_dvm_nativeactivity_closed(void) { return !atomic_load(&B.active) && B.closed; }
