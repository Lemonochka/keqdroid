package com.keqdroid.keqdroid

import android.content.Intent
import android.os.Build
import com.keqdroid.keqdroid.QuickConnect.Tap
import com.keqdroid.keqdroid.RoboSession.context
import com.keqdroid.keqdroid.RoboSession.prefs
import com.keqdroid.keqdroid.RoboSession.saveSnapshot
import com.keqdroid.keqdroid.RoboSession.setLiveStatus
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.shadows.ShadowVpnService

@RunWith(RobolectricTestRunner::class)
class QuickConnectDecideTest {

    // Robolectric по умолчанию считает, что согласия на VPN нет
    @Before
    fun consentGiven() = ShadowVpnService.setPrepareResult(null)

    @After
    fun resetLiveStatus() = setLiveStatus("disconnected")

    private fun persist(status: String) {
        prefs().edit().putString(KeqdisVpnService.KEY_QS_STATUS, status).commit()
    }

    private fun persisted() = prefs().getString(KeqdisVpnService.KEY_QS_STATUS, null)

    private fun decide(click: Boolean = true) = QuickConnect.decide(context, "TEST", click)

    @Test
    fun `with no saved server a tap opens the app to connect`() {
        assertSame(Tap.OpenApp, decide())
    }

    @Test
    fun `with a saved server a tap starts the service directly`() {
        saveSnapshot()
        val tap = decide()
        assertTrue(tap is Tap.Start)
        assertEquals(KeqdisVpnService.ACTION_START, (tap as Tap.Start).intent.action)
    }

    @Test
    fun `without VPN consent the tap goes through the quick connect window`() {
        saveSnapshot()
        ShadowVpnService.setPrepareResult(Intent("android.net.vpn.SETTINGS"))
        assertSame(Tap.Window, decide())
    }

    @Test
    fun `a proxy-only session starts without asking for VPN consent`() {
        saveSnapshot(tunnelMode = KeqdisVpnService.TUNNEL_MODE_PROXY)
        ShadowVpnService.setPrepareResult(Intent("android.net.vpn.SETTINGS"))
        assertTrue(decide() is Tap.Start)
    }

    @Test
    fun `firmware that swallowed a start goes to the window on this build`() {
        saveSnapshot()
        QuickConnect.rememberDirectStartBlocked(context)
        assertSame(Tap.Window, decide())
    }

    @Test
    fun `after a system update the window is no longer forced`() {
        saveSnapshot()
        prefs().edit().putString(KeqdisVpnService.KEY_QS_DIRECT_START_BLOCKED_ON, Build.FINGERPRINT + "-old").commit()
        assertTrue(decide() is Tap.Start)
    }

    @Test
    fun `a running VPN is stopped by a tap`() {
        saveSnapshot()
        persist("CONNECTED")
        setLiveStatus("connected")
        assertSame(Tap.Stop, decide())
        assertEquals("connected", QuickConnect.effectiveStatus(context))
    }

    @Test
    fun `a tap on a status left by a killed process heals it and connects`() {
        saveSnapshot()
        persist("connecting")
        assertTrue(decide() is Tap.Start)
        assertEquals("disconnected", persisted())
    }

    @Test
    fun `drawing the widget does not touch the saved status`() {
        saveSnapshot()
        persist("connected")
        assertTrue(decide(click = false) is Tap.Start)
        assertEquals("connected", persisted())
        assertEquals("disconnected", QuickConnect.effectiveStatus(context))
    }
}
