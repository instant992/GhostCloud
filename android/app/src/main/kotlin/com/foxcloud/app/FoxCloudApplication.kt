package com.foxcloud.app;

import android.app.Application
import android.content.Context

class FoxCloudApplication : Application() {
    companion object {
        private lateinit var instance: FoxCloudApplication
        fun getAppContext(): Context {
            return instance.applicationContext
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this

        // FCM handles push notifications now — no need for polling service
    }
}