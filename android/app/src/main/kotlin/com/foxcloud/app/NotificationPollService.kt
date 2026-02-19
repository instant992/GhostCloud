package com.foxcloud.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Persistent foreground service that polls the server for new push
 * notifications every 3 minutes and shows them in the notification shade.
 *
 * Unlike WorkManager (min 15 min, often delayed by Doze/OEM),
 * a foreground service survives app swipe-away and runs reliably.
 *
 * Uses IMPORTANCE_MIN channel so the persistent notification is silent
 * and barely visible.
 */
class NotificationPollService : Service() {

    companion object {
        private const val TAG = "NotifPollService"

        /** Notification channel for the persistent foreground notification. */
        const val POLL_CHANNEL_ID = "GhostCloud_Background"

        /** ID for the foreground service notification. */
        const val POLL_FOREGROUND_ID = 3

        /** Polling interval — 3 minutes. */
        private const val POLL_INTERVAL_MS = 3L * 60 * 1000

        // SharedPreferences keys (Flutter shared_preferences format)
        private const val FLUTTER_PREFS = "FlutterSharedPreferences"
        private const val KEY_SUB_URL = "flutter.fox_subscription_url"
        private const val KEY_LAST_ID = "flutter.push_notification_last_id"

        private const val BASE_URL = "https://vpnghost.space"

        /** Start the service (call from Activity/Application context). */
        fun start(context: Context) {
            val intent = Intent(context, NotificationPollService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Cannot start service: ${e.message}")
            }
        }
    }

    private val job = SupervisorJob()
    private val scope = CoroutineScope(Dispatchers.IO + job)

    // ---------------------------------------------------------------
    // Service lifecycle
    // ---------------------------------------------------------------

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "onCreate")
        createPollChannel()
        try {
            startForeground(POLL_FOREGROUND_ID, buildForegroundNotification())
        } catch (e: Exception) {
            // Android 12+ may throw ForegroundServiceStartNotAllowedException
            // if started from background without valid exemption.
            Log.e(TAG, "startForeground failed", e)
            stopSelf()
            return
        }
        startPolling()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // START_STICKY: Android will restart this service if killed.
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // When user swipes the app away — schedule WorkManager one-time
        // check as backup (foreground service itself should survive swipe,
        // but some OEMs kill it).
        Log.d(TAG, "onTaskRemoved — scheduling backup WorkManager check")
        NotificationScheduler.scheduleOneTime(this)
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        Log.d(TAG, "onDestroy")
        job.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ---------------------------------------------------------------
    // Foreground notification (silent, minimal)
    // ---------------------------------------------------------------

    private fun createPollChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                POLL_CHANNEL_ID,
                "Фоновая проверка",
                NotificationManager.IMPORTANCE_MIN       // silent, no popup
            ).apply {
                description = "Проверка новых уведомлений"
                setShowBadge(false)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildForegroundNotification(): Notification {
        // Tap opens the app
        val openIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pi = PendingIntent.getActivity(
            this, 0, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, POLL_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic)
            .setContentTitle("GhostCloud")
            .setContentText("Работает в фоне")
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setSilent(true)
            .setOngoing(true)
            .setContentIntent(pi)
            .build()
    }

    // ---------------------------------------------------------------
    // Polling logic
    // ---------------------------------------------------------------

    private fun startPolling() {
        scope.launch {
            // Small initial delay so app finishes starting first
            delay(30_000)

            while (isActive) {
                try {
                    pollNotifications()
                } catch (e: Exception) {
                    Log.e(TAG, "Poll error: ${e.message}")
                }
                delay(POLL_INTERVAL_MS)
            }
        }
    }

    private fun pollNotifications() {
        val prefs = getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
        val subUrl = prefs.getString(KEY_SUB_URL, null)
        if (subUrl.isNullOrEmpty()) {
            Log.d(TAG, "No subscription URL, skipping")
            return
        }

        val lastId = prefs.getLong(KEY_LAST_ID, 0L)
        Log.d(TAG, "Polling after id=$lastId")

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
                return
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
                            showPushNotification(id.toInt(), title, message)
                        }
                        if (id > maxId) maxId = id
                    }

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
    }

    private fun showPushNotification(notifId: Int, title: String, message: String) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Ensure push channel exists (high-importance, with sound)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                GlobalState.SUBSCRIPTION_NOTIFICATION_CHANNEL,
                "Subscription Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Уведомления о подписке и сервисе"
                enableVibration(true)
            }
            nm.createNotificationChannel(channel)
        }

        val openIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pi = PendingIntent.getActivity(
            this, notifId, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, GlobalState.SUBSCRIPTION_NOTIFICATION_CHANNEL)
            .setSmallIcon(R.drawable.ic)
            .setContentTitle(title)
            .setContentText(message)
            .setStyle(NotificationCompat.BigTextStyle().bigText(message))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pi)
            .build()

        nm.notify(100 + notifId, notification)
    }
}
