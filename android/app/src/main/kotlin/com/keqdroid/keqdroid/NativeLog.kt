package com.keqdroid.keqdroid

import android.content.Context
import android.util.Log
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// logcat приложению на Android 13+ не прочитать, а этот файл читает экран Журнал приложения, формат как у app.log.
// debug в файл не идёт: плитка пишет его на каждое открытие шторки
object NativeLog {
    const val FILE_NAME = "native.log"

    // как у app.log: столько ещё перешлют, а причина обычно в конце; старая половина в .1
    private const val MAX_BYTES = 256 * 1024L

    @Volatile private var file: File? = null

    fun init(context: Context) {
        if (file == null) file = File(context.filesDir, FILE_NAME)
    }

    fun d(tag: String, msg: String) {
        Log.d(tag, msg)
    }

    fun i(tag: String, msg: String) {
        Log.i(tag, msg)
        append("INFO", tag, msg, null)
    }

    fun w(tag: String, msg: String, tr: Throwable? = null) {
        Log.w(tag, msg, tr)
        append("WARN", tag, msg, tr)
    }

    fun e(tag: String, msg: String, tr: Throwable? = null) {
        Log.e(tag, msg, tr)
        append("ERROR", tag, msg, tr)
    }

    fun read(maxChars: Int = 512 * 1024): String {
        val current = file ?: return ""
        return runCatching {
            val previous = File(current.path + ".1")
            val text = (if (previous.exists()) previous.readText() else "") +
                (if (current.exists()) current.readText() else "")
            text.takeLast(maxChars)
        }.getOrDefault("")
    }

    @Synchronized
    private fun append(level: String, tag: String, msg: String, tr: Throwable?) {
        val f = file ?: return
        runCatching {
            if (f.length() > MAX_BYTES) {
                val previous = File(f.path + ".1")
                previous.delete()
                f.renameTo(previous)
            }
            val stamp = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US).format(Date())
            val trace = tr?.let { "\n" + Log.getStackTraceString(it).trimEnd() } ?: ""
            f.appendText("$stamp [$level] $tag: $msg$trace\n")
        }
    }
}
