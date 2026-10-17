package android.app;

/** Package state shared by the application's contexts. Apps installing their
 * loader in attachBaseContext update mClassLoader through reflection. */
public final class LoadedApk {
    private ClassLoader mClassLoader;
    public LoadedApk(ClassLoader loader) { mClassLoader = loader; }
    public ClassLoader getClassLoader() { return mClassLoader; }
}
