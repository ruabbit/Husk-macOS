// SPDX-License-Identifier: GPL-2.0-or-later
package org.husk.lifecycle;
import android.app.Activity;
import android.content.Intent;
import android.opengl.GLSurfaceView;
import android.view.KeyEvent;
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowManager;

final class Runtime31Checks {
    static native int nativeLua();
    static void nativeRuntime() {
        System.loadLibrary("husk_runtime31");
        int expected = System.getenv("TL_NO_XMEM") == null ? 1 : 2;
        require(nativeLua() == expected);
        System.out.println("HUSK_LUA_MODE " + expected);
    }
    static volatile int ready;
    static int initialized;
    public static final class Deferred { static { initialized++; } }
    private static final StringBuilder text = new StringBuilder();
    private static int down, up, multiple, deleted, entered;
    static void require(boolean value) { if (!value) throw new AssertionError("runtime 3.1 contract"); }
    static void start(Activity activity, View view) {
        try {
            android.content.pm.PackageManager pm = activity.getPackageManager();
            android.content.pm.FeatureInfo[] features = pm.getSystemAvailableFeatures();
            require(features != null && features.length > 1);
            int glVersions = 0;
            for (android.content.pm.FeatureInfo feature : features) {
                if (feature.name == null) {
                    glVersions++;
                    require(feature.reqGlEsVersion == ((android.app.ActivityManager)activity.getSystemService("activity")).getDeviceConfigurationInfo().reqGlEsVersion);
                    require(feature.reqGlEsVersion >= 0x30000);
                } else require(pm.hasSystemFeature(feature.name));
            }
            require(glVersions == 1);
            WindowInsets unattached = new View(activity).getRootWindowInsets();
            require(unattached != null && unattached.getSystemWindowInsetBottom() >= 0 && unattached.getSystemWindowInsetTop() >= 0);
            ClassLoader parent = Runtime31Checks.class.getClassLoader();
            final int[] calls = {0};
            ClassLoader loader = new ClassLoader(parent) {
                public Class<?> loadClass(String name) throws ClassNotFoundException { calls[0]++; return super.loadClass(name); }
            };
            Class<?> deferred = Class.forName("org.husk.lifecycle.Runtime31Checks$Deferred", false, loader);
            require(deferred != null && initialized == 0 && calls[0] > 0);
            require(Class.forName("org.husk.lifecycle.Runtime31Checks$Deferred", true, loader) == deferred && initialized == 1);
            GLSurfaceView gl = new GLSurfaceView(activity);
            java.lang.reflect.Method take = GLSurfaceView.class.getMethod("huskTakeResize");
            gl.surfaceChanged(gl.getHolder(), 0, 123, 234);
            require(((Long)take.invoke(gl)).longValue() == ((123L << 32) | 234));
            require(((Long)take.invoke(gl)).longValue() == 0);
            gl.surfaceChanged(gl.getHolder(), 0, -1, 50);
            require(((Long)take.invoke(gl)).longValue() == 0);
            ready |= 1;
        } catch (Exception e) { throw new RuntimeException(e); }
        activity.getWindow().addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);
        view.setSystemUiVisibility(View.SYSTEM_UI_FLAG_FULLSCREEN | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
        view.post(() -> {
            WindowInsets insets = view.getRootWindowInsets();
            require(insets != null && insets.getSystemWindowInsetBottom() == 0 && insets.getSystemWindowInsetTop() == 0);
            ready |= 2;
        });
        activity.startActivityForResult(new Intent("android.settings.APPLICATION_DETAILS_SETTINGS"), 91);
    }
    static void result(int request, int code, Intent data) {
        if (request == 91) { require(code == Activity.RESULT_CANCELED && data == null); ready |= 4; }
    }
    static void key(KeyEvent e) {
        if (e.getKeyCode() == KeyEvent.KEYCODE_SHIFT_LEFT) return;
        if (e.getAction() == KeyEvent.ACTION_MULTIPLE) { text.append(e.getCharacters()); multiple++; }
        if (e.getAction() == KeyEvent.ACTION_DOWN) {
            down++;
            if (e.getKeyCode() == KeyEvent.KEYCODE_DEL) deleted++;
            else if (e.getKeyCode() == KeyEvent.KEYCODE_ENTER) entered++;
            else { int ch = e.getUnicodeChar(); if (ch != 0) text.appendCodePoint(ch); }
        }
        if (e.getAction() == KeyEvent.ACTION_UP) up++;
    }
    static int status() {
        return ready | (text.toString().equals("A!?中😀") && down == 5 && up == 5 && multiple == 2 && deleted == 1 && entered == 1 ? 8 : 0);
    }
}
