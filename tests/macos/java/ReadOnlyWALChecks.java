// SPDX-License-Identifier: GPL-2.0-or-later
package org.husk.lifecycle;
import android.app.Activity;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteException;
import java.io.File;
import java.nio.file.Files;
import java.util.Arrays;

final class ReadOnlyWALChecks {
    static void run(Activity activity) {
        try {
            for (String name : new String[]{"readonly.db", "wal-copy.db"}) {
                File file = new File(activity.getFilesDir().getParentFile(), name);
                byte[] before = Files.readAllBytes(file.toPath());
                try (SQLiteDatabase db = SQLiteDatabase.openDatabase(file.getPath(), null, SQLiteDatabase.OPEN_READONLY)) {
                    if (!db.isReadOnly()) throw new AssertionError("not readonly");
                    // This pragma must not grant write access to a connection requested as read-only.
                    try { db.execSQL("PRAGMA query_only=OFF"); } catch (SQLiteException expected) {}
                    try (Cursor c = db.rawQuery("SELECT value FROM evidence", null)) {
                        if (!c.moveToFirst() || c.getInt(0) != 29 || c.moveToNext()) throw new AssertionError("WAL rows not visible");
                    }
                    for (String sql : new String[]{"INSERT INTO evidence VALUES(30)", "PRAGMA user_version=42", "DROP TABLE evidence"}) {
                        boolean denied = false;
                        try { db.execSQL(sql); } catch (SQLiteException expected) { denied = true; }
                        if (!denied) throw new AssertionError("readonly connection accepted " + sql);
                    }
                }
                if (!Arrays.equals(before, Files.readAllBytes(file.toPath()))) throw new AssertionError("database changed");
            }
            System.out.println("HUSK_READONLY_WAL_PASSED");
        } catch (Exception e) { throw new RuntimeException(e); }
    }
}
