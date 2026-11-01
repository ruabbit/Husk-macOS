package husk;

import android.app.Service;
import android.content.*;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import java.util.HashMap;

/** The app's own services (started and bound in this process, as on Android) and the system services Husk answers for. */
public final class Services {
    private static final HashMap<String, Service> sRunning = new HashMap<>();
    private static final HashMap<ServiceConnection, String> sBound = new HashMap<>();
    private Services() {}
    private static Manifest.Component find(Intent i) {
        if (i.getComponent() != null) { for (Manifest.Component c : Manifest.services) if (c.name.equals(i.getComponent().getClassName())) return c; }
        if (i.getAction() != null) for (Manifest.Component c : Manifest.services) for (Manifest.Filter f : c.filters) if (f.actions.contains(i.getAction())) return c;
        return null;
    }
    private static Service create(Manifest.Component c) throws Exception {
        Service s = sRunning.get(c.name);
        if (s == null) {
            s = (Service) Class.forName(c.name, true, AppRunner.classLoader()).newInstance();
            s.huskAttach(AppRunner.application() != null ? AppRunner.application() : ContextImpl.app());
            sRunning.put(c.name, s);
            s.onCreate();
        }
        return s;
    }
    public static ComponentName start(Context from, Intent i) {
        if (!AppRunner.acceptsNewWork()) return null;
        Manifest.Component c = find(i);
        if (c == null) return null;
        new Handler(Looper.getMainLooper()).post(() -> {
            if (!AppRunner.acceptsNewWork()) return;
            try { Service s = create(c); s.onStartCommand(i, 0, 1); } catch (Throwable t) { android.util.Log.e("Husk", "service " + c.name + " failed", t); }
        });
        return new ComponentName(Native.packageName(), c.name);
    }
    public static boolean stop(Intent i) {
        Manifest.Component c = find(i);
        if (c == null) return false;
        Service s = sRunning.remove(c.name);
        if (s != null) s.onDestroy();
        return s != null;
    }
    public static void stopSelf(Service s) { String k = null; for (java.util.Map.Entry<String, Service> e : sRunning.entrySet()) if (e.getValue() == s) k = e.getKey(); if (k != null) { sRunning.remove(k); s.onDestroy(); } }
    public static boolean bind(Context from, Intent i, ServiceConnection conn) {
        if (!AppRunner.acceptsNewWork()) return false;
        final IBinder play = PlayStore.bind(i);
        if (play != null) {
            final ComponentName cn = new ComponentName(GooglePackages.VENDING, i.getAction());
            new Handler(Looper.getMainLooper()).post(() -> { if (AppRunner.acceptsNewWork()) conn.onServiceConnected(cn, play); });
            return true;
        }
        Manifest.Component c = find(i);
        if (c == null) return false;
        new Handler(Looper.getMainLooper()).post(() -> {
            if (!AppRunner.acceptsNewWork()) return;
            try {
                Service s = create(c);
                IBinder b = s.onBind(i);
                sBound.put(conn, c.name);
                ComponentName cn = new ComponentName(Native.packageName(), c.name);
                if (b != null) conn.onServiceConnected(cn, b); else conn.onNullBinding(cn);
            } catch (Throwable t) { android.util.Log.e("Husk", "binding " + c.name + " failed", t); }
        });
        return true;
    }
    public static void unbind(ServiceConnection conn) { sBound.remove(conn); }
    static void finishForHost() {
        java.util.ArrayList<Job> jobs;
        synchronized (sJobs) { jobs = new java.util.ArrayList<>(sJobs.values()); jobs.addAll(sRetiring); sJobs.clear(); sRetiring.clear(); }
        for (Job job : jobs) stopJob(job);
        for (Service service : new java.util.ArrayList<>(sRunning.values())) service.onDestroy();
        sRunning.clear(); sBound.clear();
    }
    private static final HashMap<Integer, Job> sJobs = new HashMap<>();
    private static final java.util.ArrayList<Job> sRetiring = new java.util.ArrayList<>();
    private static final class Job {
        android.app.job.JobInfo info;
        android.app.job.JobService service;
        android.app.job.JobParameters params;
    }
    /** Bounded foreground subset: no Android background scheduler or persistence. */
    public static int scheduleJob(android.app.job.JobInfo info) {
        if (info == null || info.getService() == null) throw new IllegalArgumentException("missing JobService");
        if (!AppRunner.acceptsNewWork() || !info.huskCanRun()) return android.app.job.JobScheduler.RESULT_FAILURE;
        Manifest.Component found = null;
        if (Native.packageName().equals(info.getService().getPackageName()))
            for (Manifest.Component c : Manifest.services)
                if (c.name.equals(info.getService().getClassName()) && c.enabled) { found = c; break; }
        if (found == null) throw new IllegalArgumentException("JobService is absent or disabled");
        final Manifest.Component component = found;
        final Job job = new Job(); job.info = info;
        final Job previous;
        synchronized (sJobs) { previous = sJobs.put(info.getId(), job); if (previous != null) sRetiring.add(previous); }
        new Handler(Looper.getMainLooper()).post(() -> {
            stopJob(previous);
            synchronized (sJobs) { if (sJobs.get(info.getId()) != job || !AppRunner.acceptsNewWork()) return; }
            try {
                Service service = create(component);
                if (!(service instanceof android.app.job.JobService)) throw new IllegalArgumentException("not a JobService");
                job.service = (android.app.job.JobService)service;
                job.params = new android.app.job.JobParameters();
                job.params.huskJobId = info.getId(); job.params.huskExtras = info.getExtras();
                if (!job.service.onStartJob(job.params)) finishJob(job.params, false);
            } catch (Exception e) {
                synchronized (sJobs) { if (sJobs.get(info.getId()) == job) sJobs.remove(info.getId()); }
                throw new RuntimeException("JobService failed", e);
            }
        });
        return android.app.job.JobScheduler.RESULT_SUCCESS;
    }
    private static void stopJob(Job job) {
        android.app.job.JobService service;
        synchronized (sJobs) {
            sRetiring.remove(job);
            if (job == null || job.service == null || job.params == null) return;
            service = job.service; job.service = null;
        }
        if (service.onStopJob(job.params)) android.util.Log.w("Husk", "Background JobScheduler rescheduling is unavailable");
    }
    public static void cancelJob(int id) {
        final Job job;
        synchronized (sJobs) { job = sJobs.remove(id); if (job != null) sRetiring.add(job); }
        if (job != null) new Handler(Looper.getMainLooper()).post(() -> stopJob(job));
    }
    public static void cancelJobs() {
        java.util.ArrayList<Integer> ids;
        synchronized (sJobs) { ids = new java.util.ArrayList<>(sJobs.keySet()); }
        for (Integer id : ids) cancelJob(id);
    }
    public static java.util.List<android.app.job.JobInfo> pendingJobs() {
        java.util.ArrayList<android.app.job.JobInfo> result = new java.util.ArrayList<>();
        synchronized (sJobs) { for (Job job : sJobs.values()) result.add(job.info); }
        return result;
    }
    public static void finishJob(android.app.job.JobParameters params, boolean reschedule) {
        if (params == null) return;
        synchronized (sJobs) {
            Job job = sJobs.get(params.getJobId());
            if (job != null && job.params == params) { sJobs.remove(params.getJobId()); job.service = null; }
        }
        if (reschedule) android.util.Log.w("Husk", "Background JobScheduler rescheduling is unavailable");
    }

    /** A system service by name, or null for those Husk has nothing for. */
    public static Object system(String name, Context c) {
        switch (name) {
        case Context.AUDIO_SERVICE: return new android.media.AudioManager();
        case Context.VIBRATOR_SERVICE: return new android.os.Vibrator();
        case Context.VIBRATOR_MANAGER_SERVICE: return new android.os.VibratorManager();
        case Context.CLIPBOARD_SERVICE: return new ClipboardManager();
        case Context.INPUT_METHOD_SERVICE: return new android.view.inputmethod.InputMethodManager();
        case Context.SENSOR_SERVICE: return new android.hardware.SensorManager();
        case Context.POWER_SERVICE: return new android.os.PowerManager();
        case Context.ACTIVITY_SERVICE: return new android.app.ActivityManager();
        case Context.CONNECTIVITY_SERVICE: return new android.net.ConnectivityManager();
        case Context.NOTIFICATION_SERVICE: return new android.app.NotificationManager();
        case Context.ALARM_SERVICE: return new android.app.AlarmManager();
        case Context.ACCESSIBILITY_SERVICE: return new android.view.accessibility.AccessibilityManager();
        case Context.UI_MODE_SERVICE: return new android.app.UiModeManager();
        case Context.DISPLAY_SERVICE: return new android.hardware.display.DisplayManager();
        case Context.KEYGUARD_SERVICE: return new android.app.KeyguardManager();
        case Context.USER_SERVICE: return new android.os.UserManager();
        case Context.BATTERY_SERVICE: return new android.os.BatteryManager();
        case Context.STORAGE_SERVICE: return new android.os.storage.StorageManager();
        case Context.TELEPHONY_SERVICE: return new android.telephony.TelephonyManager();
        case Context.JOB_SCHEDULER_SERVICE: return new android.app.job.JobScheduler.Impl();
        case Context.APP_OPS_SERVICE: return new android.app.AppOpsManager();
        case Context.INPUT_SERVICE: return new android.hardware.input.InputManager();
        case Context.WIFI_SERVICE: return new android.net.wifi.WifiManager(c, null);
        case Context.LOCATION_SERVICE: return new android.location.LocationManager(c, null);
        default: return null;
        }
    }
}
