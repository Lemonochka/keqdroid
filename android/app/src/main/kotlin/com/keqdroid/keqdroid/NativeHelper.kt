package com.keqdroid.keqdroid

import java.io.File
import java.util.Collections

object NativeHelper {
    init { System.loadLibrary("keqdis_native") }

    private const val TAG = "KEQDIS"

    // Имена бинарей, которые мы запускаем через fork+execv. По ним же ищутся
    // осиротевшие процессы, см. killOrphans().
    private val coreBinaries = setOf(
        "libxray.so",
        "libmihomo.so",
        "libtun2socks.so",
    )

    // pid'ы ядер, запущенных ИМЕННО ЭТИМ процессом приложения.
    //
    // Единственный способ отличить своё живое ядро от чужого осиротевшего:
    // список живёт в памяти процесса и умирает вместе с ним, поэтому всё, что
    // нашлось в /proc и в списке не значится, запущено прошлой жизнью
    // приложения.
    private val livePids = Collections.synchronizedSet(mutableSetOf<Int>())

    @JvmStatic
    private external fun nativeStartTun2Socks(
        tunFd: Int,
        binPath: String,
        proxyUrl: String,
        logLevel: String,
        logPath: String,
        mtu: Int,
    ): Int

    @JvmStatic
    private external fun nativeStartCore(
        binPath: String,
        configPath: String,
        assetDir: String,
        logName: String,
        coreKind: String,
        tunFd: Int,
    ): Int

    // logLevel: уровень логов tun2socks. На `info` он печатает каждое соединение
    // строкой `[TCP] <сокет приложения> <-> <назначение>` — единственное место,
    // где виден исходный сокет; в лог xray попадает уже наш собственный, со
    // стороны SOCKS. logPath: полный путь к файлу логов, пустая строка —
    // логирование в файл выключено и пайп не создаётся вовсе.
    // mtu: ОБЯЗАН совпадать с тем, с которым поднят интерфейс VpnService. Своего
    // значения у fd-устройства tun2socks не знает и по умолчанию берёт 1500;
    // расхождение с интерфейсом даёт пакеты, которые netstack собрал, а ядро на
    // записи в tun отбросило.
    fun startTun2Socks(
        tunFd: Int,
        binPath: String,
        proxyUrl: String,
        logLevel: String,
        logPath: String,
        mtu: Int,
    ): Int = remember(
        nativeStartTun2Socks(tunFd, binPath, proxyUrl, logLevel, logPath, mtu),
    )

    // Запуск ядра прокси. logName: имя файла логов ядра внутри assetDir
    // (filesDir); пустая строка — файловое логирование выключено (используется
    // ping/спидтестом).
    //
    // coreKind: "xray" или "mihomo". От него зависит argv — xray хочет
    // `run -c <config>` и базы geo через XRAY_LOCATION_ASSET, mihomo —
    // `-d <dir> -f <config>` и берёт базы из рабочего каталога.
    //
    // tunFd: дескриптор TUN-устройства, когда туннелем владеет само ядро
    // (mihomo с `tun.file-descriptor`); -1 — ядро о туннеле не знает, пакеты
    // ему приносит tun2socks. Дескриптор переживает execv только со снятым
    // FD_CLOEXEC, и снимает его натив — см. forkexec.c.
    fun startCore(
        binPath: String,
        configPath: String,
        assetDir: String,
        logName: String,
        coreKind: String,
        tunFd: Int = -1,
    ): Int = remember(
        nativeStartCore(binPath, configPath, assetDir, logName, coreKind, tunFd),
    )

    private fun remember(pid: Int): Int {
        if (pid > 0) livePids.add(pid)
        return pid
    }

    // Прибить ядра, оставшиеся от прошлой жизни приложения.
    //
    // Ядро запускается двойным fork'ом и намеренно живёт отдельно от нас: так
    // оно переживает пересоздание сервиса. Обратная сторона — оно переживает и
    // смерть самого приложения (force stop, переустановка из `flutter run`,
    // отстрел системой): onDestroy при SIGKILL не приходит, убивать процесс
    // некому, и он остаётся сидеть на 2080.
    //
    // Дальше начинается неочевидное: новое ядро порт занять не может и работает
    // без SOCKS, а tun2socks подключается к СТАРОМУ ядру — с чужими
    // credentials. В логе это выглядит как `rejected username/password`, будто
    // сломалась авторизация, хотя сломан порядок запуска.
    //
    // Убиваем только то, чего нет в livePids: ephemeral-ядра пингов живут в
    // этом же процессе и сиротами не являются.
    //
    // Возвращает, скольких прибили: SIGKILL асинхронен, и вызывающему стоит
    // дождаться освобождения порта, прежде чем поднимать своё ядро.
    fun killOrphans(): Int {
        var killed = 0
        val mine = android.os.Process.myPid()
        // Сначала выкидываем из списка мёртвых. Иначе он растёт всю сессию —
        // каждый пинг это своё ядро — а когда pid пойдёт по второму кругу,
        // застрявшая в списке запись спрячет от нас настоящую сироту.
        synchronized(livePids) {
            livePids.removeAll { !File("/proc/$it").exists() }
        }
        val dirs = File("/proc").listFiles() ?: return 0
        for (dir in dirs) {
            val pid = dir.name.toIntOrNull() ?: continue
            if (pid == mine || livePids.contains(pid)) continue
            // /proc чужих процессов на Android нам не виден (hidepid), так что
            // под раздачу попадают только процессы нашего же uid.
            //
            // cmdline разделён нулями, а не пробелами: argv[0] — всё до первого.
            val argv0 = runCatching {
                File(dir, "cmdline").readBytes()
                    .toString(Charsets.UTF_8)
                    .substringBefore(Char.MIN_VALUE)
            }.getOrNull() ?: continue
            val binary = argv0.substringAfterLast('/')
            if (binary !in coreBinaries) continue
            android.util.Log.w(TAG, "killOrphans: killing stale $binary pid=$pid")
            runCatching { android.os.Process.killProcess(pid) }
            killed++
        }
        return killed
    }
}
