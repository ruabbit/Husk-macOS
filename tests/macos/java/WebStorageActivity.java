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
    public final class SaveBridge {
        @JavascriptInterface public void store() {
            getSharedPreferences("web", 0).edit().putBoolean("bridge_saved", true).apply();
        }
    }
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
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
        CookieManager.getInstance().setCookie("https://husk.invalid/", "retained=1; Max-Age=86400; Path=/; Secure");
        getSharedPreferences("web", 0).edit().putInt("destroyed", 1).apply();
        web.destroy();
        if (failDestroy) throw new IllegalStateException("Expected fixture destroy failure");
        super.onDestroy();
    }
}
