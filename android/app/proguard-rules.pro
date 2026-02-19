
-keep class com.foxcloud.app.models.**{ *; }

# WorkManager notification worker
-keep class com.foxcloud.app.NotificationWorker { *; }
-keep class com.foxcloud.app.BootReceiver { *; }
-keep class com.foxcloud.app.NotificationScheduler { *; }
-keep class com.foxcloud.app.NotificationPollService { *; }
