// SPDX-License-Identifier: GPL-2.0-or-later
package org.husk.lifecycle;

import android.content.Context;
import android.content.res.Configuration;
import android.content.res.Resources;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Picture;
import android.graphics.RenderNode;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.Drawable;
import android.util.DisplayMetrics;
import android.view.View;
import android.widget.TextView;

final class FrameworkChecks {
    private static volatile byte[] allocationProbe;
    private static void check(boolean condition, String why) {
        if (!condition) throw new IllegalStateException(why);
    }
    static void run(Context context) {
        check(new 〇.例().value() == 42, "UTF-8 class names remain ordinary object references");
        boolean missingNew=false, missingMethod=false, missingField=false, tooLarge=false;
        try { new missing.optional.MissingOptional(); } catch (NoClassDefFoundError expected) { missingNew=true; }
        try { missing.optional.MissingOptional.probe(); } catch (NoClassDefFoundError expected) { missingMethod=true; }
        try { int n = missing.optional.MissingOptional.value; } catch (NoClassDefFoundError expected) { missingField=true; }
        try { allocationProbe = new byte[268435457]; } catch (OutOfMemoryError expected) { tooLarge=true; }
        check(missingNew, "missing new-instance must throw NoClassDefFoundError");
        check(missingMethod, "missing method class must throw NoClassDefFoundError");
        check(missingField, "missing field class must throw NoClassDefFoundError");
        check(tooLarge, "oversized arrays must throw OutOfMemoryError");
        android.net.wifi.WifiManager wifi = (android.net.wifi.WifiManager)context.getSystemService(Context.WIFI_SERVICE);
        check(wifi != null && wifi.getConnectionInfo() != null, "Wi-Fi info object exists without a connected network");
        java.io.File obb = context.getObbDir();
        check(obb.getPath().equals("/sdcard/Android/obb/" + context.getPackageName()) && obb.isDirectory(), "Android OBB directory alias");
        try (java.io.FileInputStream stream = new java.io.FileInputStream(new java.io.File(obb, "main.1.org.husk.lifecycle.obb"))) {
            check(stream.read() == 79, "OBB installed beside the APK is readable through Context.getObbDir");
        } catch (java.io.IOException e) { throw new IllegalStateException("OBB read", e); }
        Configuration config = new Configuration(context.getResources().getConfiguration());
        config.densityDpi = 480;
        Resources resources = new Resources(context.getAssets(), new DisplayMetrics(), config);
        check(resources.getDisplayMetrics().densityDpi == 480 && resources.getDisplayMetrics().density == 3f,
              "configuration density must override fresh metrics");
        check(resources.getDrawable(android.R.drawable.ic_menu_add, null).getIntrinsicWidth() > 0,
              "framework image at configured density");
        Drawable image = resources.getDrawable(android.R.drawable.ic_menu_add, null);
        check(image.getConstantState() != null && image.getConstantState().newDrawable(resources) != null,
              "framework drawables can be cloned by Material menus");
        config.densityDpi = 160;
        resources.updateConfiguration(config, new DisplayMetrics());
        check(resources.getDrawable(android.R.drawable.ic_menu_add, null).getIntrinsicWidth() > 0,
              "trimmed framework image falls back from mdpi");

        TextView button = new TextView(context) {
            private int depth;
            @Override public void setCompoundDrawables(Drawable l, Drawable t, Drawable r, Drawable b) {
                // Bound the regression so old code fails without a stack overflow.
                check(++depth < 4, "compound drawables recursively dispatch to the subclass");
                setCompoundDrawablesRelative(l, t, r, b);
                depth--;
            }
        };
        Drawable icon = new ColorDrawable(0xff115588);
        icon.setBounds(0, 0, 12, 12);
        button.setCompoundDrawables(icon, null, null, null);
        check(button.getCompoundDrawablesRelative()[0] == icon, "relative drawable retained");
        button.cancelLongPress();

        View view = new View(context) {
            @Override protected void onDraw(Canvas canvas) { canvas.drawColor(0xff2864a0); }
        };
        view.layout(0, 0, 16, 16);
        Bitmap first = view.getDrawingCache();
        check(first != null && first.getPixel(8, 8) == 0xff2864a0, "drawing cache pixels");
        check(view.getDrawingCache() == first, "drawing cache reuses its bitmap");
        view.layout(0, 0, 24, 24);
        Bitmap resized = view.getDrawingCache();
        check(first.isRecycled() && resized.getWidth() == 24, "resizing releases old drawing cache");
        view.destroyDrawingCache();
        check(resized.isRecycled(), "destroy releases drawing cache");

        Picture picture = new Picture();
        RenderNode layer = new RenderNode("fixture");
        Bitmap destination = Bitmap.createBitmap(32, 32, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(destination);
        for (int n = 0; n < 8; n++) {
            int size = 16 + n, color = 0xff112230 + n;
            picture.beginRecording(size, size).drawColor(color);
            picture.endRecording();
            destination.eraseColor(0);
            picture.draw(canvas);
            check(destination.getPixel(8, 8) == color, "picture replacement remains drawable");
            layer.setPosition(0, 0, size, size);
            layer.beginRecording(size, size).drawColor(color);
            layer.endRecording();
            destination.eraseColor(0);
            canvas.drawRenderNode(layer);
            check(destination.getPixel(8, 8) == color && layer.hasDisplayList(), "resized layer pixels");
        }
        layer.discardDisplayList();
        destination.eraseColor(0);
        canvas.drawRenderNode(layer);
        check(!layer.hasDisplayList() && layer.computeApproximateMemoryUsage() == 0 && destination.getPixel(8, 8) == 0,
              "discarded layer stops drawing and releases its display list");
        System.out.println("PASS framework density, compound drawables and bitmap replacement lifecycle");
    }
}
