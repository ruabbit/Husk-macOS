// SPDX-License-Identifier: GPL-2.0-or-later
package org.husk.webstorage;

import android.app.Activity;
import android.os.Bundle;
import android.webkit.CookieManager;
import android.webkit.JsResult;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.view.KeyEvent;

/** A real DEX WebView using APK assets, Java callbacks and final cookie writes. */
public final class WebStorageActivity extends Activity {
    private WebView web;
    private boolean failDestroy;
    private int webGeneration;
    private final android.os.Handler main = new android.os.Handler(android.os.Looper.getMainLooper());
    private volatile boolean lateBridgeDestroy;
    private volatile boolean finishOnPause;
    public interface BoundaryFactory { java.lang.reflect.InvocationHandler createWebView(WebView view); }
    public interface BoundaryProvider {
        void addWebMessageListener(String name, String[] origins, java.lang.reflect.InvocationHandler listener);
    }
    public final class SaveBridge {
        private int calls;
        private final int generation = webGeneration;
        @JavascriptInterface public int viewGeneration() { return generation; }
        @JavascriptInterface public void retire(String mode) {
            main.postDelayed(() -> {
                WebView old = web;
                old.destroy();
                if ("duplicate".equals(mode)) { old.destroy(); old.destroy(); }
                webGeneration++;
                if ("only".equals(mode)) setContentView(new android.widget.FrameLayout(WebStorageActivity.this));
                else installWeb();
                getSharedPreferences("web", 0).edit().putBoolean("view_retired", true).apply();
            }, 100);
        }
        @JavascriptInterface public boolean installListener(boolean fail) {
            try {
                java.lang.reflect.InvocationHandler factory = (java.lang.reflect.InvocationHandler)
                    Class.forName("android.webkit.HuskSupportLib").getMethod("factory").invoke(null);
                java.lang.reflect.InvocationHandler provider = (java.lang.reflect.InvocationHandler)
                    factory.invoke(null, BoundaryFactory.class.getMethod("createWebView", WebView.class), new Object[] {web});
                java.lang.reflect.InvocationHandler listener = (proxy, method, args) -> {
                    if (fail) throw new IllegalStateException("Expected listener failure");
                    java.lang.reflect.InvocationHandler message = (java.lang.reflect.InvocationHandler)args[1];
                    String data = (String)message.invoke(null,
                        org.chromium.support_lib_boundary.WebMessageBoundaryInterface.class.getMethod("getData"), null);
                    getSharedPreferences("web", 0).edit().putString("listener_saved", data).apply();
                    main.post(() -> getSharedPreferences("web", 0).edit().putBoolean("listener_ui_saved", true).apply());
                    java.lang.reflect.InvocationHandler reply = (java.lang.reflect.InvocationHandler)args[4];
                    reply.invoke(null, org.chromium.support_lib_boundary.JavaScriptReplyProxyBoundaryInterface.class.getMethod("postMessage", String.class), new Object[] {"saved"});
                    return null;
                };
                provider.invoke(null, BoundaryProvider.class.getMethod("addWebMessageListener", String.class, String[].class, java.lang.reflect.InvocationHandler.class),
                    new Object[] {"nativeMessage", new String[] {"*"}, listener});
                return true;
            } catch (Throwable error) { throw new IllegalStateException("Cannot install fixture listener", error); }
        }
        @JavascriptInterface public void recordUI() {
            main.post(() -> getSharedPreferences("web", 0).edit().putBoolean("view_ui_saved", true).apply());
        }
        @JavascriptInterface public void store() {
            final int count = ++calls;
            getSharedPreferences("web", 0).edit().putBoolean("bridge_saved", true).putInt("bridge_calls", count).apply();
            new android.os.Handler(android.os.Looper.getMainLooper()).post(() ->
                getSharedPreferences("web", 0).edit().putInt("bridge_main_calls", count).apply());
        }
        @JavascriptInterface public int previous() { return getSharedPreferences("web", 0).getInt("bridge_calls", 0); }
        @JavascriptInterface public void fail() { throw new IllegalStateException("Expected fixture save failure"); }
        @JavascriptInterface public void armLateDestroy() { lateBridgeDestroy = true; }
        @JavascriptInterface public int generation() { return getIntent().getIntExtra("generation", 0); }
        @JavascriptInterface public void closeOnPause() { finishOnPause = true; }
        @JavascriptInterface public void navigate() { web.loadUrl("file:///android_asset/storage.html?next"); }
        @JavascriptInterface public void close(String mode) {
            // Let the JavaScript call return before the Activity starts closing.
            new android.os.Handler(android.os.Looper.getMainLooper()).postDelayed(() -> {
                if ("destroy-failed".equals(mode)) failDestroy = true;
                if ("affinity".equals(mode)) { finishAffinity(); finishAffinity(); }
                else {
                    finish();
                    if ("duplicate".equals(mode)) { finish(); finishAffinity(); finishAffinity(); }
                }
            }, 100);
        }
        @JavascriptInterface public void replace(boolean finishFirst) {
            new android.os.Handler(android.os.Looper.getMainLooper()).post(() -> {
                android.content.Intent next = new android.content.Intent(WebStorageActivity.this, WebStorageActivity.class);
                next.putExtra("generation", 1);
                if (finishFirst) finish();
                startActivity(next);
                if (!finishFirst) finish();
            });
        }
        @JavascriptInterface public void child() {
            new android.os.Handler(android.os.Looper.getMainLooper()).post(() ->
                startActivityForResult(new android.content.Intent(WebStorageActivity.this, Child.class), 42));
        }
        @JavascriptInterface public void affinityChild() {
            new android.os.Handler(android.os.Looper.getMainLooper()).postDelayed(() ->
                startActivity(new android.content.Intent(WebStorageActivity.this, Child.class).putExtra("affinity", true)), 100);
        }
    }
    public static final class Child extends Activity {
        @Override public void onCreate(Bundle state) {
            super.onCreate(state);
            if (getIntent().getBooleanExtra("affinity", false)) finishAffinity();
            else { setResult(7); finish(); }
        }
        @Override public void onDestroy() {
            getSharedPreferences("web", 0).edit().putBoolean("child_destroyed", true).apply();
            super.onDestroy();
        }
    }
    @Override protected void onActivityResult(int request, int result, android.content.Intent data) {
        if (request == 42) getSharedPreferences("web", 0).edit().putInt("child_result", result).apply();
    }
    @Override public void onPause() {
        super.onPause();
        if (finishOnPause) {
            getSharedPreferences("web", 0).edit().putBoolean("finished_while_paused", true).apply();
            finish();
        }
    }
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        installWeb();
    }
    private void installWeb() {
        web = new WebView(this);
        web.getSettings().setJavaScriptEnabled(true);
        web.getSettings().setDomStorageEnabled(true);
        web.addJavascriptInterface(new SaveBridge(), "nativeSave");
        web.setWebViewClient(new WebViewClient() {
            @Override public void onPageFinished(WebView view, String url) {
                String cookie = CookieManager.getInstance().getCookie("https://husk.invalid/");
                getSharedPreferences("web", 0).edit().putString("cookie", cookie == null ? "empty" : cookie).apply();
            }
        });
        web.setWebChromeClient(new WebChromeClient() {
            @Override public boolean onJsConfirm(WebView view, String url, String message, JsResult result) {
                // Deliberately keep a *test* decision pending. Host shutdown
                // must settle it; dropping its block is not a valid teardown.
                getSharedPreferences("web", 0).edit().putBoolean("pending_dialog", true).apply();
                return true;
            }
        });
        setContentView(web);
        web.loadUrl("file:///android_asset/storage.html");
    }
    @Override public boolean onKeyDown(int code, KeyEvent event) {
        if (code == KeyEvent.KEYCODE_F) {
            failDestroy = true;
            getSharedPreferences("web", 0).edit().putBoolean("fail_destroy", true).apply();
            return true;
        }
        return super.onKeyDown(code, event);
    }
    @Override public void onDestroy() {
        if (lateBridgeDestroy) web.evaluateJavascript("nativeSave.store()", null);
        CookieManager.getInstance().setCookie("https://husk.invalid/", "retained=1; Max-Age=86400; Path=/; Secure");
        getSharedPreferences("web", 0).edit().putInt("destroyed", 1).apply();
        getSharedPreferences("web", 0).edit().putInt("main_at_destroy", getSharedPreferences("web", 0).getInt("bridge_main_calls", 0)).apply();
        web.destroy();
        if (failDestroy) throw new IllegalStateException("Expected fixture destroy failure");
        super.onDestroy();
    }
}
