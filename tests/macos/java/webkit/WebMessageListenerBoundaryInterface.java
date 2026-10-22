// SPDX-License-Identifier: GPL-2.0-or-later
package org.chromium.support_lib_boundary;
import android.net.Uri;
import android.webkit.WebView;
import java.lang.reflect.InvocationHandler;
/** AndroidX boundary shape carried by the test APK, as by real consumers. */
public interface WebMessageListenerBoundaryInterface {
    void onPostMessage(WebView view, InvocationHandler message, Uri origin,
                       boolean mainFrame, InvocationHandler reply);
}
