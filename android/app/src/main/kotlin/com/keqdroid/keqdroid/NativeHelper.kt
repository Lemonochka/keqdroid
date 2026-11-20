package com.keqdroid.keqdroid

import java.io.File
import java.util.Collections
import java.util.concurrent.locks.ReentrantReadWriteLock
import kotlin.concurrent.read
import kotlin.concurrent.write

// по этим же именам ищутся сироты
private val CORE_BINARIES = setOf(
    "libxray.so",
    "libmihomo.so",
)

// cmdline разделён нулями
internal fun orphanCoreName(cmdline: ByteArray): String? =
    cmdline.toString(Charsets.UTF_8)
        .substringBefore(Char.MIN_VALUE)
        .substringAfterLast('/')
        .takeIf { it in CORE_BINARIES }

// Только свои: список живёт в памяти процесса и умирает с ним, всё прочее в /proc запущено прошлой жизнью.
// Pid известен лишь после окна в 250 мс внутри nativeStartCore, и скан в это окно убивал пробы пинга
internal class CoreLaunches {
    private val gate = ReentrantReadWriteLock()
    private val pids = Collections.synchronizedSet(mutableSetOf<Int>())

    fun start(launch: () -> Int): Int = gate.read {
        launch().also { if (it > 0) pids.add(it) }
    }

    fun <T> sweep(block: (MutableSet<Int>) -> T): T = gate.write { block(pids) }
}

object NativeHelper {
    init { System.loadLibrary("keqdroid_native") }

    private const val TAG = "KEQDIS"

    private val launches = CoreLaunches()

    @JvmStatic
    private external fun nativeDialFailures(): Long

    // монотонно с запуска процесса, вызывающему важна разница двух чтений
    fun dialFailures(): Long = runCatching { nativeDialFailures() }.getOrDefault(0L)

    @JvmStatic
    private external fun nativeSetCoreLogLevel(level: Int)

    // 0 пропускает всё, дальше debug, info, warning, error, none; счётчик отказов видит все строки
    fun setCoreLogLevel(level: Int) {
        runCatching { nativeSetCoreLogLevel(level) }
    }

    @JvmStatic
    private external fun nativeTunReadyCount(): Long

    // строка info, в лог при warning не попадает, поэтому считается до порога
    fun tunReadyCount(): Long = runCatching { nativeTunReadyCount() }.getOrDefault(0L)

    @JvmStatic
    private external fun nativeAvoidEfficiencyCores(): Boolean

    // только для вызывающего потока
    fun avoidEfficiencyCores(): Boolean =
        runCatching { nativeAvoidEfficiencyCores() }.getOrDefault(false)

    @JvmStatic
    private external fun nativeStartCore(
        binPath: String,
        configPath: String,
        assetDir: String,
        logName: String,
        coreKind: String,
        tunFd: Int,
        ownerSocket: String,
    ): Int

    // пустой logName выключает файл, tunFd -1 запускает без туннеля; FD_CLOEXEC снимает нативная часть
    fun startCore(
        binPath: String,
        configPath: String,
        assetDir: String,
        logName: String,
        coreKind: String,
        tunFd: Int = -1,
        ownerSocket: String = "",
    ): Int = launches.start {
        nativeStartCore(binPath, configPath, assetDir, logName, coreKind, tunFd, ownerSocket)
    }

    // ядро живёт отдельно и переживает смерть приложения (force stop, flutter run), продолжая сидеть на 2080;
    // новое тогда порт не займёт, а прокси приложения ходит в старое с чужим паролем. Ядра замера свои и не трогаются
    fun killOrphans(): Int = launches.sweep { livePids ->
        var killed = 0
        val mine = android.os.Process.myPid()
        // мёртвых выкидываем: иначе список растёт всю сессию, и pid, пошедший по второму кругу, спрячет настоящую сироту
        synchronized(livePids) {
            livePids.removeAll { !File("/proc/$it").exists() }
        }
        val dirs = File("/proc").listFiles() ?: return@sweep 0
        for (dir in dirs) {
            val pid = dir.name.toIntOrNull() ?: continue
            if (pid == mine || livePids.contains(pid)) continue
            // чужой /proc на Android закрыт (hidepid), видим только свой uid
            val binary = runCatching { orphanCoreName(File(dir, "cmdline").readBytes()) }.getOrNull() ?: continue
            NativeLog.w(TAG, "killOrphans: killing stale $binary pid=$pid")
            runCatching { android.os.Process.killProcess(pid) }
            killed++
        }
        killed
    }
}
