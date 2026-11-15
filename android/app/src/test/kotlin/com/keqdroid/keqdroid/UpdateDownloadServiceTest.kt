package com.keqdroid.keqdroid

import android.app.Application
import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.content.pm.ServiceInfo
import com.keqdroid.keqdroid.RoboSession.context
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf

@RunWith(RobolectricTestRunner::class)
class UpdateDownloadServiceTest {

    @Before
    fun clean() = UpdateDownloadService.reset()

    private val manager get() = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun shown(id: Int): Notification? = shadowOf(manager).getNotification(id)

    private fun requested() {
        UpdateDownloadService.start(context, "Загрузка обновления", "Скачивается обновление 0.38.0")
    }

    private fun systemStarts(): UpdateDownloadService {
        val intent = shadowOf(context as Application).nextStartedService
        assertEquals(UpdateDownloadService::class.java.name, intent.component?.className)
        return Robolectric.buildService(UpdateDownloadService::class.java, intent)
            .create()
            .startCommand(0, 1)
            .get()
    }

    @Test
    fun `while the update downloads the app stays in the foreground with a progress bar`() {
        requested()
        val service = systemStarts()

        val first = shadowOf(service).lastForegroundNotification
        assertEquals(UpdateNotices.PROGRESS_ID, shadowOf(service).lastForegroundNotificationId)
        assertEquals("Скачивается обновление 0.38.0", first.extras.getString(Notification.EXTRA_TITLE))
        assertTrue(first.extras.getBoolean(Notification.EXTRA_PROGRESS_INDETERMINATE))

        UpdateDownloadService.progress(context, 40)
        val updated = shown(UpdateNotices.PROGRESS_ID)!!
        assertEquals(40, updated.extras.getInt(Notification.EXTRA_PROGRESS))
        assertEquals("40%", updated.extras.getCharSequence(Notification.EXTRA_TEXT).toString())
        assertEquals(
            NotificationManager.IMPORTANCE_LOW,
            manager.getNotificationChannel(updated.channelId).importance,
        )
        assertEquals("Загрузка обновления", manager.getNotificationChannel(updated.channelId).name)
    }

    @Test
    fun `the end of the download takes the bar away and late progress does not bring it back`() {
        requested()
        val service = systemStarts()

        UpdateDownloadService.stop()
        UpdateDownloadService.progress(context, 90)

        assertTrue(shadowOf(service).isForegroundStopped)
        assertTrue(shadowOf(service).isStoppedBySelf)
        assertNull(shown(UpdateNotices.PROGRESS_ID))
    }

    @Test
    fun `a download that ends before the system starts the service leaves nothing behind`() {
        requested()
        UpdateDownloadService.stop()
        val service = systemStarts()

        assertTrue(shadowOf(service).isForegroundStopped)
        assertTrue(shadowOf(service).isStoppedBySelf)
        assertNull(shown(UpdateNotices.PROGRESS_ID))
    }

    @Test
    fun `the system time limit stops the service instead of crashing the app`() {
        requested()
        val service = systemStarts()

        service.onTimeout(1, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)

        assertTrue(shadowOf(service).isStoppedBySelf)
    }

    @Test
    fun `the finished notice opens the app, makes a sound and goes away on tap`() {
        UpdateNotices.result(
            context,
            "Обновления приложения",
            "Обновление 0.38.0 скачано",
            "Нажмите, чтобы установить",
        )

        val notice = shown(UpdateNotices.RESULT_ID)!!
        assertEquals("Обновление 0.38.0 скачано", notice.extras.getString(Notification.EXTRA_TITLE))
        assertEquals("Нажмите, чтобы установить", notice.extras.getCharSequence(Notification.EXTRA_TEXT).toString())
        assertNotEquals(0, notice.flags and Notification.FLAG_AUTO_CANCEL)
        val tap = shadowOf(notice.contentIntent)
        assertTrue(tap.isActivity)
        assertEquals(MainActivity::class.java.name, tap.savedIntent.component?.className)
        val channel = manager.getNotificationChannel(notice.channelId)
        assertEquals(NotificationManager.IMPORTANCE_DEFAULT, channel.importance)
        assertEquals("Обновления приложения", channel.name)

        UpdateNotices.cancelResult(context)
        assertNull(shown(UpdateNotices.RESULT_ID))
    }
}
