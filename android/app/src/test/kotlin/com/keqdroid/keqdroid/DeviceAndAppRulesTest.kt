package com.keqdroid.keqdroid

import android.app.ApplicationExitInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DeviceAndAppRulesTest {

    @Test
    fun `autostart screens are found by brand or manufacturer in any case`() {
        val xiaomi = OemAutostart.screensFor("POCO", "Xiaomi")!!
        assertEquals("com.miui.securitycenter", xiaomi.single().first)
        assertEquals(OemAutostart.screensFor("google", "Xiaomi"), xiaomi)
        assertEquals(4, OemAutostart.screensFor("realme", "realme")!!.size)
        assertEquals(3, OemAutostart.screensFor("iQOO", "vivo")!!.size)
        assertEquals(2, OemAutostart.screensFor("HONOR", "HONOR")!!.size)
        assertEquals(1, OemAutostart.screensFor("asus", "ASUSTeK Computer Inc.")!!.size)
    }

    @Test
    fun `phones without an autostart setting get no button`() {
        assertNull(OemAutostart.screensFor("google", "Google"))
        assertNull(OemAutostart.screensFor("samsung", "samsung"))
        assertNull(OemAutostart.screensFor("", ""))
    }

    @Test
    fun `the VPN status written for the system comes back from the exit record`() {
        for (status in listOf("connected", "connecting", "disconnected", "error")) {
            assertEquals(status, ProcessExits.vpnStatusFromSummary(ProcessExits.vpnSummary(status)))
        }
    }

    @Test
    fun `an exit record without our summary has no VPN status`() {
        assertNull(ProcessExits.vpnStatusFromSummary(null))
        assertNull(ProcessExits.vpnStatusFromSummary("connected".toByteArray()))
        assertEquals("", ProcessExits.vpnStatusFromSummary("vpn=".toByteArray()))
    }

    @Test
    fun `exit reasons are logged by name`() {
        assertEquals("LOW_MEMORY", ProcessExits.reasonName(ApplicationExitInfo.REASON_LOW_MEMORY))
        assertEquals("SIGNALED", ProcessExits.reasonName(ApplicationExitInfo.REASON_SIGNALED))
        assertEquals("USER_REQUESTED", ProcessExits.reasonName(ApplicationExitInfo.REASON_USER_REQUESTED))
        assertEquals("PACKAGE_UPDATED", ProcessExits.reasonName(ApplicationExitInfo.REASON_PACKAGE_UPDATED))
        assertEquals("UNKNOWN(999)", ProcessExits.reasonName(999))
    }

    @Test
    fun `the last exit is described in one line for the core log`() {
        assertEquals(
            "2026-11-12 14:03:05, LOW_MEMORY, status 0, VPN connected, \"lmkd kill\"",
            ProcessExits.describe(
                "2026-11-12 14:03:05", ApplicationExitInfo.REASON_LOW_MEMORY, 0, "connected", "lmkd kill",
            ),
        )
        assertEquals(
            "2026-11-12 14:03:05, SIGNALED, status 9",
            ProcessExits.describe("2026-11-12 14:03:05", ApplicationExitInfo.REASON_SIGNALED, 9, null, "  "),
        )
    }

    @Test
    fun `launch actions are trusted only from our own closed alias`() {
        val alias = "com.keqdroid.keqdroid.LaunchAction"
        assertEquals(
            MainActivity.LAUNCH_ACTION_CONNECT,
            launchActionFrom(alias) { MainActivity.LAUNCH_ACTION_CONNECT },
        )
        assertEquals(
            MainActivity.LAUNCH_ACTION_DISCONNECT,
            launchActionFrom(alias) { MainActivity.LAUNCH_ACTION_DISCONNECT },
        )
        assertNull(launchActionFrom(alias) { "wipe_everything" })
        assertNull(launchActionFrom(alias) { null })
    }

    @Test
    fun `extras sent to the exported window are not even read`() {
        var read = false
        assertNull(launchActionFrom("com.keqdroid.keqdroid.MainActivity") { read = true; MainActivity.LAUNCH_ACTION_CONNECT })
        assertNull(launchActionFrom(null) { read = true; MainActivity.LAUNCH_ACTION_CONNECT })
        assertFalse(read)
    }

    @Test
    fun `local proxy credentials are long random alphanumerics`() {
        val a = randomToken(24)
        val b = randomToken(24)
        assertEquals(24, a.length)
        assertEquals(16, randomToken(16).length)
        assertTrue(a.all { it in 'a'..'z' || it in 'A'..'Z' || it in '0'..'9' })
        assertNotEquals(a, b)
    }

    @Test
    fun `theme seeds from system settings parse with or without alpha`() {
        assertEquals(0xFF6750A4.toInt(), parseThemeHex("6750A4"))
        assertEquals(0xFF6750A4.toInt(), parseThemeHex(" #6750a4 "))
        assertEquals(0x806750A4.toInt(), parseThemeHex("806750A4"))
    }

    @Test
    fun `broken theme seeds are ignored`() {
        assertNull(parseThemeHex(null))
        assertNull(parseThemeHex(""))
        assertNull(parseThemeHex("6750A"))
        assertNull(parseThemeHex("GGGGGG"))
    }
}
