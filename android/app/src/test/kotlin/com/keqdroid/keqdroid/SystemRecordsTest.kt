package com.keqdroid.keqdroid

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.ComponentName
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.net.Uri
import android.provider.Settings
import com.keqdroid.keqdroid.RoboSession.context
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.shadows.ShadowActivityManager.ApplicationExitInfoBuilder
import org.robolectric.shadows.ShadowBuild
import java.util.TimeZone

@RunWith(RobolectricTestRunner::class)
class SystemRecordsTest {
    private lateinit var zone: TimeZone

    @Before
    fun utc() {
        zone = TimeZone.getDefault()
        TimeZone.setDefault(TimeZone.getTimeZone("UTC"))
    }

    @After
    fun restoreZone() = TimeZone.setDefault(zone)

    private fun exit(reason: Int, status: Int, summary: ByteArray?, description: String?) {
        val am = context.getSystemService(ActivityManager::class.java)
        shadowOf(am).addApplicationExitInfo(
            ApplicationExitInfoBuilder.newBuilder()
                .setProcessName(context.packageName)
                .setReason(reason)
                .setStatus(status)
                .setTimestamp(1_794_484_800_000L)
                .setDescription(description)
                .setProcessStateSummary(summary)
                .build(),
        )
    }

    @Test
    fun `how the app was killed is reported with the VPN status of that moment`() {
        exit(ApplicationExitInfo.REASON_LOW_MEMORY, 0, ProcessExits.vpnSummary("connected"), "lmkd")
        val record = ProcessExits.recent(context).single()
        assertEquals("LOW_MEMORY", record["reasonName"])
        assertEquals("connected", record["vpnStatus"])
        assertEquals("lmkd", record["description"])
        assertEquals("2026-11-12 12:00:00, LOW_MEMORY, status 0, VPN connected, \"lmkd\"", ProcessExits.describeLast(context))
    }

    @Test
    fun `a kill before any VPN session has no VPN status`() {
        exit(ApplicationExitInfo.REASON_SIGNALED, 9, null, null)
        assertNull(ProcessExits.recent(context).single()["vpnStatus"])
        assertEquals("2026-11-12 12:00:00, SIGNALED, status 9", ProcessExits.describeLast(context))
    }

    @Test
    fun `no exit records means nothing to say`() {
        assertEquals(emptyList<Map<String, Any?>>(), ProcessExits.recent(context))
        assertNull(ProcessExits.describeLast(context))
    }

    private fun install(pkg: String, cls: String, exported: Boolean) {
        val pm = shadowOf(context.packageManager)
        pm.installPackage(PackageInfo().apply {
            packageName = pkg
            applicationInfo = ApplicationInfo().apply { packageName = pkg }
        })
        pm.addOrUpdateActivity(ActivityInfo().apply {
            packageName = pkg
            name = cls
            this.exported = exported
            applicationInfo = ApplicationInfo().apply { packageName = pkg }
        })
    }

    private fun brand(name: String) {
        ShadowBuild.setBrand(name)
        ShadowBuild.setManufacturer(name)
    }

    private val miui = "com.miui.securitycenter"
    private val miuiScreen = "com.miui.permcenter.autostart.AutoStartManagementActivity"

    @Test
    fun `phones without an autostart setting get no autostart button`() {
        brand("google")
        assertEquals(OemAutostart.KIND_NONE, OemAutostart.kind(context))
    }

    @Test
    fun `an open vendor screen is offered and opened directly`() {
        brand("Xiaomi")
        install(miui, miuiScreen, exported = true)
        assertEquals(OemAutostart.KIND_SCREEN, OemAutostart.kind(context))
        OemAutostart.open(context)
        val opened = shadowOf(context as android.app.Application).nextStartedActivity
        assertEquals(ComponentName(miui, miuiScreen), opened.component)
        assertTrue(opened.flags and Intent.FLAG_ACTIVITY_NEW_TASK != 0)
    }

    @Test
    fun `a vendor screen closed to other apps sends the person to app details`() {
        brand("Xiaomi")
        install(miui, miuiScreen, exported = false)
        assertEquals(OemAutostart.KIND_APP_DETAILS, OemAutostart.kind(context))
        OemAutostart.open(context)
        val opened = shadowOf(context as android.app.Application).nextStartedActivity
        assertEquals(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, opened.action)
        assertEquals(Uri.fromParts("package", context.packageName, null), opened.data)
    }

    @Test
    fun `a known vendor without the screen installed also gets app details`() {
        brand("vivo")
        assertEquals(OemAutostart.KIND_APP_DETAILS, OemAutostart.kind(context))
    }
}
