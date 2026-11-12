package com.keqdroid.keqdroid

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ConnectionOwnerTest {
    private val outside = ConnectionOwnerServer.OUTSIDE_VPN

    @Test
    fun `the guard name matches the one in Dart and the core patches`() {
        assertEquals("keqdroid:outside-vpn", outside)
    }

    @Test
    fun `a core request is split into protocol, source and destination`() {
        val q = parseOwnerQuery("udp 172.19.0.1 40213 1.1.1.1 443\n")!!
        assertTrue(q.udp)
        assertEquals("172.19.0.1", q.srcIp)
        assertEquals(40213, q.srcPort)
        assertEquals("1.1.1.1", q.dstIp)
        assertEquals(443, q.dstPort)
        assertFalse(parseOwnerQuery("tcp ::1 1 ::2 2")!!.udp)
    }

    @Test
    fun `a malformed request gets no answer instead of a crash`() {
        assertNull(parseOwnerQuery(""))
        assertNull(parseOwnerQuery("tcp 10.0.0.1 80 10.0.0.2"))
        assertNull(parseOwnerQuery("tcp 10.0.0.1 http 10.0.0.2 443"))
        assertNull(parseOwnerQuery("tcp  10.0.0.1 80 10.0.0.2 443"))
    }

    @Test
    fun `a connection without an owner is marked as coming from outside the VPN`() {
        assertEquals(outside, unownedAnswer(systemOutsideVpn = false, "93.184.216.34", 443) { true })
        assertEquals(outside, unownedAnswer(systemOutsideVpn = false, KeqdisVpnService.TUN_DNS_ADDRESS, 53) { true })
    }

    @Test
    fun `in selected apps mode system DNS to our resolver is not blocked`() {
        assertEquals("", unownedAnswer(systemOutsideVpn = true, KeqdisVpnService.TUN_DNS_ADDRESS, 53) { false })
        assertEquals("", unownedAnswer(systemOutsideVpn = true, KeqdisVpnService.TUN_DNS_ADDRESS, 853) { false })
    }

    @Test
    fun `strict private DNS counts as system traffic only while it is on`() {
        assertEquals("", unownedAnswer(systemOutsideVpn = true, "8.8.8.8", 853) { true })
        assertEquals(outside, unownedAnswer(systemOutsideVpn = true, "8.8.8.8", 853) { false })
    }

    @Test
    fun `plain DNS to a public resolver and other ports stay guarded`() {
        var asked = false
        assertEquals(outside, unownedAnswer(systemOutsideVpn = true, "8.8.8.8", 53) { asked = true; true })
        assertEquals(outside, unownedAnswer(systemOutsideVpn = true, KeqdisVpnService.TUN_DNS_ADDRESS, 443) { asked = true; true })
        assertFalse(asked)
    }

    @Test
    fun `lookup timings are summarised with median, p95 and max`() {
        val sorted = (1L..100L).toList()
        assertEquals(
            "owner lookups: 500 total, last 100: median 51 us, p95 96 us, max 100 us, outside VPN: 7",
            ownerTimingLine(sorted, 500, 7),
        )
        assertEquals(
            "owner lookups: 1 total, last 1: median 9 us, p95 9 us, max 9 us, outside VPN: 0",
            ownerTimingLine(listOf(9L), 1, 0),
        )
    }

    @Test
    fun `only our own core binaries count as orphans`() {
        val nul = Char.MIN_VALUE
        val dir = "/data/app/~~x/com.keqdroid.keqdroid-1/lib/arm64"
        assertEquals("libxray.so", orphanCoreName("$dir/libxray.so${nul}run$nul-c${nul}config.json$nul".toByteArray()))
        assertEquals("libmihomo.so", orphanCoreName("$dir/libmihomo.so$nul-d$nul/files$nul".toByteArray()))
        assertEquals("libxray.so", orphanCoreName("libxray.so".toByteArray()))
    }

    @Test
    fun `the app itself and anything else in proc is left alone`() {
        val nul = Char.MIN_VALUE
        assertNull(orphanCoreName("com.keqdroid.keqdroid$nul".toByteArray()))
        assertNull(orphanCoreName("/system/bin/sh$nul-c${nul}libxray.so$nul".toByteArray()))
        assertNull(orphanCoreName("/data/libxray.so.bak$nul".toByteArray()))
        assertNull(orphanCoreName(ByteArray(0)))
    }
}
