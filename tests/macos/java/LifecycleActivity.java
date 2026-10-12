// SPDX-License-Identifier: GPL-2.0-or-later
package org.husk.lifecycle;

import android.app.Activity;
import android.os.Bundle;
import android.graphics.Canvas;
import android.view.View;
import android.view.MotionEvent;
import android.view.KeyEvent;
import android.database.sqlite.SQLiteDatabase;

/** Real DEX fixture. Delays expose a host that acknowledges before callbacks return. */
public final class LifecycleActivity extends Activity {
    private static volatile int events;
    private static Thread owner;
    private static boolean wrongThread;
    private SQLiteDatabase database;
    private static void callback() { if (Thread.currentThread() != owner) wrongThread = true; }
    private static void delay() { try { Thread.sleep(100); } catch (InterruptedException e) { throw new RuntimeException(e); } }
    @Override public void onCreate(Bundle state) {
        super.onCreate(state); owner = Thread.currentThread(); events |= 1;
        setContentView(new View(this) {
            @Override protected void onDraw(Canvas canvas) { canvas.drawColor(0xff2864a0); }
            @Override public boolean onTouchEvent(MotionEvent e) { callback(); if (e.getActionMasked() == MotionEvent.ACTION_UP) events |= 2; return true; }
        });
        getSharedPreferences("lifecycle", 0).edit().putInt("created", 1).apply();
        database = SQLiteDatabase.openOrCreateDatabase(new java.io.File(getFilesDir(), "lifecycle.db"), null);
        database.execSQL("CREATE TABLE lifecycle(value INTEGER)");
        database.execSQL("INSERT INTO lifecycle VALUES(1)");
        if ("sqlite-uncommitted".equals(System.getenv("HUSK_JAVA_CASE"))) {
            database.beginTransaction(); database.execSQL("INSERT INTO lifecycle VALUES(2)");
        }
    }
    @Override public boolean onKeyDown(int code, KeyEvent e) { callback(); events |= 4; return true; }
    @Override public void onPause() { callback(); delay(); events |= 8; super.onPause(); }
    @Override public void onResume() { callback(); events |= 16; super.onResume(); }
    @Override public void onDestroy() {
        callback(); delay();
        if ("destroy-failed".equals(System.getenv("HUSK_JAVA_CASE"))) throw new IllegalStateException("test onDestroy failure");
        events |= 32;
        getSharedPreferences("lifecycle", 0).edit().putInt("destroyed", 1).putInt("events", wrongThread ? -1 : events).apply();
        if ("live-thread".equals(System.getenv("HUSK_JAVA_CASE"))) {
            Thread t = new Thread(() -> { try { Thread.sleep(10000); } catch (InterruptedException e) {} }, "unfinished-fixture-worker");
            t.setDaemon(true); t.start();
        }
        super.onDestroy();
    }
    public static int result() { return wrongThread ? -1 : events; }
}
