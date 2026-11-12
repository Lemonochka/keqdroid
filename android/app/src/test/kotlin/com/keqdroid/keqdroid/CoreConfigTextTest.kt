package com.keqdroid.keqdroid

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test

class CoreConfigTextTest {

    @Test
    fun `escaped slashes become plain so go-yaml can read the config`() {
        assertEquals(
            """{"url":"https://cp.cloudflare.com/generate_204"}""",
            yamlSafeJson("""{"url":"https:\/\/cp.cloudflare.com\/generate_204"}"""),
        )
    }

    @Test
    fun `a config without escaped slashes is passed through untouched`() {
        val json = """{"tun":{"enable":true,"file-descriptor":42}}"""
        assertSame(json, yamlSafeJson(json))
    }

    @Test
    fun `other escapes survive, and an escaped backslash does not swallow the next slash`() {
        // в JSON: строка a\ и дальше путь /b, слэш перед b экранирован
        assertEquals("""{"p":"a\\/b","q":"x\"y\n"}""", yamlSafeJson("""{"p":"a\\\/b","q":"x\"y\n"}"""))
        assertEquals("""["\\"]""", yamlSafeJson("""["\\"]"""))
    }

    @Test
    fun `a lone trailing backslash is kept`() {
        assertEquals("""/x\""", yamlSafeJson("""\/x\"""))
    }

    @Test
    fun `mihomo log level above info is lowered to info in json form`() {
        val raised = mihomoSessionLogLevel("""{"log-level": "warning","mode":"rule"}""")!!
        assertEquals("""{"log-level": "info","mode":"rule"}""", raised.config)
        assertEquals(2, raised.floor)
    }

    @Test
    fun `mihomo log level above info is lowered to info in yaml form`() {
        val raised = mihomoSessionLogLevel("mode: rule\nlog-level: 'error'\nipv6: false\n")!!
        assertEquals("mode: rule\nlog-level: 'info'\nipv6: false\n", raised.config)
        assertEquals(3, raised.floor)
    }

    @Test
    fun `mihomo silent counts as the highest floor`() {
        assertEquals(4, mihomoSessionLogLevel("log-level: SILENT")!!.floor)
    }

    @Test
    fun `mihomo config at info or below, without the field or with an unknown level is left alone`() {
        assertNull(mihomoSessionLogLevel("log-level: info"))
        assertNull(mihomoSessionLogLevel("log-level: debug"))
        assertNull(mihomoSessionLogLevel("mode: rule"))
        assertNull(mihomoSessionLogLevel("log-level: verbose"))
    }

    @Test
    fun `nested log-level keys in yaml are not mistaken for the top level one`() {
        assertNull(mihomoSessionLogLevel("dns:\n  log-level: error\n"))
    }

    @Test
    fun `xray without a log level writes warnings, so the session is raised`() {
        assertEquals(2, xrayLogFloor("warning"))
        assertEquals(2, xrayLogFloor("Warning"))
        assertEquals(3, xrayLogFloor("error"))
        assertEquals(4, xrayLogFloor("none"))
    }

    @Test
    fun `xray with an unknown level is treated as warning`() {
        assertEquals(2, xrayLogFloor("loud"))
        assertEquals(2, xrayLogFloor(""))
    }

    @Test
    fun `xray at info or debug is left as is`() {
        assertNull(xrayLogFloor("info"))
        assertNull(xrayLogFloor("debug"))
    }

    @Test
    fun `log text since a mark returns only the new part`() {
        val bytes = "old line\nnew line\n".toByteArray()
        assertEquals("new line\n", textSince(bytes, 9))
        assertEquals("", textSince(bytes, bytes.size.toLong()))
    }

    @Test
    fun `a log that was truncated below the mark is read whole`() {
        val bytes = "fresh\n".toByteArray()
        assertEquals("fresh\n", textSince(bytes, 1000))
        assertEquals("fresh\n", textSince(bytes, -1))
    }

    @Test
    fun `log text since a mark keeps utf-8 intact`() {
        val bytes = "ok\nсервер упал\n".toByteArray()
        assertEquals("сервер упал\n", textSince(bytes, 3))
    }

    @Test
    fun `log tail skips blank lines and keeps the last ones`() {
        val lines = listOf("1", "", "2", "  ", "3", "4")
        assertEquals("\n3\n4", logTail(lines, maxLines = 2, maxChars = 600))
        assertEquals("\n1\n2\n3\n4", logTail(lines, maxLines = 6, maxChars = 600))
    }

    @Test
    fun `log tail is cut from the start to fit the notification`() {
        assertEquals("\nghij", logTail(listOf("abcdefghij"), maxLines = 6, maxChars = 4))
    }

    @Test
    fun `an empty log gives no tail at all`() {
        assertEquals("", logTail(emptyList(), 6, 600))
        assertEquals("", logTail(listOf("", "   "), 6, 600))
    }

    @Test
    fun `the last tun failure line names the reason`() {
        val log = "INFO start\n" +
            "ERRO Start TUN listening error: first\n" +
            "ERRO Start TUN listening error:   operation not permitted  \n"
        assertEquals("operation not permitted", mihomoTunFailure(log))
    }

    @Test
    fun `a long tun failure is cut to 300 characters`() {
        val reason = "x".repeat(500)
        assertEquals(300, mihomoTunFailure("Start TUN listening error: $reason")!!.length)
    }

    @Test
    fun `no tun failure line means no failure`() {
        assertNull(mihomoTunFailure("[TUN] Tun adapter listening at: tun0\n"))
        assertNull(mihomoTunFailure(""))
    }

    @Test
    fun `mihomo api port comes from the external controller address`() {
        assertEquals(9090 to "s3cret", mihomoApiOf("127.0.0.1:9090", "s3cret"))
        assertEquals(9090 to "s3cret", mihomoApiOf(":9090", "s3cret"))
        assertEquals(9090 to "s3cret", mihomoApiOf("[::1]:9090", "s3cret"))
    }

    @Test
    fun `mihomo api without a port or a secret is not offered`() {
        assertNull(mihomoApiOf("127.0.0.1:9090", ""))
        assertNull(mihomoApiOf("", "s3cret"))
        assertNull(mihomoApiOf("127.0.0.1", "s3cret"))
        assertNull(mihomoApiOf("127.0.0.1:0", "s3cret"))
        assertNull(mihomoApiOf("127.0.0.1:http", "s3cret"))
    }
}
