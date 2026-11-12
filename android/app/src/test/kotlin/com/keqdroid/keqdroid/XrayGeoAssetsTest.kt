package com.keqdroid.keqdroid

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class XrayGeoAssetsTest {
    private val geo = XrayGeoAssets

    @Test
    fun `an extracted base with the same fingerprint is not extracted again`() {
        assertTrue(geo.geoUpToDate(outLength = 600_000, previous = "size:600000", fingerprint = "size:600000"))
    }

    @Test
    fun `a new bundled base is extracted even though a file is already there`() {
        assertFalse(geo.geoUpToDate(outLength = 600_000, previous = "size:600000", fingerprint = "size:610000"))
        assertFalse(geo.geoUpToDate(outLength = 600_000, previous = null, fingerprint = "size:600000"))
    }

    @Test
    fun `a missing or empty file is extracted whatever the stamp says`() {
        assertFalse(geo.geoUpToDate(outLength = null, previous = "size:1", fingerprint = "size:1"))
        assertFalse(geo.geoUpToDate(outLength = 0, previous = "size:1", fingerprint = "size:1"))
    }

    @Test
    fun `a full downloaded base is not replaced by the trimmed bundled one`() {
        assertTrue(geo.keepsRicherBase(outLength = 23_500_000, assetSize = 600_000))
    }

    @Test
    fun `a base the same size or smaller than the bundled one is replaced`() {
        assertFalse(geo.keepsRicherBase(outLength = 600_000, assetSize = 600_000))
        assertFalse(geo.keepsRicherBase(outLength = 500_000, assetSize = 600_000))
        assertFalse(geo.keepsRicherBase(outLength = null, assetSize = 600_000))
    }

    @Test
    fun `with an unknown asset size nothing counts as richer`() {
        assertFalse(geo.keepsRicherBase(outLength = 23_500_000, assetSize = -1))
        assertFalse(geo.keepsRicherBase(outLength = 23_500_000, assetSize = 0))
    }

    @Test
    fun `fingerprint is the asset size, or the app version when the size is unknown`() {
        var asked = false
        assertEquals("size:612345", geo.fingerprintOf(612_345) { asked = true; 99 })
        assertFalse(asked)
        assertEquals("app:360200", geo.fingerprintOf(-1) { 360_200 })
    }

    @Test
    fun `the stamp reads back what was written`() {
        val entries = mapOf("geoip.dat" to "size:612345", "geosite.dat" to "app:360200")
        assertEquals(entries, geo.parseStamp(geo.formatStamp(entries).lines()))
    }

    @Test
    fun `broken stamp lines are skipped and the value may contain equals signs`() {
        assertEquals(
            mapOf("geoip.dat" to "a=b"),
            geo.parseStamp(listOf("", "=orphan", "garbage", "geoip.dat=a=b")),
        )
    }
}
