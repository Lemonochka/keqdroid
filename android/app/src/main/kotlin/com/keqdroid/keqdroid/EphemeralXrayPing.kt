package com.keqdroid.keqdroid



import android.util.Log

import java.io.File

import java.net.HttpURLConnection

import java.net.InetSocketAddress

import java.net.Proxy

import java.net.Socket

import java.net.URL

import java.util.UUID

import java.util.concurrent.Callable

import java.util.concurrent.Executors

import java.util.concurrent.TimeUnit

import java.util.concurrent.atomic.AtomicBoolean

import java.util.concurrent.locks.ReentrantLock

import kotlin.concurrent.withLock

import kotlin.math.max

import kotlin.math.min



/**

 * Starts a short-lived Xray process, performs HTTP via local SOCKS5 (noauth),

 * then kills the process.
 *
 * URL tests run concurrently: each one writes its own config file and gets its
 * own SOCKS port from Dart, so nothing here is shared between them. How many go
 * at once is decided in PingService (urlPingConcurrency) — one place, and it
 * applies to desktop too.
 *
 * Speed tests stay serialized: they measure bandwidth, and parallel downloads
 * would split the channel between themselves and report nonsense.

 */

object EphemeralXrayPing {

    /// Ядро замера, как его называет dart-сторона (`VpnBackend.wireValue`).

    const val CORE_XRAY = "xray"

    const val CORE_MIHOMO = "mihomo"

    /// Бинарь ядра. Оба лежат в nativeLibraryDir под именами `lib*.so`: APK
    /// распаковывает только то, что похоже на библиотеку, поэтому ядра там и
    /// названы так, хотя это обычные исполняемые файлы.

    private fun coreBinary(nativeLibraryDir: String, core: String): File =
        File(nativeLibraryDir, if (core == CORE_MIHOMO) "libmihomo.so" else "libxray.so")


    private const val TAG = "KEQDIS_PING"

    // Only the speed test takes it, see the class doc.

    private val lock = ReentrantLock()



    data class Result(

        val success: Boolean,

        val latencyMs: Int?,

        val error: String?,

        val httpStatus: Int?,

    )



    data class BatchItem(

        val id: String,

        val xrayConfigJson: String,

    )



    data class BatchResult(

        val id: String,

        val result: Result,

    )



    data class SpeedResult(

        val success: Boolean,

        val kbps: Int?,

        val error: String?,

    )



    data class SpeedBatchResult(

        val id: String,

        val result: SpeedResult,

    )



    fun urlTest(

        nativeLibraryDir: String,

        filesDir: File,

        assetDir: String,

        xrayConfigJson: String,

        socksPort: Int,

        testUrl: String,

        timeoutMs: Int,

    ): Result {

        return runSingle(

            nativeLibraryDir = nativeLibraryDir,

            filesDir = filesDir,

            assetDir = assetDir,

            xrayConfigJson = xrayConfigJson,

            socksPort = socksPort,

            testUrl = testUrl,

            timeoutMs = timeoutMs,

        )

    }



    /**
     * Runs several URL tests in one call — saves a MethodChannel round-trip per
     * server. Items share a single SOCKS port, so they go one after another;
     * running servers in parallel is PingService's job, and it hands every
     * measurement a port of its own.
     */

    fun urlTestBatch(

        nativeLibraryDir: String,

        filesDir: File,

        assetDir: String,

        socksPort: Int,

        items: List<BatchItem>,

        testUrl: String,

        timeoutMs: Int,

        keepAlive: Boolean = true,

        core: String = CORE_XRAY,

    ): List<BatchResult> {

        if (items.isEmpty()) return emptyList()

        val binary = coreBinary(nativeLibraryDir, core)

        if (!binary.exists()) {

            val err = Result(false, null, "${binary.name} not found", null)

            return items.map { BatchResult(it.id, err) }

        }

        return items.map { item ->

            BatchResult(

                id = item.id,

                result = runSingle(

                    nativeLibraryDir = nativeLibraryDir,

                    filesDir = filesDir,

                    assetDir = assetDir,

                    xrayConfigJson = item.xrayConfigJson,

                    socksPort = socksPort,

                    testUrl = testUrl,

                    timeoutMs = timeoutMs,

                    binary = binary,

                    keepAlive = keepAlive,

                    core = core,

                ),

            )

        }

    }



    data class MultiProbe(
        val id: String,
        val port: Int,
    )

    /**
     * Measures a whole batch with ONE core process.
     *
     * The config carries an inbound per server (MultiPingConfig on the Dart
     * side), so each probe reaches its own server through its own port. That is
     * what makes fifty servers possible on a phone: the limit was never startup
     * time, it was holding fifty Go runtimes at once.
     *
     * A batch fails as a whole on purpose. One unusable server takes the config
     * down with it, and rather than guess which one, the caller splits the batch
     * and retries — down to a single server, which is the old path.
     */
    fun urlTestMulti(
        nativeLibraryDir: String,
        filesDir: File,
        assetDir: String,
        configJson: String,
        probes: List<MultiProbe>,
        testUrl: String,
        timeoutMs: Int,
        keepAlive: Boolean = true,
        concurrency: Int = 16,
        core: String = CORE_XRAY,
    ): List<BatchResult> {
        if (probes.isEmpty()) return emptyList()

        val binary = coreBinary(nativeLibraryDir, core)
        if (!binary.exists()) {
            val err = Result(false, null, "${binary.name} not found", null)
            return probes.map { BatchResult(it.id, err) }
        }

        val configFile = File(filesDir, "xray_ping_multi_${UUID.randomUUID()}.json")
        var pid = -1
        var coreStartedAt = System.currentTimeMillis()
        // Первая удачная проба означает, что ядро дочитало конфиг: остальным
        // отказам в этом батче верим сразу, они уже про серверы.
        val coreAwake = AtomicBoolean(false)
        try {
            configFile.writeText(configJson, Charsets.UTF_8)
            coreStartedAt = System.currentTimeMillis()
            pid = NativeHelper.startCore(binary.absolutePath, configFile.absolutePath, assetDir, "", core)
            if (pid <= 0) {
                val err = Result(false, null, "failed to start $core for the batch (pid=$pid)", null)
                return probes.map { BatchResult(it.id, err) }
            }

            // Порты поднимаются разом, поэтому бюджет общий: первый ждёт старта
            // ядра, остальные к этому моменту уже слушают.
            val portWaitMs = min(timeoutMs, 8_000)
            for (probe in probes) {
                if (!waitForPort("127.0.0.1", probe.port, portWaitMs)) {
                    val err = Result(false, null, "port ${probe.port} not ready in the batch", null)
                    return probes.map { BatchResult(it.id, err) }
                }
            }

            val workers = min(max(1, concurrency), probes.size)
            val pool = Executors.newFixedThreadPool(workers)
            try {
                val tasks = probes.map { probe ->
                    Callable {
                        BatchResult(
                            probe.id,
                            probeAwaitingCore(
                                testUrl, probe.port, timeoutMs, keepAlive,
                                core = core,
                                coreStartedAt = coreStartedAt,
                                coreAwake = coreAwake,
                            ),
                        )
                    }
                }
                // Один срок на весь батч: пробы идут параллельно, и ждать надо
                // самую медленную, а не сумму их таймаутов.
                val futures = pool.invokeAll(tasks, (timeoutMs + 5_000).toLong(), TimeUnit.MILLISECONDS)
                return probes.mapIndexed { index, probe ->
                    runCatching { futures[index].get() }.getOrElse {
                        BatchResult(probe.id, Result(false, null, "probe cancelled: ${it.message}", null))
                    }
                }
            } finally {
                pool.shutdownNow()
            }
        } catch (e: Exception) {
            Log.e("KEQDIS", "urlTestMulti failed: ${e.message}")
            val err = Result(false, null, e.message ?: "batch failed", null)
            return probes.map { BatchResult(it.id, err) }
        } finally {
            if (pid > 0) {
                runCatching { android.os.Process.killProcess(pid) }
                var i = 0
                while (i < 4 && File("/proc/$pid").exists()) {
                    Thread.sleep(40)
                    i++
                }
            }
            runCatching { configFile.delete() }
        }
    }

    fun speedTest(

        nativeLibraryDir: String,

        filesDir: File,

        assetDir: String,

        xrayConfigJson: String,

        socksPort: Int,

        downloadUrl: String,

        timeoutMs: Int,

    ): SpeedResult = lock.withLock {

        runSpeedSingle(

            nativeLibraryDir = nativeLibraryDir,

            filesDir = filesDir,

            assetDir = assetDir,

            xrayConfigJson = xrayConfigJson,

            socksPort = socksPort,

            downloadUrl = downloadUrl,

            timeoutMs = timeoutMs,

        )

    }



    fun speedTestBatch(

        nativeLibraryDir: String,

        filesDir: File,

        assetDir: String,

        socksPort: Int,

        items: List<BatchItem>,

        downloadUrl: String,

        timeoutMs: Int,

        core: String = CORE_XRAY,

    ): List<SpeedBatchResult> = lock.withLock {

        if (items.isEmpty()) return@withLock emptyList()

        val binary = coreBinary(nativeLibraryDir, core)

        if (!binary.exists()) {

            val err = SpeedResult(false, null, "${binary.name} not found")

            return@withLock items.map { SpeedBatchResult(it.id, err) }

        }

        items.map { item ->

            SpeedBatchResult(

                id = item.id,

                result = runSpeedSingle(

                    nativeLibraryDir = nativeLibraryDir,

                    filesDir = filesDir,

                    assetDir = assetDir,

                    xrayConfigJson = item.xrayConfigJson,

                    socksPort = socksPort,

                    downloadUrl = downloadUrl,

                    timeoutMs = timeoutMs,

                    binary = binary,

                    core = core,

                ),

            )

        }

    }



    private fun runSingle(

        nativeLibraryDir: String,

        filesDir: File,

        assetDir: String,

        xrayConfigJson: String,

        socksPort: Int,

        testUrl: String,

        timeoutMs: Int,

        binary: File? = null,

        keepAlive: Boolean = true,

        core: String = CORE_XRAY,

    ): Result {

        val configFile = File(filesDir, "xray_ping_${UUID.randomUUID()}.json")

        var pid = -1

        try {

            configFile.writeText(xrayConfigJson, Charsets.UTF_8)

            val xrayBin = binary ?: coreBinary(nativeLibraryDir, core)

            if (!xrayBin.exists()) {

                return Result(false, null, "${xrayBin.name} not found", null)

            }



            // logName="" — ping/спидтест не пишут в файл логов соединения.
            val coreStartedAt = System.currentTimeMillis()

            pid = NativeHelper.startCore(xrayBin.absolutePath, configFile.absolutePath, assetDir, "", core)

            when {

                pid == -1 -> return Result(false, null, "Xray binary not found", null)

                pid == -2 -> return Result(false, null, "Xray config not found", null)

                pid == -4 -> return Result(false, null, "Xray crashed on startup", null)

                pid <= 0 -> return Result(false, null, "Failed to start Xray (pid=$pid)", null)

            }



            val portWaitMs = min(timeoutMs, 5_000)

            if (!waitForPort("127.0.0.1", socksPort, portWaitMs)) {

                return Result(false, null, "Xray SOCKS port $socksPort not ready", null)

            }



            return probeAwaitingCore(

                testUrl, socksPort, timeoutMs, keepAlive,

                core = core,

                coreStartedAt = coreStartedAt,

                coreAwake = null,

            )

        } finally {

            if (pid > 0) {

                try {

                    android.os.Process.killProcess(pid)

                } catch (_: Exception) {

                }

                // Brief wait so the port is released before the next server in a batch.

                var i = 0

                while (i < 4 && File("/proc/$pid").exists()) {

                    Thread.sleep(40)

                    i++

                }

            }

            runCatching { configFile.delete() }

        }

    }



    private fun runSpeedSingle(

        nativeLibraryDir: String,

        filesDir: File,

        assetDir: String,

        xrayConfigJson: String,

        socksPort: Int,

        downloadUrl: String,

        timeoutMs: Int,

        binary: File? = null,

        core: String = CORE_XRAY,

    ): SpeedResult {

        val configFile = File(filesDir, "xray_speed_${UUID.randomUUID()}.json")

        var pid = -1

        try {

            configFile.writeText(xrayConfigJson, Charsets.UTF_8)

            val xrayBin = binary ?: coreBinary(nativeLibraryDir, core)

            if (!xrayBin.exists()) {

                return SpeedResult(false, null, "${xrayBin.name} not found")

            }



            // logName="" — ping/спидтест не пишут в файл логов соединения.
            pid = NativeHelper.startCore(xrayBin.absolutePath, configFile.absolutePath, assetDir, "", core)

            when {

                pid == -1 -> return SpeedResult(false, null, "Xray binary not found")

                pid == -2 -> return SpeedResult(false, null, "Xray config not found")

                pid == -4 -> return SpeedResult(false, null, "Xray crashed on startup")

                pid <= 0 -> return SpeedResult(false, null, "Failed to start Xray (pid=$pid)")

            }



            val portWaitMs = min(timeoutMs, 6_000)

            if (!waitForPort("127.0.0.1", socksPort, portWaitMs)) {

                return SpeedResult(false, null, "Xray SOCKS port $socksPort not ready")

            }



            return downloadProbeViaSocks(downloadUrl, socksPort, timeoutMs)

        } finally {

            if (pid > 0) {

                try {

                    android.os.Process.killProcess(pid)

                } catch (_: Exception) {

                }

                var i = 0

                while (i < 4 && File("/proc/$pid").exists()) {

                    Thread.sleep(40)

                    i++

                }

            }

            runCatching { configFile.delete() }

        }

    }



    private fun waitForPort(host: String, port: Int, maxWaitMs: Int): Boolean {

        val deadline = System.currentTimeMillis() + maxWaitMs

        var sleepMs = 20L

        while (System.currentTimeMillis() < deadline) {

            if (isPortOpen(host, port)) return true

            Thread.sleep(sleepMs)

            sleepMs = min(sleepMs + 15, 80L)

        }

        return isPortOpen(host, port)

    }



    private fun isPortOpen(host: String, port: Int): Boolean {

        return try {

            Socket().use { it.connect(InetSocketAddress(host, port), 200) }

            true

        } catch (_: Exception) {

            false

        }

    }



    private fun ensureHttps(url: String): String {

        val trimmed = url.trim()

        if (trimmed.startsWith("http://", ignoreCase = true)) {

            return "https://" + trimmed.substring(7)

        }

        return trimmed

    }



    /// Сколько ядру дают на то, чтобы начать обслуживать соединения.
    ///
    /// Открытый порт готовности не означает: mihomo поднимает листенеры
    /// раньше, чем дочитывает конфиг, и до самого конца загрузки молча
    /// закрывает всё, что успело подключиться (tunnel.isHandle — status !=
    /// Running, ни строки в лог). Снаружи это неотличимо от мёртвого сервера:
    /// проба видит закрытое соединение. При живом туннеле ядро замера доходит
    /// до Running за 1.3-1.8 с (замерено на Pixel 6a; без туннеля — за
    /// полсекунды), и до этого момента падает ВЕСЬ батч разом — именно это и
    /// выглядело как «при включённом VPN пинг не работает».
    private const val CORE_WAKEUP_GRACE_MS = 3_000L

    /// Проба, которая не принимает загружающееся ядро за мёртвый сервер.
    ///
    /// Повтор только у mihomo и только в первые секунды жизни процесса: у
    /// xray листенеры поднимаются последними, там открытый порт и есть
    /// готовность. [coreAwake] снимает ожидание досрочно — как только кто-то
    /// в батче ответил, ядро точно работает.
    private fun probeAwaitingCore(
        testUrl: String,
        port: Int,
        timeoutMs: Int,
        keepAlive: Boolean,
        core: String,
        coreStartedAt: Long,
        coreAwake: AtomicBoolean?,
    ): Result {
        while (true) {
            val result = httpProbeViaSocks(testUrl, port, timeoutMs, keepAlive)
            if (result.success) {
                coreAwake?.set(true)
                return result
            }
            if (core != CORE_MIHOMO) return result
            if (coreAwake?.get() == true) return result
            if (System.currentTimeMillis() - coreStartedAt >= CORE_WAKEUP_GRACE_MS) return result
            Thread.sleep(200)
        }
    }

    private fun httpProbeViaSocks(
        url: String,
        socksPort: Int,
        timeoutMs: Int,
        keepAlive: Boolean = true,
    ): Result {

        val safeUrl = ensureHttps(url)

        val proxy = Proxy(Proxy.Type.SOCKS, InetSocketAddress("127.0.0.1", socksPort))

        var connection: HttpURLConnection? = null

        val connectTimeoutMs = min(timeoutMs, 6_000)
        val readTimeoutMs = min(timeoutMs, 8_000)
        return try {
            // Два запроса, берём лучший. Первый оплачивает DNS, TLS-рукопожатие и
            // прогрев цепочки — он меряет стоимость процедуры, а не сервер. Второй
            // идёт по уже поднятому соединению (пул HttpURLConnection переиспользует
            // его, пока никто не просил `Connection: close`) и показывает чистое
            // время ответа.
            var best: Result? = null
            for (attempt in 0 until if (keepAlive) 2 else 1) {
                val start = System.currentTimeMillis()
                connection = (URL(safeUrl).openConnection(proxy) as HttpURLConnection).apply {
                    // Всегда GET. Раньше на `generate_204` и `connecttest.txt` уходил
                    // HEAD — то есть на два пресета из трёх (gstatic-дефолт и
                    // Microsoft), и именно они у пользователей не отвечали, пока
                    // Cloudflare с GET работал. Экономии от HEAD тут нет: 204 без
                    // тела, connecttest.txt — 22 байта.
                    requestMethod = "GET"
                    connectTimeout = connectTimeoutMs
                    readTimeout = readTimeoutMs
                    instanceFollowRedirects = true
                    setRequestProperty("User-Agent", "KEQDIS/1.0")
                }

                val code = connection.responseCode
                val elapsed = (System.currentTimeMillis() - start).toInt()

                // Тело дочитываем всегда: недочитанный ответ не возвращает
                // соединение в пул, и второй запрос откроет новое — то есть
                // померит ровно то же, что первый.
                if (code != 204) {
                    runCatching {
                        connection.inputStream?.use { stream ->
                            val buf = ByteArray(1024)
                            while (stream.read(buf) >= 0) { /* до конца */ }
                        }
                    }
                }

                val ok = code in 200..399 || code == 204
                if (!ok) return Result(false, elapsed, "HTTP $code", code)
                if (best == null || elapsed < best.latencyMs!!) {
                    best = Result(true, elapsed, null, code)
                }
            }
            best!!
        } catch (e: Exception) {

            Log.w(TAG, "httpProbeViaSocks failed: ${e.message}")

            Result(false, null, e.message ?: e.javaClass.simpleName, null)

        } finally {

            connection?.disconnect()

        }

    }



    private fun downloadProbeViaSocks(

        downloadUrl: String,

        socksPort: Int,

        timeoutMs: Int,

    ): SpeedResult {

        val safeUrl = ensureHttps(downloadUrl)

        val proxy = Proxy(Proxy.Type.SOCKS, InetSocketAddress("127.0.0.1", socksPort))

        var connection: HttpURLConnection? = null

        val connectTimeoutMs = min(timeoutMs, 8_000)

        val readTimeoutMs = min(timeoutMs, 30_000)

        return try {

            connection = (URL(safeUrl).openConnection(proxy) as HttpURLConnection).apply {

                requestMethod = "GET"

                connectTimeout = connectTimeoutMs

                readTimeout = readTimeoutMs

                instanceFollowRedirects = true

                setRequestProperty("User-Agent", "KEQDIS/1.0")

            }

            val code = connection.responseCode

            if (code !in 200..399) {

                return SpeedResult(false, null, "HTTP $code")

            }

            val start = System.currentTimeMillis()

            var bytes = 0

            connection.inputStream.use { stream ->

                val buf = ByteArray(8192)

                while (true) {

                    val n = stream.read(buf)

                    if (n <= 0) break

                    bytes += n

                }

            }

            val elapsedMs = (System.currentTimeMillis() - start).coerceAtLeast(1)

            val seconds = elapsedMs / 1000.0

            if (bytes <= 0) {

                return SpeedResult(false, null, "No data received")

            }

            val kbps = (bytes * 8.0 / 1000.0 / seconds).toInt()

            SpeedResult(true, kbps, null)

        } catch (e: Exception) {

            Log.w(TAG, "downloadProbeViaSocks failed: ${e.message}")

            SpeedResult(false, null, e.message ?: e.javaClass.simpleName)

        } finally {

            connection?.disconnect()

        }

    }

}


