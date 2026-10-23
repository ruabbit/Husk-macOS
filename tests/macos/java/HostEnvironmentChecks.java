// SPDX-License-Identifier: GPL-2.0-or-later
package org.husk.lifecycle;

import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.BatteryManager;
import android.os.Build;
import android.text.format.DateFormat;
import java.util.Locale;
import java.util.TimeZone;

final class HostEnvironmentChecks {
    private static void check(boolean ok, String why) { if (!ok) throw new IllegalStateException(why); }
    private static String property(String key) throws Exception {
        return (String)Class.forName("android.os.SystemProperties").getMethod("get", String.class).invoke(null, key);
    }
    static void run(Context context) {
        try {
            BatteryManager manager = (BatteryManager)context.getSystemService(Context.BATTERY_SERVICE);
            Intent battery = context.registerReceiver(null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
            check(manager != null && battery != null, "battery manager and sticky snapshot");
            int level = battery.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
            int status = battery.getIntExtra(BatteryManager.EXTRA_STATUS, -1);
            check(level >= 0 && level <= 100 && battery.getIntExtra(BatteryManager.EXTRA_SCALE, 0) == 100, "battery capacity units");
            check(status >= 1 && status <= 5, "battery status");
            check(Math.abs(manager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) - level) <= 1, "native battery property agrees with sticky capacity");
            if (!battery.getBooleanExtra(BatteryManager.EXTRA_PRESENT, true)) {
                check(level == 100 && battery.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) == 1 && manager.isCharging(), "desktop AC without invented battery");
                check("".equals(battery.getStringExtra(BatteryManager.EXTRA_TECHNOLOGY)), "absent battery has no chemistry");
            }
            check(TimeZone.getDefault().getID().equals(property("persist.sys.timezone")), "time zone mismatch: Java=" + TimeZone.getDefault().getID() + " native=" + property("persist.sys.timezone"));
            TimeZone.setDefault(TimeZone.getTimeZone("GMT"));
            check(TimeZone.getDefault().getID().equals("GMT"), "guest may override its default time zone");
            TimeZone.setDefault(null);
            check(TimeZone.getDefault().getID().equals(property("persist.sys.timezone")), "clearing guest override restores host time zone");
            check(Locale.getDefault().toLanguageTag().equals(property("persist.sys.locale")), "locale mismatch: Java=" + Locale.getDefault().toLanguageTag() + " native=" + property("persist.sys.locale"));
            check(property("ro.product.locale").equals(property("persist.sys.locale")), "locale aliases agree");
            check(Build.FINGERPRINT.equals(property("ro.vendor.build.fingerprint")), "Java and native identity agree");
            String pattern = ((java.text.SimpleDateFormat)DateFormat.getTimeFormat(context)).toPattern();
            check(pattern.equals(DateFormat.is24HourFormat(context) ? "HH:mm" : "h:mm a"), "clock preference reaches formatter");
            context.getSharedPreferences("lifecycle", 0).edit().putBoolean("host_environment", true)
                .putString("host_locale", Locale.getDefault().toLanguageTag()).putString("host_timezone", TimeZone.getDefault().getID()).commit();
            System.out.println("HUSK_GUEST_STDOUT_MARKER " + Locale.getDefault().toLanguageTag() + " / " + TimeZone.getDefault().getID());
            System.out.println("{\"event\":\"guest-print\"}");
            System.err.println("HUSK_GUEST_STDERR_MARKER");
        } catch (Exception e) { throw new IllegalStateException("host environment", e); }
    }
}
