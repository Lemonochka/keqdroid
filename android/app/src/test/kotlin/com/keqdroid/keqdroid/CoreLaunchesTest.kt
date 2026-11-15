package com.keqdroid.keqdroid

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CoreLaunchesTest {

    @Test
    fun `a sweep waits for a core still in its start window and sees it as ours`() {
        val launches = CoreLaunches()
        val inWindow = CountDownLatch(1)
        val release = CountDownLatch(1)
        val starter = thread {
            launches.start { inWindow.countDown(); release.await(); 42 }
        }
        assertTrue(inWindow.await(2, TimeUnit.SECONDS))

        val seenOurs = AtomicReference<Boolean?>(null)
        val sweeper = thread { seenOurs.set(launches.sweep { 42 in it }) }
        sweeper.join(300)
        assertTrue("the sweep ran while a core was starting", sweeper.isAlive)

        release.countDown()
        sweeper.join(2000)
        starter.join(2000)
        assertEquals(true, seenOurs.get())
    }

    @Test
    fun `parallel starts do not wait for each other`() {
        val launches = CoreLaunches()
        val bothInWindow = CountDownLatch(2)
        val starters = (1..2).map { pid ->
            thread {
                launches.start {
                    bothInWindow.countDown()
                    bothInWindow.await(2, TimeUnit.SECONDS)
                    pid
                }
            }
        }
        assertTrue(bothInWindow.await(2, TimeUnit.SECONDS))
        starters.forEach { it.join(2000) }
        assertEquals(setOf(1, 2), launches.sweep { it.toSet() })
    }

    @Test
    fun `a failed start is not remembered`() {
        val launches = CoreLaunches()
        assertEquals(-4, launches.start { -4 })
        assertFalse(launches.sweep { it.isNotEmpty() })
    }
}
