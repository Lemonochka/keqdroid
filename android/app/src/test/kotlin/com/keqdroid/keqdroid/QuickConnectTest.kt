package com.keqdroid.keqdroid

import com.keqdroid.keqdroid.QuickConnect.Route
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class QuickConnectTest {

    private fun route(
        persisted: String,
        live: Boolean,
        snapshot: Boolean = true,
        consentMissing: Boolean = false,
        blocked: Boolean = false,
        asked: MutableList<String> = mutableListOf(),
    ) = QuickConnect.route(
        persisted,
        live,
        hasSnapshot = { asked += "snapshot"; snapshot },
        consentMissing = { asked += "consent"; consentMissing },
        startBlocked = { asked += "blocked"; blocked },
    )

    @Test
    fun `a tap on a running or connecting VPN stops it without looking further`() {
        for (status in listOf("connected", "running", "connecting", "starting")) {
            val asked = mutableListOf<String>()
            assertEquals(status, Route.STOP, route(status, live = true, asked = asked))
            assertEquals(emptyList<String>(), asked)
        }
    }

    @Test
    fun `a status left over from a killed process connects instead of stopping`() {
        assertEquals(Route.START, route("connected", live = false))
        assertTrue(QuickConnect.isStale("connected", liveActive = false))
        assertFalse(QuickConnect.isStale("connected", liveActive = true))
        assertFalse(QuickConnect.isStale("disconnected", liveActive = false))
    }

    @Test
    fun `without a saved server the app opens to connect`() {
        val asked = mutableListOf<String>()
        assertEquals(Route.OPEN_APP, route("disconnected", live = false, snapshot = false, asked = asked))
        assertEquals(listOf("snapshot"), asked)
    }

    @Test
    fun `missing VPN consent opens the quick connect window before anything else`() {
        val asked = mutableListOf<String>()
        assertEquals(
            Route.CONSENT_WINDOW,
            route("error", live = false, consentMissing = true, blocked = true, asked = asked),
        )
        assertEquals(listOf("snapshot", "consent"), asked)
    }

    @Test
    fun `firmware that once swallowed a start goes straight to the window`() {
        assertEquals(Route.BLOCKED_WINDOW, route("disconnected", live = false, blocked = true))
    }

    @Test
    fun `otherwise the tile starts the service directly`() {
        val asked = mutableListOf<String>()
        assertEquals(Route.START, route("disconnected", live = false, asked = asked))
        assertEquals(listOf("snapshot", "consent", "blocked"), asked)
    }

    @Test
    fun `a stale record shows as disconnected`() {
        assertEquals("disconnected", QuickConnect.effectiveStatus("connecting", liveActive = false))
        assertEquals("connecting", QuickConnect.effectiveStatus("connecting", liveActive = true))
        assertEquals("error", QuickConnect.effectiveStatus("error", liveActive = false))
    }

    // binder отдаёт имя enum (running, stopped), prefs и liveStatus слова из statusName: плитка, виджет и нажатие
    // обязаны понимать оба словаря одинаково
    @Test
    fun `tile, widget and tap agree on both status vocabularies`() {
        for (status in VpnRunStatus.values()) {
            val active = status == VpnRunStatus.RUNNING || status == VpnRunStatus.STARTING
            for (word in listOf(statusName(status), status.name.lowercase())) {
                assertEquals(word, active, word in QuickConnect.ACTIVE_STATUSES)
                assertEquals(word, active, tileLook(word).active)
                assertEquals(word, status == VpnRunStatus.STARTING, tileLook(word).connecting)
                val look = HomeWidget.lookOf(word)
                val expected = when (status) {
                    VpnRunStatus.STOPPED -> HomeWidget.Look.OFF
                    VpnRunStatus.STARTING -> HomeWidget.Look.CONNECTING
                    VpnRunStatus.RUNNING -> HomeWidget.Look.ON
                    VpnRunStatus.ERROR -> HomeWidget.Look.ERROR
                }
                assertEquals(word, expected, look)
            }
        }
    }

    @Test
    fun `an unknown status leaves the tile off`() {
        assertFalse(tileLook("").active)
        assertFalse(tileLook("paused").active)
        assertEquals(HomeWidget.Look.OFF, HomeWidget.lookOf("paused"))
    }
}
