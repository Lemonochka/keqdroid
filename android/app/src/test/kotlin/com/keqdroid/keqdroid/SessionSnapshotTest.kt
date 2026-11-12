package com.keqdroid.keqdroid

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SessionSnapshotTest {
    private val config = "/data/user/0/com.keqdroid.keqdroid/files/xray_config.json"

    private fun snapshot(
        backend: String = KeqdisVpnService.VPN_BACKEND_MIHOMO,
        tunnelMode: String = KeqdisVpnService.TUNNEL_MODE_PROXY,
        serverName: String? = "Frankfurt",
    ) = SessionSnapshot(
        backend = backend,
        tunnelMode = tunnelMode,
        config = config,
        socksPort = 10808,
        exclude = setOf("com.bank.app"),
        include = emptySet(),
        username = "user",
        password = "pass",
        serverName = serverName,
    )

    private fun written(s: SessionSnapshot): FakeSharedPreferences {
        val prefs = FakeSharedPreferences()
        s.writeTo(prefs.edit()).apply()
        return prefs
    }

    @Test
    fun `the tile reconnects with exactly what the last session used`() {
        val read = SessionSnapshot.read(written(snapshot())) { it == config }!!
        assertEquals(KeqdisVpnService.VPN_BACKEND_MIHOMO, read.backend)
        assertEquals(KeqdisVpnService.TUNNEL_MODE_PROXY, read.tunnelMode)
        assertEquals(config, read.config)
        assertEquals(10808, read.socksPort)
        assertEquals(setOf("com.bank.app"), read.exclude)
        assertEquals(emptySet<String>(), read.include)
        assertEquals("user", read.username)
        assertEquals("pass", read.password)
        assertEquals("Frankfurt", read.serverName)
    }

    @Test
    fun `there is no snapshot when the config file is gone`() {
        assertNull(SessionSnapshot.read(written(snapshot())) { false })
    }

    @Test
    fun `a record left by the old AWG core is not reused`() {
        assertNull(SessionSnapshot.read(written(snapshot(backend = "awg"))) { true })
    }

    @Test
    fun `nothing saved means nothing to reconnect to`() {
        assertNull(SessionSnapshot.read(FakeSharedPreferences()) { true })
    }

    @Test
    fun `a snapshot without credentials is unusable`() {
        val prefs = written(snapshot())
        prefs.edit().putString(KeqdisVpnService.KEY_QS_LAST_SOCKS_PASSWORD, " ").apply()
        assertNull(SessionSnapshot.read(prefs) { true })

        val noUser = written(snapshot())
        noUser.edit().remove(KeqdisVpnService.KEY_QS_LAST_SOCKS_USERNAME).apply()
        assertNull(SessionSnapshot.read(noUser) { true })
    }

    @Test
    fun `records from before the mode setting reconnect as a VPN on port 2080 with xray`() {
        val prefs = FakeSharedPreferences()
        prefs.edit()
            .putString(KeqdisVpnService.KEY_QS_LAST_XRAY_CONFIG, config)
            .putString(KeqdisVpnService.KEY_QS_LAST_SOCKS_USERNAME, "u")
            .putString(KeqdisVpnService.KEY_QS_LAST_SOCKS_PASSWORD, "p")
            .apply()
        val read = SessionSnapshot.read(prefs) { true }!!
        assertEquals(KeqdisVpnService.VPN_BACKEND_XRAY, read.backend)
        assertEquals(KeqdisVpnService.TUNNEL_MODE_VPN, read.tunnelMode)
        assertEquals(2080, read.socksPort)
        assertTrue(read.exclude.isEmpty())
        assertNull(read.serverName)
    }

    @Test
    fun `a blank server name is not carried into the notification`() {
        assertNull(SessionSnapshot.read(written(snapshot(serverName = "  "))) { true }!!.serverName)
        assertNull(SessionSnapshot.read(written(snapshot(serverName = null))) { true }!!.serverName)
    }

    @Test
    fun `the config path is checked only when the rest of the record is usable`() {
        var asked = false
        SessionSnapshot.read(written(snapshot(backend = "awg"))) { asked = true; true }
        assertFalse(asked)
    }

    @Test
    fun `tunnel mode from the intent falls back to the VPN for anything but proxy`() {
        assertEquals(KeqdisVpnService.TUNNEL_MODE_PROXY, sessionTunnelMode(KeqdisVpnService.TUNNEL_MODE_PROXY))
        assertEquals(KeqdisVpnService.TUNNEL_MODE_VPN, sessionTunnelMode(KeqdisVpnService.TUNNEL_MODE_VPN))
        assertEquals(KeqdisVpnService.TUNNEL_MODE_VPN, sessionTunnelMode(null))
        assertEquals(KeqdisVpnService.TUNNEL_MODE_VPN, sessionTunnelMode("PROXY"))
    }
}
