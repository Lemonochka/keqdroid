package com.keqdroid.keqdroid

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SessionCredentialsTest {
    private val dart = ProxyCredentials("dart-user", "dart-pass")
    private val pending = ProxyCredentials("pending-user", "pending-pass")
    private val core = ProxyCredentials("core-user", "core-pass")
    private val saved = ProxyCredentials("saved-user", "saved-pass")
    private val empty = ProxyCredentials("", "")

    @Test
    fun `start takes the password Dart wrote into the config`() {
        assertEquals(dart, startCredentials(dart, pending))
    }

    @Test
    fun `start falls back to the generated password for an older Dart side`() {
        assertEquals(pending, startCredentials(null, pending))
        assertEquals(pending, startCredentials(empty, pending))
        assertEquals(pending, startCredentials(ProxyCredentials("dart-user", ""), pending))
    }

    @Test
    fun `start without any password is refused`() {
        assertNull(startCredentials(null, null))
        assertNull(startCredentials(empty, empty))
    }

    @Test
    fun `the app gets the password of the running core`() {
        assertEquals(core, activeCredentials(core, saved))
    }

    @Test
    fun `before the binder is bound the saved core password is used`() {
        assertEquals(saved, activeCredentials(null, saved))
        assertEquals(saved, activeCredentials(empty, saved))
    }

    @Test
    fun `no running core means no password`() {
        assertNull(activeCredentials(null, empty))
        assertNull(activeCredentials(null, null))
    }
}
