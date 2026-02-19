package com.foxcloud.app

import android.content.Context
import android.util.Log
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

/**
 * Schedules background notification checking via:
 * 1) Foreground service (primary — polls every 3 min, survives swipe)
 * 2) WorkManager periodic (backup — every 15 min, in case service is killed)
 */
object NotificationScheduler {
    private const val TAG = "NotificationScheduler"

    /** Schedule both foreground service and periodic WorkManager backup. */
    fun schedule(context: Context) {
        Log.d(TAG, "Scheduling notification polling")

        // 1. Start foreground service (primary mechanism)
        NotificationPollService.start(context)

        // 2. WorkManager as a backup (every 15 min)
        schedulePeriodicWork(context)

        Log.d(TAG, "Notification polling scheduled")
    }

    /** Schedule a one-time immediate check (used from onTaskRemoved). */
    fun scheduleOneTime(context: Context) {
        Log.d(TAG, "Scheduling one-time notification check")
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()

        val request = OneTimeWorkRequestBuilder<NotificationWorker>()
            .setConstraints(constraints)
            .build()

        WorkManager.getInstance(context).enqueue(request)
    }

    private fun schedulePeriodicWork(context: Context) {
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()

        val request = PeriodicWorkRequestBuilder<NotificationWorker>(
            15, TimeUnit.MINUTES          // minimum interval for periodic work
        )
            .setConstraints(constraints)
            .setInitialDelay(1, TimeUnit.MINUTES)
            .build()

        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            NotificationWorker.WORK_NAME,
            ExistingPeriodicWorkPolicy.KEEP,
            request
        )
    }
}
