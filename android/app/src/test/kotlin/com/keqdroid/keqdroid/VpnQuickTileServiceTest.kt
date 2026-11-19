package com.keqdroid.keqdroid

import android.content.Intent
import android.os.Looper
import android.os.SystemClock
import com.keqdroid.keqdroid.RoboSession.context
import com.keqdroid.keqdroid.RoboSession.saveSnapshot
import com.keqdroid.keqdroid.RoboSession.setLiveStatus
import com.keqdroid.keqdroid.RoboSession.setStartAcceptedAt
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.shadows.ShadowVpnService
import java.time.Duration

@RunWith(RobolectricTestRunner::class)
class VpnQuickTileServiceTest {

    @Before
    fun consentGiven() = ShadowVpnService.setPrepareResult(null)

    @After
    fun reset() {
        setLiveStatus("disconnected")
        setStartAcceptedAt(0L)
    }

    private fun tapTile() = Robolectric.buildService(VpnQuickTileService::class.java).create().get().onClick()

    private fun waitPastTheCheck() = shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(3))

    private fun startedActivity(): Intent? = shadowOf(RuntimeEnvironment.getApplication()).nextStartedActivity

    @Test
    fun `a start the service took and then lost keeps the tile starting directly`() {
        saveSnapshot()
        tapTile()
        // сервис принял команду, а старт тут же упал или его выключили вторым нажатием
        setStartAcceptedAt(SystemClock.elapsedRealtime())
        setLiveStatus("disconnected")
        waitPastTheCheck()

        assertFalse(QuickConnect.directStartBlocked(context))
        assertNull(startedActivity())
    }

    @Test
    fun `a start the firmware swallowed opens the window and is remembered`() {
        saveSnapshot()
        tapTile()
        waitPastTheCheck()

        assertTrue(QuickConnect.directStartBlocked(context))
        assertEquals(QuickConnectActivity::class.java.name, startedActivity()?.component?.className)
    }
}
