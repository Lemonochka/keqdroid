package com.keqdroid.keqdroid

import android.content.Intent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class VpnServiceRulesTest {

    @Test
    fun `run states are told to the tile, widget and Dart with these words`() {
        assertEquals("disconnected", statusName(VpnRunStatus.STOPPED))
        assertEquals("connecting", statusName(VpnRunStatus.STARTING))
        assertEquals("connected", statusName(VpnRunStatus.RUNNING))
        assertEquals("error", statusName(VpnRunStatus.ERROR))
    }

    @Test
    fun `only a finished status survives a process restart`() {
        assertFalse(statusNeedsHealing("disconnected"))
        assertFalse(statusNeedsHealing("error"))
        assertTrue(statusNeedsHealing("connected"))
        assertTrue(statusNeedsHealing("connecting"))
        assertTrue(statusNeedsHealing(null))
    }

    @Test
    fun `restore needs a snapshot`() {
        assertEquals(
            "there is no server to reconnect to, connect from the app once",
            restoreRefusal(startsTunnel = null, alwaysOn = false) { false },
        )
    }

    @Test
    fun `always-on VPN does not bring back a proxy-only session`() {
        assertEquals(
            "the last session was a local proxy, and always-on VPN needs a tunnel",
            restoreRefusal(startsTunnel = false, alwaysOn = true) { false },
        )
    }

    @Test
    fun `a proxy-only session comes back after a restart without asking for VPN consent`() {
        var asked = false
        assertNull(restoreRefusal(startsTunnel = false, alwaysOn = false) { asked = true; true })
        assertFalse(asked)
    }

    @Test
    fun `a tunnel without consent stays down`() {
        assertEquals("the VPN permission was taken away", restoreRefusal(true, alwaysOn = false) { true })
        assertEquals("the VPN permission was taken away", restoreRefusal(true, alwaysOn = true) { true })
        assertNull(restoreRefusal(true, alwaysOn = true) { false })
    }

    @Test
    fun `a core that dies right after start three times in a row ends the session`() {
        var deaths = 0
        repeat(3) { deaths = quickDeathsAfter(deaths, livedMs = 5_000) }
        assertEquals(CORE_MAX_QUICK_DEATHS, deaths)
    }

    @Test
    fun `a core that lived for a while is always revived and resets the count`() {
        assertEquals(0, quickDeathsAfter(previous = 2, livedMs = CORE_QUICK_DEATH_MS))
        assertEquals(0, quickDeathsAfter(previous = 2, livedMs = 3_600_000))
        assertEquals(3, quickDeathsAfter(previous = 2, livedMs = CORE_QUICK_DEATH_MS - 1))
    }

    @Test
    fun `HyperOS is recognised by its version name first`() {
        assertEquals(
            "OS2.0 (name)",
            hyperOsVersionOf("OS2.0", "2", "OS2.0.201.0.VNPMIXM", "Xiaomi", "POCO"),
        )
    }

    @Test
    fun `HyperOS falls back to the version code`() {
        assertEquals("code 4", hyperOsVersionOf("", "4", "whatever", "Xiaomi", "Xiaomi"))
    }

    @Test
    fun `HyperOS build number counts only on Xiaomi brands`() {
        assertEquals(
            "OS2.0.201.0.VNPMIXM (build)",
            hyperOsVersionOf("", "", "OS2.0.201.0.VNPMIXM", "Xiaomi", "POCO"),
        )
        assertEquals("OS3.1 (build)", hyperOsVersionOf("", "", "OS3.1", null, "redmi"))
        assertNull(hyperOsVersionOf("", "", "OS2.0.201.0", "Google", "google"))
    }

    @Test
    fun `MIUI and AOSP builds on Xiaomi are not HyperOS`() {
        assertNull(hyperOsVersionOf("", "", "V14.0.6.0.TKFMIXM", "Xiaomi", "Redmi"))
        assertNull(hyperOsVersionOf("", "", "eng.root.20260101", "Xiaomi", "Xiaomi"))
    }

    @Test
    fun `only Huawei and Honor get the underlying network set by hand`() {
        assertTrue(needsExplicitUnderlying("HUAWEI"))
        assertTrue(needsExplicitUnderlying("Honor"))
        assertFalse(needsExplicitUnderlying("Xiaomi"))
        assertFalse(needsExplicitUnderlying("Google"))
    }

    @Test
    fun `memory log warns once per doubling`() {
        val gb = 1024L * 1024 * 1024
        val watch = MemoryWatch()
        assertEquals(emptyList<String>(), watch.alarms(500L * 1024 * 1024))
        assertEquals(listOf("now above 1024 MB", "grew by 524 MB since last time"), watch.alarms(gb + 0))
        assertEquals(emptyList<String>(), watch.alarms(gb + 100L * 1024 * 1024))
        assertEquals(
            listOf("now above 4096 MB", "grew by 3996 MB since last time"),
            watch.alarms(5 * gb),
        )
    }

    @Test
    fun `memory log warns about a jump even below the threshold`() {
        val mb = 1024L * 1024
        val watch = MemoryWatch()
        watch.alarms(100 * mb)
        assertEquals(listOf("grew by 300 MB since last time"), watch.alarms(400 * mb))
        assertEquals(emptyList<String>(), watch.alarms(600 * mb))
    }

    @Test
    fun `proc status fields are read by key`() {
        val status = sequenceOf("Name:\tkeqdroid", "Threads:\t57", "VmRSS:\t  183456 kB")
        assertEquals(57L, statusField(status, "Threads"))
        assertEquals(183456L, statusField(status, "VmRSS"))
        assertNull(statusField(status, "VmSwap"))
        assertNull(statusField(status, "Name"))
    }

    @Test
    fun `speeds and uptime read the same in every locale`() {
        assertEquals("512 B/s", formatSpeed(512))
        assertEquals("1.0 KB/s", formatSpeed(1024))
        assertEquals("1.5 MB/s", formatSpeed(1536L * 1024))
        assertEquals("59s", formatUptime(59_999))
        assertEquals("1m 0s", formatUptime(60_000))
        assertEquals("2h 5m", formatUptime((2 * 3600 + 5 * 60 + 9) * 1000L))
        assertEquals("3 MB", megabytes(3L * 1024 * 1024 + 1))
    }

    @Test
    fun `notification shows what the settings ask for`() {
        assertEquals("1m 5s  ·  ↓ 2.0 KB/s  ·  ↑ 10 B/s", notificationBody(true, true, 65_000, 2048, 10))
        assertEquals("1m 5s", notificationBody(true, false, 65_000, 2048, 10))
        assertEquals("↓ 2.0 KB/s  ·  ↑ 10 B/s", notificationBody(false, true, 65_000, 2048, 10))
        assertEquals("Connected", notificationBody(false, false, 65_000, 2048, 10))
    }

    @Test
    fun `the core log says why a session came back by itself`() {
        assertEquals(
            "the app was updated while the VPN was on, reconnecting",
            resumeNote(Intent.ACTION_MY_PACKAGE_REPLACED),
        )
        assertEquals(
            "the phone restarted while the VPN was on, reconnecting",
            resumeNote(Intent.ACTION_BOOT_COMPLETED),
        )
        assertNull(resumeNote(Intent.ACTION_PACKAGE_REPLACED))
        assertNull(resumeNote(null))
    }
}
