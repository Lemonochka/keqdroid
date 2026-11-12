package com.keqdroid.keqdroid

import android.content.ComponentName
import android.content.Intent
import com.keqdroid.keqdroid.RoboSession.context
import com.keqdroid.keqdroid.RoboSession.prefs
import com.keqdroid.keqdroid.RoboSession.saveSnapshot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class SnapshotIntentTest {

    @Test
    fun `nothing saved means no start intent`() {
        assertNull(KeqdisVpnService.snapshotStartIntent(context))
    }

    @Test
    fun `the start intent carries the whole last session`() {
        val config = saveSnapshot(
            tunnelMode = KeqdisVpnService.TUNNEL_MODE_PROXY,
            backend = KeqdisVpnService.VPN_BACKEND_MIHOMO,
            exclude = setOf("com.bank.app"),
        )
        val intent = KeqdisVpnService.snapshotStartIntent(context)!!

        assertEquals(ComponentName(context, KeqdisVpnService::class.java), intent.component)
        assertEquals(KeqdisVpnService.ACTION_START, intent.action)
        assertEquals(KeqdisVpnService.VPN_BACKEND_MIHOMO, intent.getStringExtra(KeqdisVpnService.EXTRA_VPN_BACKEND))
        assertEquals(KeqdisVpnService.TUNNEL_MODE_PROXY, intent.getStringExtra(KeqdisVpnService.EXTRA_TUNNEL_MODE))
        assertEquals(config.path, intent.getStringExtra(KeqdisVpnService.EXTRA_XRAY_CONFIG))
        assertEquals(10808, intent.getIntExtra("socks_port", -1))
        assertEquals(listOf("com.bank.app"), intent.getStringArrayListExtra("exclude_packages"))
        assertEquals(emptyList<String>(), intent.getStringArrayListExtra("include_packages"))
        assertEquals("user", intent.getStringExtra(KeqdisVpnService.EXTRA_SOCKS_USERNAME))
        assertEquals("pass", intent.getStringExtra(KeqdisVpnService.EXTRA_SOCKS_PASSWORD))
        assertEquals("Frankfurt", intent.getStringExtra(KeqdisVpnService.EXTRA_SERVER_NAME))
        assertFalse(KeqdisVpnService.startsTunnel(intent))
    }

    @Test
    fun `a record left with the old keqrnel engine reconnects with chain`() {
        saveSnapshot()
        prefs().edit().putString(KeqdisVpnService.KEY_QS_LAST_CORE_ENGINE, KeqdisVpnService.CORE_ENGINE_KEQRNEL).commit()
        assertEquals(
            KeqdisVpnService.CORE_ENGINE_CHAIN,
            KeqdisVpnService.snapshotStartIntent(context)!!.getStringExtra(KeqdisVpnService.EXTRA_CORE_ENGINE),
        )
    }

    @Test
    fun `a blank server name is not sent, the notification then says VPN`() {
        saveSnapshot(serverName = " ")
        assertFalse(KeqdisVpnService.snapshotStartIntent(context)!!.hasExtra(KeqdisVpnService.EXTRA_SERVER_NAME))
    }

    @Test
    fun `a config wiped together with app data means no start intent`() {
        saveSnapshot().delete()
        assertNull(KeqdisVpnService.snapshotStartIntent(context))
    }

    @Test
    fun `only proxy mode skips the tunnel`() {
        assertTrue(KeqdisVpnService.startsTunnel(Intent()))
        assertTrue(
            KeqdisVpnService.startsTunnel(
                Intent().putExtra(KeqdisVpnService.EXTRA_TUNNEL_MODE, KeqdisVpnService.TUNNEL_MODE_VPN),
            ),
        )
        assertFalse(
            KeqdisVpnService.startsTunnel(
                Intent().putExtra(KeqdisVpnService.EXTRA_TUNNEL_MODE, KeqdisVpnService.TUNNEL_MODE_PROXY),
            ),
        )
    }
}
