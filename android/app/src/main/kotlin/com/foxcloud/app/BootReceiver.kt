package com.foxcloud.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Re-schedules the notification polling worker after the device reboots.
 * Requires RECEIVE_BOOT_COMPLETED permission (already declared in manifest).
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action == Intent.ACTION_BOOT_COMPLETED) {
            Log.d("BootReceiver", "Device booted — FCM handles notifications")
            // FCM handles push notifications now, no WorkManager/service needed
        }
    }
}
