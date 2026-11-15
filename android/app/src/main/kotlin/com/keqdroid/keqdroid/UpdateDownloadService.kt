package com.keqdroid.keqdroid

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.annotation.VisibleForTesting
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

// свёрнутое приложение без VPN Android 14 через 10 с замораживает и рвёт ему сокеты:
// служба держит процесс, пока Dart качает обновление
class UpdateDownloadService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            ServiceCompat.startForeground(
                this,
                UpdateNotices.PROGRESS_ID,
                UpdateNotices.progress(this, title, percent),
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                } else {
                    0
                },
            )
        } catch (e: Exception) {
            NativeLog.e("KEQDIS", "update download could not run in the foreground: $e")
            stopSelf(startId)
            return START_NOT_STICKY
        }
        running = this
        // загрузка могла кончиться раньше, чем система запустила службу
        if (!wanted) shutDown()
        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int, fgsType: Int) = shutDown()

    override fun onDestroy() {
        if (running === this) running = null
        super.onDestroy()
    }

    private fun shutDown() {
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    companion object {
        private var wanted = false
        private var running: UpdateDownloadService? = null
        private var title = ""
        private var percent = -1

        fun start(context: Context, channelName: String, title: String) {
            this.title = title
            percent = -1
            wanted = true
            UpdateNotices.progressChannel(context, channelName)
            try {
                ContextCompat.startForegroundService(
                    context,
                    Intent(context, UpdateDownloadService::class.java),
                )
            } catch (e: Exception) {
                wanted = false
                NativeLog.e("KEQDIS", "update download service refused: $e")
            }
        }

        fun progress(context: Context, value: Int) {
            percent = value
            // после stop уведомление уже снято, notify вернул бы его обычным и вечным
            if (!wanted || running == null) return
            UpdateNotices.manager(context)
                .notify(UpdateNotices.PROGRESS_ID, UpdateNotices.progress(context, title, value))
        }

        fun stop() {
            wanted = false
            running?.shutDown()
        }

        @VisibleForTesting
        internal fun reset() {
            wanted = false
            running = null
            title = ""
            percent = -1
        }
    }
}

object UpdateNotices {
    const val PROGRESS_ID = 4101
    const val RESULT_ID = 4102
    private const val PROGRESS_CHANNEL = "keqdroid_update_download"
    private const val RESULT_CHANNEL = "keqdroid_update_result"

    fun manager(context: Context) =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    fun progressChannel(context: Context, name: String) =
        channel(context, PROGRESS_CHANNEL, name, NotificationManager.IMPORTANCE_LOW)

    private fun channel(context: Context, id: String, name: String, importance: Int) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        manager(context).createNotificationChannel(
            NotificationChannel(id, name, importance).apply { setShowBadge(false) }
        )
    }

    private fun openApp(context: Context): PendingIntent = PendingIntent.getActivity(
        context,
        40,
        Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        },
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    fun progress(context: Context, title: String, percent: Int): Notification =
        NotificationCompat.Builder(context, PROGRESS_CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .apply { if (percent >= 0) setContentText("$percent%") }
            .setProgress(100, percent.coerceIn(0, 100), percent < 0)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setContentIntent(openApp(context))
            .build()

    // установщик открывает само приложение, когда вернётся на экран: из фона Android его не покажет
    fun result(context: Context, channelName: String, title: String, text: String) {
        channel(context, RESULT_CHANNEL, channelName, NotificationManager.IMPORTANCE_DEFAULT)
        manager(context).notify(
            RESULT_ID,
            NotificationCompat.Builder(context, RESULT_CHANNEL)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(title)
                .setContentText(text)
                .setAutoCancel(true)
                .setContentIntent(openApp(context))
                .build(),
        )
    }

    fun cancelResult(context: Context) = manager(context).cancel(RESULT_ID)
}
