package com.keqdroid.keqdroid

import android.app.Application
import android.content.Intent
import com.keqdroid.keqdroid.RoboSession.context
import com.keqdroid.keqdroid.RoboSession.prefs
import com.keqdroid.keqdroid.RoboSession.saveSnapshot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.shadows.ShadowVpnService

@RunWith(RobolectricTestRunner::class)
class SessionResumeReceiverTest {

    // Robolectric по умолчанию считает, что согласия на VPN нет
    @Before
    fun consentGiven() = ShadowVpnService.setPrepareResult(null)

    private fun wanted(on: Boolean) {
        prefs().edit().putBoolean(KeqdisVpnService.KEY_QS_SESSION_WANTED, on).commit()
    }

    private fun receive(action: String) = SessionResumeReceiver().onReceive(context, Intent(action))

    private fun started(): Intent? = shadowOf(context as Application).nextStartedService

    @Test
    fun `after an update the VPN that was on reconnects and says why in the core log`() {
        saveSnapshot()
        wanted(true)
        receive(Intent.ACTION_MY_PACKAGE_REPLACED)
        val start = started()!!
        assertEquals(KeqdisVpnService.ACTION_START, start.action)
        assertEquals(
            "the app was updated while the VPN was on, reconnecting",
            start.getStringExtra(KeqdisVpnService.EXTRA_LOG_NOTE),
        )
    }

    @Test
    fun `after a reboot a proxy-only session comes back without VPN consent`() {
        saveSnapshot(tunnelMode = KeqdisVpnService.TUNNEL_MODE_PROXY)
        wanted(true)
        ShadowVpnService.setPrepareResult(Intent("android.net.vpn.SETTINGS"))
        receive(Intent.ACTION_BOOT_COMPLETED)
        assertEquals(
            "the phone restarted while the VPN was on, reconnecting",
            started()!!.getStringExtra(KeqdisVpnService.EXTRA_LOG_NOTE),
        )
    }

    @Test
    fun `a VPN that was turned off stays off`() {
        saveSnapshot()
        wanted(false)
        receive(Intent.ACTION_BOOT_COMPLETED)
        assertNull(started())
    }

    @Test
    fun `a tunnel whose permission was taken away stays down`() {
        saveSnapshot()
        wanted(true)
        ShadowVpnService.setPrepareResult(Intent("android.net.vpn.SETTINGS"))
        receive(Intent.ACTION_BOOT_COMPLETED)
        assertNull(started())
    }

    @Test
    fun `without a saved server there is nothing to bring back`() {
        wanted(true)
        receive(Intent.ACTION_MY_PACKAGE_REPLACED)
        assertNull(started())
    }

    @Test
    fun `other broadcasts are ignored`() {
        saveSnapshot()
        wanted(true)
        receive(Intent.ACTION_TIME_CHANGED)
        assertNull(started())
    }
}
