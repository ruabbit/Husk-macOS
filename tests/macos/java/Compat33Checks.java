// SPDX-License-Identifier: GPL-2.0-or-later
package org.husk.lifecycle;
import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.net.Uri;
import android.provider.DocumentsContract;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

public final class Compat33Checks {
    public static int initialized;
    public static final class MethodClass { static { initialized |= 1; } public void method() {} }
    public static final class StaticMethodClass { static { initialized |= 2; } public static void method() {} }
    public static final class FieldClass { static { initialized |= 4; } public int field; }
    public static final class StaticFieldClass { static { initialized |= 8; } public static int field; }
    public static final class AllocClass {
        static { initialized |= 16; }
        public AllocClass() { throw new AssertionError("AllocObject must not call a constructor"); }
    }
    public static final class FailedAllocClass {
        static { if (initialized != 0) throw new IllegalStateException("expected initialization failure"); }
    }
    public static Class<?> deferred(int index) throws Exception {
        String[] names = {"MethodClass", "StaticMethodClass", "FieldClass", "StaticFieldClass", "AllocClass", "FailedAllocClass"};
        return Class.forName("org.husk.lifecycle.Compat33Checks$" + names[index], false, Compat33Checks.class.getClassLoader());
    }
    public static int count() { return initialized; }
    static void check(boolean ok, String message) { if (!ok) throw new AssertionError(message); }
    static void run(Activity activity) {
        android.media.midi.MidiManager midi = (android.media.midi.MidiManager) activity.getSystemService("midi");
        check(midi != null && midi.getDevices() != null && midi.getDevices().length == 0,
                "MIDI service reports an empty device list without inventing hardware");
        String id = "folder/a b%中文";
        Uri doc = DocumentsContract.buildDocumentUri("org.husk.documents", id);
        check(DocumentsContract.getDocumentId(doc).equals(id), "document IDs retain encoded separators");
        Uri tree = DocumentsContract.buildTreeDocumentUri("org.husk.documents", "root/路径");
        Uri child = DocumentsContract.buildDocumentUriUsingTree(tree, id);
        check(DocumentsContract.getTreeDocumentId(child).equals("root/路径") && DocumentsContract.getDocumentId(child).equals(id), "tree document IDs");
        check(DocumentsContract.isDocumentUri(activity, child) && !DocumentsContract.isDocumentUri(activity, Uri.parse("file:///document/a")), "URI classification");
        Uri query = DocumentsContract.buildSearchDocumentsUri("org.husk.documents", "root", "a+b &中文");
        check(DocumentsContract.getSearchDocumentsQuery(query).equals("a+b &中文"), "search query encoding");
        android.content.ContextWrapper wrapper = new android.content.ContextWrapper(activity);
        check(wrapper.getDataDir().equals(activity.getDataDir()) && wrapper.getCodeCacheDir().equals(activity.getCodeCacheDir()), "wrapper delegates directories");
        check(Color.valueOf(0xff123456).isSrgb() && Color.valueOf(0xff123456).getColorSpace().isSrgb(), "color-space members are sRGB");
        Bitmap alpha = Bitmap.createBitmap(2, 2, Bitmap.Config.ALPHA_8);
        ByteBuffer pixels = ByteBuffer.allocate(alpha.getByteCount());
        for(int i=0;i<pixels.capacity();i++)pixels.put((byte)(i*41));
        pixels.rewind(); alpha.copyPixelsFromBuffer(pixels);
        ByteBuffer restored = ByteBuffer.allocate(alpha.getByteCount()); alpha.copyPixelsToBuffer(restored);
        check(java.util.Arrays.equals(pixels.array(), restored.array()), "ALPHA_8 buffer roundtrip");
        Bitmap rgb = Bitmap.createBitmap(2, 1, Bitmap.Config.RGB_565);
        ByteBuffer colors = ByteBuffer.allocate(rgb.getByteCount()).order(ByteOrder.nativeOrder());
        colors.putShort((short)0xf800).putShort((short)0x07e0).rewind(); rgb.copyPixelsFromBuffer(colors);
        check(rgb.getPixel(0,0)==0xffff0000 && rgb.getPixel(1,0)==0xff00ff00, "RGB_565 input buffer channels");
        check(android.app.usage.UsageStats.CREATOR.newArray(2).getClass() == android.app.usage.UsageStats[].class,
                "generated Parcelable creator uses its declared array type");
        alpha.recycle(); rgb.recycle();
        System.out.println("HUSK_COMPAT33_JAVA_PASSED");
    }
}
