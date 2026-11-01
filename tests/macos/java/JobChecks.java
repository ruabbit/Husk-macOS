// SPDX-License-Identifier: GPL-2.0-or-later
package org.husk.lifecycle;

import android.app.Activity;
import android.app.job.*;
import android.content.ComponentName;
import android.os.*;

/** Foreground scheduling on the real AppMain, including the host teardown. */
public final class JobChecks {
    private static volatile int started, stopped, completed;
    private static Activity activity;
    private static Thread main;
    private static JobScheduler scheduler;
    private static void check(boolean value) { if (!value) throw new IllegalStateException("JobScheduler lifecycle"); }
    private static JobInfo job(int id, int value) {
        PersistableBundle extras = new PersistableBundle(); extras.putInt("value", value);
        return new JobInfo.Builder(id, new ComponentName(activity, Worker.class)).setExtras(extras).build();
    }
    public static void start(Activity owner) {
        activity = owner; main = Thread.currentThread();
        scheduler = (JobScheduler)owner.getSystemService(android.content.Context.JOB_SCHEDULER_SERVICE);
        check(scheduler.schedule(job(1, 1)) == JobScheduler.RESULT_SUCCESS); scheduler.cancel(1);
        check(scheduler.schedule(job(2, 1)) == JobScheduler.RESULT_SUCCESS);
        check(scheduler.schedule(job(2, 2)) == JobScheduler.RESULT_SUCCESS);
        check(scheduler.schedule(job(3, 3)) == JobScheduler.RESULT_SUCCESS);
        check(scheduler.schedule(new JobInfo.Builder(4, new ComponentName(owner, Worker.class))
            .setRequiresCharging(true).build()) == JobScheduler.RESULT_FAILURE);
        try { scheduler.schedule(new JobInfo.Builder(9, new ComponentName(owner.getPackageName(), "MissingJob")).build());
            throw new IllegalStateException("undeclared job accepted");
        } catch (IllegalArgumentException expected) {}
        new Handler(Looper.getMainLooper()).post(() -> {
            check(started == 12 && scheduler.getPendingJob(2) == null);
            scheduler.cancel(3);
            check(scheduler.schedule(job(5, 5)) == JobScheduler.RESULT_SUCCESS);
            new Handler(Looper.getMainLooper()).post(() -> {
                check(started == 44 && stopped == 8); completed = 1;
            });
        });
    }
    public static void activityDestroy() {
        check(completed == 1);
        check(scheduler.schedule(job(6, 6)) == JobScheduler.RESULT_FAILURE);
    }
    public static int result() { return completed; }
    public static final class Worker extends JobService {
        @Override public boolean onStartJob(JobParameters params) {
            check(Thread.currentThread() == main);
            int id = params.getJobId();
            check(id == 2 || id == 3 || id == 5);
            check(params.getExtras().getInt("value") == id);
            started |= 1 << id;
            if (id == 2) { jobFinished(params, false); return false; }
            return true;
        }
        @Override public boolean onStopJob(JobParameters params) {
            check(Thread.currentThread() == main); stopped |= 1 << params.getJobId(); return false;
        }
        @Override public void onDestroy() {
            check(Thread.currentThread() == main && started == 44 && stopped == 40 && completed == 1);
            check(scheduler.getAllPendingJobs().isEmpty());
            check(getSharedPreferences("lifecycle", 0).edit().putBoolean("jobs_closed", true).commit());
            completed = 2; super.onDestroy();
        }
    }
}
