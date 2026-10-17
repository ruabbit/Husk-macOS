package android.app;

import android.content.res.Configuration;
import android.os.Bundle;
import android.view.*;

/** Java bootstrap and lifecycle for an NDK activity. AppRunner creates the
 * application's real Application and class loader before reaching this class. */
public class NativeActivity extends Activity implements SurfaceHolder.Callback2,
        InputQueue.Callback, ViewTreeObserver.OnGlobalLayoutListener {
    public static final String META_DATA_FUNC_NAME = "android.app.func_name";
    public static final String META_DATA_LIB_NAME = "android.app.lib_name";
    private boolean mNativeLoaded;
    private SurfaceView mNativeView;
    private native void loadNativeCode(String library, String entry, String internal, String external,
                                       String obb, android.content.res.AssetManager assets, byte[] saved);
    private native void nativeLifecycle(int event, Surface surface);
    private native void nativeTouch(int phase, int id, float x, float y);
    private native void nativeKey(int device, int source, int action, int code);
    private native void nativeAxes(int device, float[] axes);
    private native byte[] nativeSave();
    private void event(int code) { if (mNativeLoaded) nativeLifecycle(code, null); }

    @Override protected void onCreate(Bundle saved) {
        super.onCreate(saved);
        husk.Manifest.Component component = husk.Manifest.activity(getClass().getName());
        Bundle meta = component != null ? component.metaData : null;
        String library = meta != null ? meta.getString(META_DATA_LIB_NAME, "main") : "main";
        String entry = meta != null ? meta.getString(META_DATA_FUNC_NAME, "ANativeActivity_onCreate") : "ANativeActivity_onCreate";
        System.loadLibrary(library);
        java.io.File external = getExternalFilesDir(null);
        java.io.File obb = new java.io.File(husk.Native.externalDir(), "Android/obb/" + getPackageName());
        obb.mkdirs();
        loadNativeCode(library, entry, getFilesDir().getAbsolutePath(), external.getAbsolutePath(),
                       obb.getAbsolutePath(), getAssets(), saved != null ? saved.getByteArray("android:native_state") : null);
        mNativeLoaded = true;
        mNativeView = new SurfaceView(this);
        mNativeView.getHolder().addCallback(this);
        setContentView(mNativeView);
    }
    @Override protected void onStart() { super.onStart(); event(1); }
    @Override protected void onResume() { super.onResume(); event(2); event(6); }
    @Override protected void onPause() { event(7); event(3); super.onPause(); }
    @Override protected void onStop() { event(4); super.onStop(); }
    @Override protected void onDestroy() {
        try { event(5); } finally { mNativeLoaded = false; super.onDestroy(); }
    }
    @Override protected void onSaveInstanceState(Bundle out) {
        super.onSaveInstanceState(out);
        if (mNativeLoaded) { byte[] state = nativeSave(); if (state != null) out.putByteArray("android:native_state", state); }
    }
    @Override public void onWindowFocusChanged(boolean focused) { super.onWindowFocusChanged(focused); event(focused ? 6 : 7); }
    @Override public void onConfigurationChanged(Configuration config) { super.onConfigurationChanged(config); event(13); }
    @Override public void onLowMemory() { super.onLowMemory(); event(12); }
    @Override public void surfaceCreated(SurfaceHolder holder) { if (mNativeLoaded) nativeLifecycle(8, holder.getSurface()); }
    @Override public void surfaceChanged(SurfaceHolder holder, int format, int width, int height) { event(9); }
    @Override public void surfaceDestroyed(SurfaceHolder holder) { event(10); }
    @Override public void surfaceRedrawNeeded(SurfaceHolder holder) { event(11); }
    @Override public void onInputQueueCreated(InputQueue queue) { /* Native queue follows the surface. */ }
    @Override public void onInputQueueDestroyed(InputQueue queue) { /* Native queue is drained during destruction. */ }
    @Override public void onGlobalLayout() { }
    @Override public boolean dispatchTouchEvent(MotionEvent e) {
        if (!mNativeLoaded) return super.dispatchTouchEvent(e);
        int action = e.getActionMasked(), index = e.getActionIndex();
        if (action == MotionEvent.ACTION_MOVE) {
            for (int i=0;i<e.getPointerCount();i++) nativeTouch(1,e.getPointerId(i),e.getX(i),e.getY(i));
        } else if (action == MotionEvent.ACTION_DOWN || action == MotionEvent.ACTION_POINTER_DOWN) {
            nativeTouch(0,e.getPointerId(index),e.getX(index),e.getY(index));
        } else if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_POINTER_UP || action == MotionEvent.ACTION_CANCEL) {
            nativeTouch(action == MotionEvent.ACTION_CANCEL ? 3 : 2,e.getPointerId(index),e.getX(index),e.getY(index));
        } else return super.dispatchTouchEvent(e);
        return true;
    }
    @Override public boolean dispatchKeyEvent(KeyEvent e) {
        if (!mNativeLoaded) return super.dispatchKeyEvent(e);
        nativeKey(e.getDeviceId(),e.getSource(),e.getAction(),e.getKeyCode()); return true;
    }
    @Override public boolean dispatchGenericMotionEvent(MotionEvent e) {
        if (!mNativeLoaded || (e.getSource() & InputDevice.SOURCE_JOYSTICK) != InputDevice.SOURCE_JOYSTICK) return super.dispatchGenericMotionEvent(e);
        float[] axes = new float[48];
        for (int i=0;i<axes.length;i++) axes[i]=e.getAxisValue(i);
        nativeAxes(e.getDeviceId(),axes); return true;
    }
}
