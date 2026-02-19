package com.foxcloud.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Background worker that periodically polls the server for new push
 * notifications and displays them in the system notification shade.
 *
 * Runs via AndroidX WorkManager every ~15 minutes even when the app
 * is closed.
 */
class NotificationWorker(
    appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {

    companion object {
        private const val TAG = "NotificationWorker"
        const val WORK_NAME = "foxcloud_notification_poll"

        // Flutter SharedPreferences stores keys with "flutter." prefix
        // in a file called "FlutterSharedPreferences"
        private const val FLUTTER_PREFS = "FlutterSharedPreferences"
        private const val KEY_SUB_URL = "flutter.fox_subscription_url"
        private const val KEY_LAST_ID = "flutter.push_notification_last_id"

        // Server base URL (same as FoxConfig.authServerUrl without /api/auth)
        private const val BASE_URL = "https://vpnghost.space"
    }

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        try {
            Log.d(TAG, "Starting notification poll")

            val prefs = applicationContext.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            val subUrl = prefs.getString(KEY_SUB_URL, null)

            if (subUrl.isNullOrEmpty()) {
                Log.d(TAG, "No subscription URL, skipping")
                return@withContext Result.success()
            }

            // Flutter stores int via shared_preferences plugin as Long
            val lastId = prefs.getLong(KEY_LAST_ID, 0L)
            Log.d(TAG, "Polling notifications after id=$lastId")

            val url = URL("$BASE_URL/api/auth/mobile/notifications?after_id=$lastId")
            val conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "GET"
            conn.setRequestProperty("x-sub-url", subUrl)
            conn.connectTimeout = 15_000
            conn.readTimeout = 15_000

            try {
                val code = conn.responseCode
                if (code != 200) {
                    Log.w(TAG, "Server returned $code")
                    return@withContext Result.retry()
                }

                val body = conn.inputStream.bufferedReader().readText()
                val json = JSONObject(body)

                if (json.optBoolean("success", false)) {
                    val notifications = json.optJSONArray("notifications")
                    if (notifications != null && notifications.length() > 0) {
                        Log.d(TAG, "Got ${notifications.length()} new notification(s)")

                        var maxId = lastId
                        for (i in 0 until notifications.length()) {
                            val n = notifications.getJSONObject(i)
                            val id = n.optLong("id", 0)
                            val title = n.optString("title", "")
                            val message = n.optString("message", "")

                            if (title.isNotEmpty() || message.isNotEmpty()) {
                                showNotification(
                                    notificationId = id.toInt(),
                                    title = title,
                                    message = message
                                )
                            }

                            if (id > maxId) maxId = id
                        }

                        // Persist highest seen ID so we don't re-show
                        if (maxId > lastId) {
                            prefs.edit().putLong(KEY_LAST_ID, maxId).apply()
                            Log.d(TAG, "Updated last id to $maxId")
                        }
                    } else {
                        Log.d(TAG, "No new notifications")
                    }
                }
            } finally {
                conn.disconnect()
            }

            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "Error polling notifications", e)
            Result.retry()
        }
    }

    private fun showNotification(notificationId: Int, title: String, message: String) {
        val nm = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Create channel (Android O+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                GlobalState.SUBSCRIPTION_NOTIFICATION_CHANNEL,
                "Subscription Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifications about subscription and service"
                enableVibration(true)
            }
            nm.createNotificationChannel(channel)
        }

        // Open app on tap
        val openIntent = applicationContext.packageManager.getLaunchIntentForPackage(
            applicationContext.packageName
        )
        val pendingIntent = PendingIntent.getActivity(
            applicationContext,
            notificationId,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(
            applicationContext,
            GlobalState.SUBSCRIPTION_NOTIFICATION_CHANNEL
        )
            .setSmallIcon(R.drawable.ic)
            .setContentTitle(title)
            .setContentText(message)
            .setStyle(NotificationCompat.BigTextStyle().bigText(message))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        // Use unique notification IDs (base offset + server ID) to avoid overwriting
        nm.notify(100 + notificationId, notification)
    }
}
