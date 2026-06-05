package com.keqdroid.keqdroid



import android.util.Log

import java.io.File

import java.net.HttpURLConnection

import java.net.InetSocketAddress

import java.net.Proxy

import java.net.Socket

import java.net.URL

import java.util.UUID

import java.util.concurrent.locks.ReentrantLock

import kotlin.concurrent.withLock

import kotlin.math.min



/**

 * Starts a short-lived Xray process, performs HTTP via local SOCKS5 (noauth),

 * then kills the process. Serialized — only one URL test at a time.

 */

object EphemeralXrayPing {

    private const val TAG = "KEQDIS_PING"

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



    fun urlTest(

        nativeLibraryDir: String,

        filesDir: File,

        assetDir: String,

        xrayConfigJson: String,

        socksPort: Int,

        testUrl: String,

        timeoutMs: Int,

    ): Result = lock.withLock {

        runSingle(

            nativeLibraryDir = nativeLibraryDir,

            filesDir = filesDir,

            assetDir = assetDir,

            xrayConfigJson = xrayConfigJson,

            socksPort = socksPort,

            testUrl = testUrl,

            timeoutMs = timeoutMs,

        )

    }



    /** Runs many URL tests in one lock — avoids MethodChannel overhead per server. */

    fun urlTestBatch(

        nativeLibraryDir: String,

        filesDir: File,

        assetDir: String,

        socksPort: Int,

        items: List<BatchItem>,

        testUrl: String,

        timeoutMs: Int,

    ): List<BatchResult> = lock.withLock {

        if (items.isEmpty()) return@withLock emptyList()

        val binary = File(nativeLibraryDir, "libxray.so")

        if (!binary.exists()) {

            val err = Result(false, null, "libxray.so not found", null)

            return@withLock items.map { BatchResult(it.id, err) }

        }

        items.map { item ->

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

    ): Result {

        val configFile = File(filesDir, "xray_ping_${UUID.randomUUID()}.json")

        var pid = -1

        try {

            configFile.writeText(xrayConfigJson, Charsets.UTF_8)

            val xrayBin = binary ?: File(nativeLibraryDir, "libxray.so")

            if (!xrayBin.exists()) {

                return Result(false, null, "libxray.so not found", null)

            }



            pid = NativeHelper.startXray(xrayBin.absolutePath, configFile.absolutePath, assetDir)

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



            return httpProbeViaSocks(testUrl, socksPort, timeoutMs)

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



    private fun httpProbeViaSocks(url: String, socksPort: Int, timeoutMs: Int): Result {

        val safeUrl = ensureHttps(url)

        val proxy = Proxy(Proxy.Type.SOCKS, InetSocketAddress("127.0.0.1", socksPort))

        var connection: HttpURLConnection? = null

        val connectTimeoutMs = min(timeoutMs, 6_000)
        val readTimeoutMs = min(timeoutMs, 8_000)
        val useHead = safeUrl.contains("generate_204", ignoreCase = true) ||
            safeUrl.contains("connecttest.txt", ignoreCase = true)
        return try {
            val start = System.currentTimeMillis()
            connection = (URL(safeUrl).openConnection(proxy) as HttpURLConnection).apply {
                requestMethod = if (useHead) "HEAD" else "GET"
                connectTimeout = connectTimeoutMs
                readTimeout = readTimeoutMs

                instanceFollowRedirects = true

                setRequestProperty("User-Agent", "KEQDIS/1.0")

                setRequestProperty("Connection", "close")

            }

            val code = connection.responseCode

            val elapsed = (System.currentTimeMillis() - start).toInt()

            if (!useHead && code != 204) {

                connection.inputStream?.use { stream ->

                    val buf = ByteArray(128)

                    stream.read(buf)

                }

            }

            val ok = code in 200..399 || code == 204

            if (ok) {

                Result(true, elapsed, null, code)

            } else {

                Result(false, elapsed, "HTTP $code", code)

            }

        } catch (e: Exception) {

            Log.w(TAG, "httpProbeViaSocks failed: ${e.message}")

            Result(false, null, e.message ?: e.javaClass.simpleName, null)

        } finally {

            connection?.disconnect()

        }

    }

}


