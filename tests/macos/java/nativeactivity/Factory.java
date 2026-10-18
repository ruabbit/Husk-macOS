package org.husk.nativeboot;

/** The factory installs a loader before Application.attachBaseContext installs its own. */
public class Factory extends android.app.AppComponentFactory {
    public static int calls;
    public static ClassLoader installed;
    @Override public ClassLoader instantiateClassLoader(ClassLoader parent, android.content.pm.ApplicationInfo info) {
        if (calls != 0 || !"org.husk.nativeboot".equals(info.packageName)) throw new AssertionError("factory order");
        calls = 1;
        return installed = new ClassLoader(parent) {};
    }
    @Override public android.app.Application instantiateApplication(ClassLoader loader, String name)
            throws ClassNotFoundException, IllegalAccessException, InstantiationException {
        if (calls != 1 || loader != installed) throw new AssertionError("factory application loader");
        calls = 2;
        return super.instantiateApplication(loader, name);
    }
    @Override public android.content.ContentProvider instantiateProvider(ClassLoader loader, String name)
            throws ClassNotFoundException, IllegalAccessException, InstantiationException {
        if (calls != 2 || loader == installed) throw new AssertionError("factory must use attached application loader");
        calls = 3;
        return super.instantiateProvider(loader, name);
    }
    @Override public android.app.Activity instantiateActivity(ClassLoader loader, String name, android.content.Intent intent)
            throws ClassNotFoundException, IllegalAccessException, InstantiationException {
        if (calls != 3 || loader == installed) throw new AssertionError("factory activity order");
        calls = 4;
        return super.instantiateActivity(loader, name, intent);
    }
}
