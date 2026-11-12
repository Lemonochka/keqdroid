package com.keqdroid.keqdroid

import com.keqdroid.keqdroid.EphemeralXrayPing.BatchItem
import com.keqdroid.keqdroid.EphemeralXrayPing.MultiProbe
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class EphemeralXrayPingTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private val ping = EphemeralXrayPing

    @Test
    fun `each core has its own binary`() {
        assertEquals("libmihomo.so", ping.coreBinary("/lib", EphemeralXrayPing.CORE_MIHOMO).name)
        assertEquals("libxray.so", ping.coreBinary("/lib", EphemeralXrayPing.CORE_XRAY).name)
        assertEquals("libxray.so", ping.coreBinary("/lib", "anything").name)
    }

    @Test
    fun `probes go over https`() {
        assertEquals("https://cp.cloudflare.com/generate_204", ping.ensureHttps("http://cp.cloudflare.com/generate_204"))
        assertEquals("https://example.com/", ping.ensureHttps("  HTTP://example.com/ "))
        assertEquals("https://example.com/", ping.ensureHttps("https://example.com/"))
    }

    @Test
    fun `only a mihomo probe is retried, and only while the core is still waking up`() {
        assertTrue(ping.retryProbe(EphemeralXrayPing.CORE_MIHOMO, coreAwake = false, sinceCoreStartMs = 1_500))
        assertFalse(ping.retryProbe(EphemeralXrayPing.CORE_MIHOMO, coreAwake = false, sinceCoreStartMs = 3_000))
        assertFalse(ping.retryProbe(EphemeralXrayPing.CORE_MIHOMO, coreAwake = true, sinceCoreStartMs = 100))
        assertFalse(ping.retryProbe(EphemeralXrayPing.CORE_XRAY, coreAwake = false, sinceCoreStartMs = 100))
    }

    @Test
    fun `download speed is counted in kilobits per second`() {
        assertEquals(16_000, ping.kbps(bytes = 2_000_000, elapsedMs = 1_000))
        assertEquals(4_000, ping.kbps(bytes = 2_000_000, elapsedMs = 4_000))
        assertEquals(8, ping.kbps(bytes = 1, elapsedMs = 1))
    }

    @Test
    fun `a missing core fails every server in the batch with the same reason`() {
        val results = ping.urlTestBatch(
            nativeLibraryDir = tmp.root.path,
            filesDir = tmp.root,
            assetDir = tmp.root.path,
            socksPort = 20000,
            items = listOf(BatchItem("a", "{}"), BatchItem("b", "{}")),
            testUrl = "https://cp.cloudflare.com/generate_204",
            timeoutMs = 1000,
            core = EphemeralXrayPing.CORE_MIHOMO,
        )
        assertEquals(listOf("a", "b"), results.map { it.id })
        assertTrue(results.all { !it.result.success && it.result.error == "libmihomo.so not found" })
    }

    @Test
    fun `a missing core fails the multi probe for each server`() {
        val results = ping.urlTestMulti(
            nativeLibraryDir = tmp.root.path,
            filesDir = tmp.root,
            assetDir = tmp.root.path,
            configJson = "{}",
            probes = listOf(MultiProbe("a", 20001), MultiProbe("b", 20002)),
            testUrl = "https://cp.cloudflare.com/generate_204",
            timeoutMs = 1000,
        )
        assertEquals(listOf("a", "b"), results.map { it.id })
        assertTrue(results.all { it.result.error == "libxray.so not found" && it.result.latencyMs == null })
        assertEquals(0, tmp.root.listFiles()!!.size)
    }

    @Test
    fun `a missing core fails the speed test batch too`() {
        val results = ping.speedTestBatch(
            nativeLibraryDir = tmp.root.path,
            filesDir = tmp.root,
            assetDir = tmp.root.path,
            socksPort = 20000,
            items = listOf(BatchItem("a", "{}")),
            downloadUrl = "https://speed.cloudflare.com/__down?bytes=1",
            timeoutMs = 1000,
        )
        assertEquals("libxray.so not found", results.single().result.error)
        assertEquals(null, results.single().result.kbps)
    }

    @Test
    fun `empty batches start nothing`() {
        assertEquals(0, ping.urlTestBatch(tmp.root.path, tmp.root, "", 1, emptyList(), "", 1).size)
        assertEquals(0, ping.urlTestMulti(tmp.root.path, tmp.root, "", "{}", emptyList(), "", 1).size)
        assertEquals(0, ping.speedTestBatch(tmp.root.path, tmp.root, "", 1, emptyList(), "", 1).size)
    }
}
