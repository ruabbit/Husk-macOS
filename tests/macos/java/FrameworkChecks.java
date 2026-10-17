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
    private static void check(boolean condition, String why) {
        if (!condition) throw new IllegalStateException(why);
    }
    static void run(Context context) {
        Configuration config = new Configuration(context.getResources().getConfiguration());
        config.densityDpi = 480;
        Resources resources = new Resources(context.getAssets(), new DisplayMetrics(), config);
        check(resources.getDisplayMetrics().densityDpi == 480 && resources.getDisplayMetrics().density == 3f,
              "configuration density must override fresh metrics");
        check(resources.getDrawable(android.R.drawable.ic_menu_add, null).getIntrinsicWidth() > 0,
              "framework image at configured density");
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
