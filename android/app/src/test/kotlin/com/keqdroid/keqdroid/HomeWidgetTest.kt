package com.keqdroid.keqdroid

import com.keqdroid.keqdroid.HomeWidget.Kind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class HomeWidgetTest {

    @Test
    fun `country codes become flag emoji`() {
        assertEquals("🇩🇪", HomeWidget.flagEmoji("DE"))
        assertEquals("🇳🇱", HomeWidget.flagEmoji("NL"))
    }

    @Test
    fun `anything that is not two capital letters gets no flag`() {
        assertNull(HomeWidget.flagEmoji("de"))
        assertNull(HomeWidget.flagEmoji("DEU"))
        assertNull(HomeWidget.flagEmoji(""))
        assertNull(HomeWidget.flagEmoji("Д1"))
    }

    @Test
    fun `the widget shows the app's name, flag and ping for the server it will connect to`() {
        val server = HomeWidget.widgetServer(
            last = "Frankfurt",
            key = "Frankfurt",
            flag = "DE",
            name = "Frankfurt 1",
            ping = "42 ms",
        )
        assertEquals("🇩🇪 Frankfurt 1", server.name)
        assertEquals("42 ms", server.ping)
    }

    @Test
    fun `after a reconnect from the tile to another server the app's ping is not shown`() {
        val server = HomeWidget.widgetServer(
            last = "Amsterdam",
            key = "Frankfurt",
            flag = "DE",
            name = "Frankfurt 1",
            ping = "42 ms",
        )
        assertEquals("Amsterdam", server.name)
        assertNull(server.ping)
    }

    @Test
    fun `before the first session the app's choice is shown as is`() {
        val server = HomeWidget.widgetServer(last = null, key = "x", flag = null, name = "Warsaw", ping = null)
        assertEquals("Warsaw", server.name)
        assertEquals("", HomeWidget.widgetServer(null, null, null, null, null).name)
    }

    @Test
    fun `without a name from the app the server of the last session is named`() {
        assertEquals("Riga", HomeWidget.widgetServer("Riga", "Riga", flag = "xx", name = null, ping = null).name)
    }

    @Test
    fun `widget size picks the nearest layout that fits`() {
        assertEquals(Kind.DROP, HomeWidget.kindFor(57, 50))
        assertEquals(Kind.GLASS, HomeWidget.kindFor(130, 120))
        assertEquals(Kind.PLAQUE, HomeWidget.kindFor(250, 50))
        assertEquals(Kind.PLAQUE, HomeWidget.kindFor(330, 110))
    }

    @Test
    fun `a launcher one dp short still gets the layout`() {
        assertEquals(Kind.GLASS, HomeWidget.kindFor(109, 109))
        assertEquals(Kind.PLAQUE, HomeWidget.kindFor(219, 39))
    }

    @Test
    fun `unknown size gets the glass, a size too small for anything gets the drop`() {
        assertEquals(Kind.GLASS, HomeWidget.kindFor(0, 0))
        assertEquals(Kind.GLASS, HomeWidget.kindFor(200, 0))
        assertEquals(Kind.DROP, HomeWidget.kindFor(20, 20))
    }
}
