// SPDX-License-Identifier: GPL-2.0-or-later
package org.husk.lifecycle;

import android.app.Activity;
import android.os.Bundle;
import android.graphics.Canvas;
import android.view.View;
import android.view.MotionEvent;
import android.view.KeyEvent;
import android.view.InputDevice;
import android.hardware.input.InputManager;
import android.database.sqlite.SQLiteDatabase;

/** Real DEX fixture. Delays expose a host that acknowledges before callbacks return. */
public final class LifecycleActivity extends Activity {
    private static volatile int events;
    private static Thread owner;
    private static boolean wrongThread;
    private static volatile int controllerEvents, controllerErrors, heldButtons;
    private static boolean neutral = true, paused;
    private SQLiteDatabase database;
    private static void callback() { if (Thread.currentThread() != owner) wrongThread = true; }
    private static void delay() { try { Thread.sleep(100); } catch (InterruptedException e) { throw new RuntimeException(e); } }
    @Override public void onCreate(Bundle state) {
        super.onCreate(state); owner = Thread.currentThread(); events |= 1;
        View view = new View(this) {
            @Override protected void onDraw(Canvas canvas) { canvas.drawColor(0xff2864a0); }
            @Override public boolean onTouchEvent(MotionEvent e) { callback(); if (e.getActionMasked() == MotionEvent.ACTION_UP) events |= 2; return true; }
            @Override public boolean onGenericMotionEvent(MotionEvent e) {
                callback();
                if (!e.isFromSource(InputDevice.SOURCE_JOYSTICK)) return false;
                if (paused || e.getDeviceId() != 41 || e.getAction() != MotionEvent.ACTION_MOVE) controllerErrors++;
                MotionEvent copy = MotionEvent.obtain(e);
                MotionEvent.PointerCoords coords = new MotionEvent.PointerCoords(); copy.getPointerCoords(0, coords);
                if (copy.getDeviceId() != e.getDeviceId() || copy.getSource() != e.getSource() ||
                    copy.getAxisValue(MotionEvent.AXIS_RZ) != e.getAxisValue(MotionEvent.AXIS_RZ) ||
                    coords.getAxisValue(MotionEvent.AXIS_LTRIGGER) != e.getAxisValue(MotionEvent.AXIS_LTRIGGER)) controllerErrors++;
                neutral = e.getAxisValue(MotionEvent.AXIS_X) == 0 && e.getAxisValue(MotionEvent.AXIS_LTRIGGER) == 0;
                if (neutral) controllerEvents |= 8;
                else if (e.getAxisValue(MotionEvent.AXIS_X) == .25f && e.getAxisValue(MotionEvent.AXIS_Y) == -.5f &&
                    e.getAxisValue(MotionEvent.AXIS_Z) == .75f && e.getAxisValue(MotionEvent.AXIS_RZ) == -.25f &&
                    e.getAxisValue(MotionEvent.AXIS_HAT_X) == 1f && e.getAxisValue(MotionEvent.AXIS_LTRIGGER) == .8f &&
                    e.getAxisValue(MotionEvent.AXIS_BRAKE) == .8f && e.getAxisValue(MotionEvent.AXIS_RTRIGGER) == .6f &&
                    e.getAxisValue(MotionEvent.AXIS_GAS) == .6f) controllerEvents |= 4;
                else controllerErrors++;
                return true;
            }
        };
        view.setFocusable(true); view.setFocusableInTouchMode(true); setContentView(view); view.requestFocus();
        ((InputManager)getSystemService(INPUT_SERVICE)).registerInputDeviceListener(new InputManager.InputDeviceListener() {
            public void onInputDeviceAdded(int id) { callback(); if (id == 41 || id == 42) controllerEvents |= 64; }
            public void onInputDeviceRemoved(int id) { callback(); if (id == 42) controllerEvents |= 128; }
            public void onInputDeviceChanged(int id) { callback(); }
        }, new android.os.Handler());
        getSharedPreferences("lifecycle", 0).edit().putInt("created", 1).apply();
        database = SQLiteDatabase.openOrCreateDatabase(new java.io.File(getFilesDir(), "lifecycle.db"), null);
        database.execSQL("CREATE TABLE lifecycle(value INTEGER)");
        database.execSQL("INSERT INTO lifecycle VALUES(1)");
        if ("sqlite-uncommitted".equals(System.getenv("HUSK_JAVA_CASE"))) {
            database.beginTransaction(); database.execSQL("INSERT INTO lifecycle VALUES(2)");
        }
    }
    @Override public boolean dispatchKeyEvent(KeyEvent e) {
        if (e.isFromSource(InputDevice.SOURCE_GAMEPAD)) {
            callback();
            if (paused || e.getDownTime() <= 0 || e.getEventTime() < e.getDownTime()) controllerErrors++;
            int code = e.getKeyCode(); boolean down = e.getAction() == KeyEvent.ACTION_DOWN;
            if (down) {
                InputDevice d = e.getDevice();
                if (d == null || d.getId() != e.getDeviceId() || !d.supportsSource(InputDevice.SOURCE_GAMEPAD) ||
                    d.getMotionRanges().size() != 10 || d.getMotionRange(MotionEvent.AXIS_LTRIGGER).getMin() != 0 ||
                    d.getMotionRange(MotionEvent.AXIS_X).getMin() != -1 || !d.hasKeys(KeyEvent.KEYCODE_BUTTON_A)[0]) controllerErrors++;
            }
            if (code == KeyEvent.KEYCODE_BUTTON_A && e.getDeviceId() == 41) { controllerEvents |= down ? 1 : 2; heldButtons += down ? 1 : -1; }
            if (code == KeyEvent.KEYCODE_BUTTON_B && e.getDeviceId() == 42) { controllerEvents |= down ? 16 : 32; heldButtons += down ? 1 : -1; }
            if (code == KeyEvent.KEYCODE_BUTTON_X) controllerErrors++;
            return true;
        }
        return super.dispatchKeyEvent(e);
    }
    @Override public boolean onKeyDown(int code, KeyEvent e) { callback(); events |= 4; return true; }
    @Override public void onPause() { callback(); delay(); if (heldButtons != 0 || !neutral) controllerErrors++; paused = true; events |= 8; super.onPause(); }
    @Override public void onResume() { callback(); paused = false; events |= 16; super.onResume(); }
    @Override public void onDestroy() {
        callback(); delay();
        if ("destroy-failed".equals(System.getenv("HUSK_JAVA_CASE"))) throw new IllegalStateException("test onDestroy failure");
        events |= 32;
        getSharedPreferences("lifecycle", 0).edit().putInt("destroyed", 1).putInt("events", wrongThread ? -1 : events).apply();
        getSharedPreferences("lifecycle", 0).edit().putInt("controller_events", controllerResult()).putInt("controller_held", heldButtons).apply();
        if ("live-thread".equals(System.getenv("HUSK_JAVA_CASE"))) {
            Thread t = new Thread(() -> { try { Thread.sleep(10000); } catch (InterruptedException e) {} }, "unfinished-fixture-worker");
            t.setDaemon(true); t.start();
        }
        super.onDestroy();
    }
    public static int result() { return wrongThread ? -1 : events; }
    public static int controllerResult() { return wrongThread || controllerErrors != 0 ? -1 : controllerEvents; }
    public static int controllerHeld() { return heldButtons; }
}
