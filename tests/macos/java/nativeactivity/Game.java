package org.husk.nativeboot;
public class Game extends android.app.NativeActivity {
    static {
        if (Bootstrap.stage != 3 || Bootstrap.loaderCalls != 2) throw new AssertionError("activity before application or bypassed loader");
        System.loadLibrary("native_fixture");
    }
    public static native int result();
    public static native void finishNative();
    @Override protected void onCreate(android.os.Bundle state) {
        super.onCreate(state);
        if (!getApplication().getClass().equals(Bootstrap.class)) throw new AssertionError("synthetic application");
        if ("java-create-failed".equals(System.getenv("HUSK_NATIVE_ACTIVITY_CASE"))) throw new IllegalStateException("fixture Java onCreate");
    }
    @Override protected void onDestroy() {
        super.onDestroy();
        getSharedPreferences("nativeboot",0).edit().putInt("destroyed",1).putInt("events",result()).commit();
    }
}
