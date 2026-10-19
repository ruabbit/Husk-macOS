// SPDX-License-Identifier: GPL-2.0-or-later
package org.husk.lifecycle;
import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.database.Cursor;
import java.io.InputStream;

final class DocumentChecks {
    static volatile int result;
    private static Thread owner;
    private static void check(boolean value, String why) { if (!value) throw new AssertionError(why); }
    static void start(Activity activity) {
        owner=Thread.currentThread();
        Intent pick=new Intent(Intent.ACTION_OPEN_DOCUMENT).setType("text/plain")
            .putExtra(Intent.EXTRA_ALLOW_MULTIPLE,true);
        activity.startActivityForResult(pick,900);
        activity.startActivityForResult(pick,901);
    }
    static void receive(Activity activity,int request,int code,Intent data) {
        check(Thread.currentThread()==owner,"picker callback must use AppMain");
        if(request==901) {check(code==Activity.RESULT_CANCELED,"overlapping picker");result|=2;return;}
        if(request==902) {
            check(code==Activity.RESULT_CANCELED && data==null,"cancel result");result|=4;
            activity.startActivityForResult(new Intent(Intent.ACTION_GET_CONTENT).setType("*/*"),903);return;
        }
        if(request==903) {check(code==Activity.RESULT_CANCELED,"close cancels pending picker");result|=8;return;}
        check(request==900&&code==Activity.RESULT_OK&&data!=null,"selected result");
        check(data.getClipData().getItemCount()==2,"multiple selection");
        for(int n=0;n<2;n++) {
            Uri uri=data.getClipData().getItemAt(n).getUri();
            check("content".equals(uri.getScheme()),"content URI");
            try (InputStream input=activity.getContentResolver().openInputStream(uri)) {
                check(input.read()==65+n,"selected copy bytes");
            } catch(java.io.IOException e) {throw new AssertionError(e);}
            try (Cursor c=activity.getContentResolver().query(uri,new String[]{"_display_name","_size","flags"},null,null,null)) {
                check(c.moveToFirst()&&c.getString(0).equals("存档 %.txt")&&c.getLong(1)==1&&c.getInt(2)==0,"metadata");
            }
            boolean denied=false;
            try {activity.getContentResolver().openOutputStream(uri).close();}
            catch(Exception expected){denied=true;}
            check(denied,"read-only grant");
        }
        Uri forged=new Uri.Builder().scheme("content").authority("husk.documents").appendPath("document").appendPath("/tmp/unselected").build();
        boolean denied=false;
        try {activity.getContentResolver().query(forged,null,null,null,null);}
        catch(SecurityException expected){denied=true;}
        check(denied,"forged URI must not open arbitrary host paths");
        result|=1;
        activity.startActivityForResult(new Intent(Intent.ACTION_GET_CONTENT).setType("*/*"),902);
    }
}
