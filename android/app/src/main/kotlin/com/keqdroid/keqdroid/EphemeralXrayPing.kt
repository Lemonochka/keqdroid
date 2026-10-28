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



// URL-тесты идут параллельно: у каждого свой файл конфига и свой SOCKS-порт от Dart, сколько разом решает PingService.
// спидтест последовательно: параллельные загрузки делили бы канал и мерили чушь

object EphemeralXrayPing {

    // имена как у VpnBackend.wireValue в Dart

    const val CORE_XRAY = "xray"

    const val CORE_MIHOMO = "mihomo"

    // ядра названы lib*.so: APK распаковывает только то, что похоже на библиотеку

    private fun coreBinary(nativeLibraryDir: String, core: String): File =
        File(nativeLibraryDir, if (core == CORE_MIHOMO) "libmihomo.so" else "libxray.so")


    private const val TAG = "KEQDIS_PING"

    // его берёт только спидтест

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



    // у элементов один SOCKS-порт, поэтому по очереди, параллель по серверам делает PingService

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

    // один процесс ядра на весь батч: телефон упирался не во время старта, а в пятьдесят рантаймов Go разом.
    // не поднялось ядро, значит пустой список: по нему Dart делит батч вплоть до одного сервера.
    // список отказов он принял бы за ответ, и десяток живых серверов уходил в красные из-за одного
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
        onEach: ((BatchResult) -> Unit)? = null,
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
        // первая удачная проба значит, что ядро дочитало конфиг, остальным отказам батча верим сразу
        val coreAwake = AtomicBoolean(false)
        try {
            configFile.writeText(configJson, Charsets.UTF_8)
            coreStartedAt = System.currentTimeMillis()
            pid = NativeHelper.startCore(binary.absolutePath, configFile.absolutePath, assetDir, "", core)
            if (pid <= 0) {
                NativeLog.w("KEQDIS", "urlTestMulti: $core did not start for ${probes.size} probes (pid=$pid), splitting")
                return emptyList()
            }

            // порты поднимаются разом, бюджет общий: первый ждёт старта ядра
            val portWaitMs = min(timeoutMs, 8_000)
            for (probe in probes) {
                if (!waitForPort("127.0.0.1", probe.port, portWaitMs)) {
                    NativeLog.w("KEQDIS", "urlTestMulti: port ${probe.port} not ready for ${probes.size} probes, splitting")
                    return emptyList()
                }
            }

            val workers = min(max(1, concurrency), probes.size)
            val pool = Executors.newFixedThreadPool(workers)
            try {
                val tasks = probes.map { probe ->
                    Callable {
                        val item = BatchResult(
                            probe.id,
                            probeAwaitingCore(
                                testUrl, probe.port, timeoutMs, keepAlive,
                                core = core,
                                coreStartedAt = coreStartedAt,
                                coreAwake = coreAwake,
                            ),
                        )
                        // сразу, а не по концу батча: батч держит до таймаута самый медленный
                        onEach?.let { runCatching { it(item) } }
                        item
                    }
                }
                // пробы параллельны, ждём самую медленную, а не сумму таймаутов
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
            NativeLog.e("KEQDIS", "urlTestMulti failed: ${e.message}")
            return emptyList()
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



            // пустой logName: замер не пишет в лог соединения
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

                // ждём, пока порт освободится для следующего сервера

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



    // открытый порт у mihomo ещё не готовность: листенеры поднимаются раньше конца загрузки конфига,
    // и всё подключившееся до Running закрывается молча. при живом туннеле это 1.3-1.8 с на Pixel 6a
    private const val CORE_WAKEUP_GRACE_MS = 3_000L

    // повтор только у mihomo: у xray листенеры поднимаются последними. coreAwake снимает ожидание, как только кто-то в батче ответил
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
            // два запроса, берём лучший: первый платит за DNS и TLS, второй по тому же соединению меряет сервер
            var best: Result? = null
            for (attempt in 0 until if (keepAlive) 2 else 1) {
                val start = System.currentTimeMillis()
                connection = (URL(safeUrl).openConnection(proxy) as HttpURLConnection).apply {
                    // всегда GET: на HEAD generate_204 и connecttest.txt у людей не отвечали, а Cloudflare с GET работал
                    requestMethod = "GET"
                    connectTimeout = connectTimeoutMs
                    readTimeout = readTimeoutMs
                    instanceFollowRedirects = true
                    setRequestProperty("User-Agent", "KEQDIS/1.0")
                }

                val code = connection.responseCode
                val elapsed = (System.currentTimeMillis() - start).toInt()

                // тело дочитываем: иначе соединение не вернётся в пул, и второй запрос померит то же, что первый
                if (code != 204) {
                    runCatching {
                        connection.inputStream?.use { stream ->
                            val buf = ByteArray(1024)
                            while (stream.read(buf) >= 0) { }
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

            // мимо NativeLog: мёртвый сервер в замере не сбой приложения, а прогон подписки вытеснил бы из журнала всё
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

            // тоже мимо NativeLog
            Log.w(TAG, "downloadProbeViaSocks failed: ${e.message}")

            SpeedResult(false, null, e.message ?: e.javaClass.simpleName)

        } finally {

            connection?.disconnect()

        }

    }

}


