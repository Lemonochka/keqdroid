package com.keqdroid.keqdroid

import org.json.JSONException
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

// org.json тут настоящий андроидный: на чистой JVM другая реализация, она слэш не экранирует
@RunWith(RobolectricTestRunner::class)
class CoreConfigJsonTest {

    @Test
    fun `android's JSON writer escapes slashes, the reason mihomo needs yamlSafeJson`() {
        assertEquals("""{"u":"a\/b"}""", JSONObject().put("u", "a/b").toString())
    }

    @Test
    fun `the tunnel descriptor goes into a mihomo config that go-yaml can still read`() {
        val config = """{"mixed-port":2080,"external-controller":"127.0.0.1:9090",""" +
            """"rule-providers":{"ru":{"type":"http","url":"https://example.com/lists/ru.yaml",""" +
            """"path":"./rules/ru.yaml"}},"tun":{"enable":true,"stack":"system"}}"""
        val out = mihomoConfigWithTunFd(config, 42)

        assertFalse(out, out.contains("\\/"))
        val back = JSONObject(out)
        val tun = back.getJSONObject("tun")
        assertEquals(42, tun.getInt("file-descriptor"))
        assertEquals(KeqdisVpnService.TUN_MTU, tun.getInt("mtu"))
        assertTrue(tun.getBoolean("enable"))
        assertEquals("system", tun.getString("stack"))
        val ru = back.getJSONObject("rule-providers").getJSONObject("ru")
        assertEquals("https://example.com/lists/ru.yaml", ru.getString("url"))
        assertEquals("./rules/ru.yaml", ru.getString("path"))
    }

    @Test
    fun `a backslash before a slash in a value survives the rewrite`() {
        val value = "geosite\\/x"
        val config = JSONObject().put("tun", JSONObject()).put("rule", value).toString()
        assertEquals(value, JSONObject(mihomoConfigWithTunFd(config, 7)).getString("rule"))
    }

    @Test
    fun `a mihomo config without a tun section cannot take the tunnel`() {
        assertThrows(IllegalStateException::class.java) { mihomoConfigWithTunFd("""{"mode":"rule"}""", 42) }
    }

    @Test
    fun `xray gets the interface MTU on its tun inbound only`() {
        val config = """{"inbounds":[{"tag":"socks-in","protocol":"socks","port":2080},""" +
            """{"tag":"tun-in","protocol":"tun","settings":{"name":"xray0"}}],"outbounds":[]}"""
        val inbounds = JSONObject(xrayConfigWithTunMtu(config)).getJSONArray("inbounds")
        assertFalse(inbounds.getJSONObject(0).has("settings"))
        val settings = inbounds.getJSONObject(1).getJSONObject("settings")
        assertEquals(KeqdisVpnService.TUN_MTU, settings.getInt("mtu"))
        assertEquals("xray0", settings.getString("name"))
    }

    @Test
    fun `a tun inbound without settings gets them`() {
        val out = JSONObject(xrayConfigWithTunMtu("""{"inbounds":[{"protocol":"tun"}]}"""))
        assertEquals(
            KeqdisVpnService.TUN_MTU,
            out.getJSONArray("inbounds").getJSONObject(0).getJSONObject("settings").getInt("mtu"),
        )
    }

    @Test
    fun `xray config without a tun inbound is refused`() {
        assertThrows(IllegalStateException::class.java) {
            xrayConfigWithTunMtu("""{"inbounds":[{"protocol":"socks"}]}""")
        }
        assertThrows(IllegalStateException::class.java) { xrayConfigWithTunMtu("""{"outbounds":[]}""") }
    }

    @Test
    fun `the tunnel is xray's own only when the config has a tun inbound`() {
        assertTrue(xrayHasTunInbound("""{"inbounds":[{"protocol":"socks"},{"protocol":"tun"}]}"""))
        assertFalse(xrayHasTunInbound("""{"inbounds":[{"protocol":"socks"}]}"""))
        assertFalse(xrayHasTunInbound("""{"outbounds":[]}"""))
        assertFalse(xrayHasTunInbound("""{"inbounds":[1,"tun",null]}"""))
    }

    @Test
    fun `a broken config is reported, not read as having no tunnel`() {
        assertThrows(JSONException::class.java) { xrayHasTunInbound("{inbounds:") }
        assertThrows(JSONException::class.java) { xraySessionLogLevel("not json") }
    }

    @Test
    fun `xray session log is raised to info and the rest of the config is kept`() {
        val raised = xraySessionLogLevel("""{"log":{"loglevel":"error","access":"none"},"inbounds":[]}""")!!
        assertEquals(3, raised.floor)
        val back = JSONObject(raised.config)
        assertEquals("info", back.getJSONObject("log").getString("loglevel"))
        assertEquals("none", back.getJSONObject("log").getString("access"))
        assertEquals(0, back.getJSONArray("inbounds").length())
    }

    @Test
    fun `xray without a log section is raised from its default warning`() {
        val raised = xraySessionLogLevel("""{"inbounds":[]}""")!!
        assertEquals(2, raised.floor)
        assertEquals("info", JSONObject(raised.config).getJSONObject("log").getString("loglevel"))
    }

    @Test
    fun `xray already at info or debug runs its own config`() {
        assertNull(xraySessionLogLevel("""{"log":{"loglevel":"Info"}}"""))
        assertNull(xraySessionLogLevel("""{"log":{"loglevel":"debug"}}"""))
    }
}
