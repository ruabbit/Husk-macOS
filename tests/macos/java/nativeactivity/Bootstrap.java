package org.husk.nativeboot;
public class Bootstrap extends android.app.Application {
    public static int stage, loaderCalls;
    @Override protected void attachBaseContext(android.content.Context base) {
        super.attachBaseContext(base);
        if (stage != 0) throw new AssertionError("duplicate attach");
        java.net.URL manifest = Bootstrap.class.getResource("/AndroidManifest.xml");
        if (manifest == null) throw new AssertionError("application class loader cannot find its APK manifest");
        try (java.io.InputStream input = manifest.openStream()) {
            if (input.read() != 3) throw new AssertionError("application manifest resource is not binary XML");
        } catch (java.io.IOException e) { throw new AssertionError("application APK resource cannot open", e); }
        String url = manifest.toString();
        if (!url.startsWith("jar:file:/data/app/")) throw new AssertionError("host APK path leaked into Android resources: " + url);
        try (java.util.zip.ZipFile apk = new java.util.zip.ZipFile(url.substring(9, url.lastIndexOf('!')))) {
            if (apk.getEntry("AndroidManifest.xml") == null) throw new AssertionError("APK alias does not resolve");
        } catch (java.io.IOException e) { throw new AssertionError("Android installation path cannot open", e); }
        stage = 1;
        System.loadLibrary("bootstrap");
        ClassLoader loader = new ClassLoader(super.getClassLoader()) {
            @Override public Class<?> loadClass(String name) throws ClassNotFoundException {
                if (name.equals("org.husk.nativeboot.Provider") || name.equals("org.husk.nativeboot.Game")) loaderCalls++;
                return super.loadClass(name);
            }
        };
        try {
            java.lang.reflect.Field info = base.getClass().getDeclaredField("mPackageInfo");
            info.setAccessible(true);
            Object loaded = info.get(base);
            java.lang.reflect.Field packageLoader = loaded.getClass().getDeclaredField("mClassLoader");
            packageLoader.setAccessible(true); packageLoader.set(loaded, loader);
            java.lang.reflect.Field contextLoader = base.getClass().getDeclaredField("mClassLoader");
            contextLoader.setAccessible(true); contextLoader.set(base, loader);
        } catch (Exception e) { throw new IllegalStateException("install application loader", e); }
    }
    @Override public void onCreate() {
        super.onCreate();
        if (stage != 2 || loaderCalls != 1) throw new AssertionError("provider or app loader missing");
        stage = 3;
    }
}
