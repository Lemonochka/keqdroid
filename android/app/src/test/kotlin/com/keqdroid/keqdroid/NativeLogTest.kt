package com.keqdroid.keqdroid

import com.keqdroid.keqdroid.RoboSession.context
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.File

@RunWith(RobolectricTestRunner::class)
class NativeLogTest {
    private val log get() = File(context.filesDir, NativeLog.FILE_NAME)

    // файл журнала заводится один раз на процесс, а песочница Robolectric переживает тест
    private fun forgetFile() {
        NativeLog::class.java.getDeclaredField("file").apply { isAccessible = true }.set(null, null)
    }

    @Before
    fun fresh() {
        forgetFile()
        NativeLog.init(context)
    }

    @Test
    fun `info, warnings and errors reach the app's journal, debug does not`() {
        NativeLog.i("T", "one")
        NativeLog.w("T", "two")
        NativeLog.e("T", "three")
        NativeLog.d("T", "four")
        val text = NativeLog.read()
        assertTrue(text, text.contains("[INFO] T: one\n"))
        assertTrue(text, text.contains("[WARN] T: two\n"))
        assertTrue(text, text.contains("[ERROR] T: three\n"))
        assertFalse(text, text.contains("four"))
        assertTrue(Regex("""^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3} \[INFO]""").containsMatchIn(text))
    }

    @Test
    fun `an error keeps its stack trace`() {
        NativeLog.e("T", "boom", IllegalStateException("why"))
        val text = NativeLog.read()
        assertTrue(text, text.contains("[ERROR] T: boom\njava.lang.IllegalStateException: why"))
        assertTrue(text, text.contains("\tat com.keqdroid.keqdroid.NativeLogTest"))
    }

    @Test
    fun `the journal rotates past 256 KB and keeps the previous part`() {
        val line = "x".repeat(1000)
        repeat(300) { NativeLog.i("T", "$it $line") }
        assertTrue(File(log.path + ".1").exists())
        assertTrue(log.length() < 256 * 1024)
        val text = NativeLog.read()
        assertTrue(text.contains("[INFO] T: 0 x"))
        assertTrue(text.contains("[INFO] T: 299 x"))
    }

    @Test
    fun `only one previous part is kept`() {
        val line = "x".repeat(1000)
        repeat(600) { NativeLog.i("T", "$it $line") }
        val text = NativeLog.read()
        assertFalse(text.contains("[INFO] T: 0 x"))
        assertTrue(text.contains("[INFO] T: 599 x"))
    }

    @Test
    fun `reading is capped from the start`() {
        NativeLog.i("T", "a".repeat(500))
        NativeLog.i("T", "end")
        val text = NativeLog.read(maxChars = 20)
        assertEquals(20, text.length)
        assertTrue(text.endsWith("T: end\n"))
    }

    @Test
    fun `before init nothing is written`() {
        forgetFile()
        NativeLog.i("T", "lost")
        assertEquals("", NativeLog.read())
        NativeLog.init(context)
        assertFalse(NativeLog.read().contains("lost"))
    }
}
