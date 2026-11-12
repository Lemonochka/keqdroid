package com.keqdroid.keqdroid

import com.keqdroid.keqdroid.RoboSession.context
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.File

// ассеты настоящие: Flutter кладёт их в сборку, Robolectric читает из неё же
@RunWith(RobolectricTestRunner::class)
class GeoAssetsExtractTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private val dir get() = tmp.root
    private val geoip get() = File(dir, "geoip.dat")
    private val geosite get() = File(dir, "geosite.dat")
    private val stamp get() = File(dir, "geo_assets.stamp")

    private fun stamped() = XrayGeoAssets.parseStamp(stamp.readLines())

    @Test
    fun `bundled bases are extracted and stamped with their size`() {
        XrayGeoAssets.ensure(context, dir)
        assertTrue(geoip.length() > 100_000)
        assertTrue(geosite.length() > geoip.length())
        assertEquals(
            mapOf("geoip.dat" to "size:${geoip.length()}", "geosite.dat" to "size:${geosite.length()}"),
            stamped(),
        )
    }

    @Test
    fun `an unchanged bundled base is not extracted again`() {
        XrayGeoAssets.ensure(context, dir)
        val marker = ByteArray(geoip.length().toInt()) { 7 }
        geoip.writeBytes(marker)
        XrayGeoAssets.ensure(context, dir)
        assertTrue(geoip.readBytes().contentEquals(marker))
    }

    @Test
    fun `a richer downloaded base survives a new bundled one`() {
        XrayGeoAssets.ensure(context, dir)
        val bundled = geoip.length()
        geoip.writeBytes(ByteArray(bundled.toInt() + 1000))
        stamp.writeText("geoip.dat=size:1")
        XrayGeoAssets.ensure(context, dir)
        assertEquals(bundled + 1000, geoip.length())
        assertEquals("size:$bundled", stamped()["geoip.dat"])
    }

    @Test
    fun `a smaller base from an older build is replaced`() {
        XrayGeoAssets.ensure(context, dir)
        val bundled = geoip.length()
        geoip.writeBytes(ByteArray(10))
        stamp.writeText("geoip.dat=size:1")
        XrayGeoAssets.ensure(context, dir)
        assertEquals(bundled, geoip.length())
    }

    @Test
    fun `a deleted base comes back even with a matching stamp`() {
        XrayGeoAssets.ensure(context, dir)
        val bundled = geosite.length()
        geosite.delete()
        XrayGeoAssets.ensure(context, dir)
        assertEquals(bundled, geosite.length())
    }
}
