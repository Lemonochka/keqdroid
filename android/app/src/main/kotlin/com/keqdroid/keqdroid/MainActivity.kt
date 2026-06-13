package com.keqdroid.keqdroid

import android.app.Activity
import android.content.ComponentName
import androidx.activity.result.ActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.VpnService
import android.os.IBinder
import android.provider.Settings
import android.util.Base64
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.io.BufferedReader
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.io.InputStreamReader
import java.net.InetSocketAddress
import java.net.Socket

class MainActivity : FlutterFragmentActivity() {

    companion object {
        const val METHOD_CHANNEL         = "keqdis_vpn_channel"
        const val EVENT_CHANNEL          = "keqdis_vpn_status"
        const val EXTRA_LAUNCH_ACTION    = "action"
        private const val ICON_SIZE_PX   = 96
        private const val DEFAULT_SPEED_TEST_URL =
            "https://speed.cloudflare.com/__down?bytes=2000000"

        fun randomToken(length: Int): String {
            val chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
            val rng   = java.security.SecureRandom()
            return buildString(length) { repeat(length) { append(chars[rng.nextInt(chars.length)]) } }
        }
    }

    private val mainScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private var permissionRequestInFlight = false
    private var pendingPermissionResult: MethodChannel.Result? = null

    private val vpnPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { activityResult: ActivityResult ->
            permissionRequestInFlight = false
            pendingPermissionResult?.success(activityResult.resultCode == Activity.RESULT_OK)
            pendingPermissionResult = null
        }
    private var pendingSocksUsername: String? = null
    private var pendingSocksPassword: String? = null
    private var eventSink: EventChannel.EventSink? = null
    private var telemetryJob: Job? = null
    private var lastStatusError: String? = null
    private var vpnServiceBinder: KeqdisVpnService.LocalBinder? = null
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null

    // [FIX-UNBIND-CRASH] Отслеживаем, был ли bindService успешен,
    // чтобы не вызывать unbindService без привязки → IllegalArgumentException.
    private var serviceBound = false

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, binder: IBinder) {
            vpnServiceBinder = binder as KeqdisVpnService.LocalBinder
            vpnServiceBinder?.setStatusListener { status, extra ->
                lastStatusError = extra
                // EventSink.success/error ДОЛЖНЫ вызываться только из Main thread.
                // mainScope.launch гарантирует это — не меняйте на Dispatchers.IO.
                mainScope.launch {
                    emitVpnSnapshot(statusOverride = status, errorOverride = extra)
                }
            }
        }

        override fun onServiceDisconnected(name: ComponentName) {
            vpnServiceBinder?.setStatusListener(null)
            vpnServiceBinder = null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // [FIX-UNBIND-CRASH] Сохраняем результат bindService.
        serviceBound = bindService(
            Intent(this, KeqdisVpnService::class.java),
            serviceConnection,
            Context.BIND_AUTO_CREATE,
        )
        setupMethodChannel(flutterEngine)
        setupEventChannel(flutterEngine)
    }

    private fun setupMethodChannel(flutterEngine: FlutterEngine) {
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .also { ch ->
                ch.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "startVpn" -> {
                            val backend = call.argument<String>("vpnBackend") ?: "xray"
                            val socksPort       = call.argument<Int>("socksPort") ?: 2080
                            val serverName      = call.argument<String>("serverName")
                            val excludePackages = call.argument<List<*>>("excludePackages")
                                ?.filterIsInstance<String>() ?: emptyList()
                            val includePackages = call.argument<List<*>>("includePackages")
                                ?.filterIsInstance<String>() ?: emptyList()
                            when (backend) {
                                KeqdisVpnService.VPN_BACKEND_KPHTTP -> {
                                    val kphttpToml = call.argument<String>("kphttpTomlConfig") ?: run {
                                        result.error("INVALID_ARGS", "Missing kphttpTomlConfig", null)
                                        return@setMethodCallHandler
                                    }
                                    startVpnWithKphttp(
                                        kphttpToml,
                                        socksPort,
                                        excludePackages,
                                        includePackages,
                                        serverName,
                                        result,
                                    )
                                }
                                KeqdisVpnService.VPN_BACKEND_XRAY -> {
                                    val xrayConfig = call.argument<String>("xrayConfig") ?: run {
                                        result.error("INVALID_ARGS", "Missing xrayConfig", null)
                                        return@setMethodCallHandler
                                    }
                                    startVpnWithXray(
                                        xrayConfig,
                                        socksPort,
                                        excludePackages,
                                        includePackages,
                                        serverName,
                                        result,
                                    )
                                }
                                else -> result.error("UNSUPPORTED_BACKEND", "Unsupported VPN backend: $backend", null)
                            }
                        }
                        "stopVpn"              -> stopVpn(result)
                        "requestVpnPermission" -> requestVpnPermission(result)
                        "getSocksCredentials"  -> {
                            // Генерируем свежие credentials.
                            // Они будут переданы в сервис через Intent при startVpn —
                            // так Xray конфиг и tun2socks гарантированно используют одно и то же.
                            pendingSocksUsername = randomToken(16)
                            pendingSocksPassword = randomToken(24)
                            android.util.Log.d("KEQDIS", "getSocksCredentials: generated new credentials")
                            result.success(mapOf(
                                "username" to pendingSocksUsername!!,
                                "password" to pendingSocksPassword!!,
                            ))
                        }
                        "getPing" -> {
                            val addr    = call.argument<String>("address") ?: ""
                            val port    = call.argument<Int>("port") ?: 0
                            val timeout = call.argument<Int>("timeoutMs") ?: 5000
                            getPing(addr, port, timeout, result)
                        }
                        "getInstalledApps" -> {
                            val sys = call.argument<Boolean>("includeSystem") ?: false
                            getInstalledApps(sys, result)
                        }
                        "getStatus" -> getStatus(result)
                        "getDeviceModel" -> result.success(android.os.Build.MODEL ?: "Android Device")
                        "getLaunchAction" -> {
                            // Возвращает action из Intent если приложение было запущено из уведомления
                            val action = intent?.getStringExtra(EXTRA_LAUNCH_ACTION)
                            result.success(action)
                        }
                        "clearLaunchAction" -> {
                            intent?.removeExtra(EXTRA_LAUNCH_ACTION)
                            result.success(null)
                        }
                        "getAndroidId" -> {
                            val androidId = Settings.Secure.getString(
                                contentResolver,
                                Settings.Secure.ANDROID_ID
                            )
                            result.success(androidId ?: "")
                        }
                        "getXrayLogs" -> {
                            val maxLines = call.argument<Int>("maxLines") ?: 300
                            getXrayLogs(maxLines, result)
                        }
                        "xrayUrlTest" -> {
                            val xrayConfig = call.argument<String>("xrayConfig")
                            val socksPort = call.argument<Int>("socksPort")
                            val testUrl = call.argument<String>("testUrl")
                            val timeoutMs = call.argument<Int>("timeoutMs") ?: 15_000
                            if (xrayConfig.isNullOrBlank() || socksPort == null || socksPort <= 0) {
                                result.error("INVALID_ARGS", "Missing xrayConfig or socksPort", null)
                                return@setMethodCallHandler
                            }
                            xrayUrlTest(
                                xrayConfig,
                                socksPort,
                                testUrl ?: "https://connectivitycheck.gstatic.com/generate_204",
                                timeoutMs,
                                result,
                            )
                        }
                        "xrayUrlTestBatch" -> {
                            val socksPort = call.argument<Int>("socksPort")
                            val testUrl = call.argument<String>("testUrl")
                            val timeoutMs = call.argument<Int>("timeoutMs") ?: 15_000
                            @Suppress("UNCHECKED_CAST")
                            val rawItems = call.argument<List<Map<String, Any?>>>("items")
                            if (socksPort == null || socksPort <= 0 || rawItems.isNullOrEmpty()) {
                                result.error("INVALID_ARGS", "Missing socksPort or items", null)
                                return@setMethodCallHandler
                            }
                            xrayUrlTestBatch(
                                rawItems,
                                socksPort,
                                testUrl ?: "https://connectivitycheck.gstatic.com/generate_204",
                                timeoutMs,
                                result,
                            )
                        }
                        "xraySpeedTest" -> {
                            val xrayConfig = call.argument<String>("xrayConfig")
                            val socksPort = call.argument<Int>("socksPort")
                            val downloadUrl = call.argument<String>("downloadUrl")
                            val timeoutMs = call.argument<Int>("timeoutMs") ?: 20_000
                            if (xrayConfig.isNullOrBlank() || socksPort == null || socksPort <= 0) {
                                result.error("INVALID_ARGS", "Missing xrayConfig or socksPort", null)
                                return@setMethodCallHandler
                            }
                            xraySpeedTest(
                                xrayConfig,
                                socksPort,
                                downloadUrl ?: DEFAULT_SPEED_TEST_URL,
                                timeoutMs,
                                result,
                            )
                        }
                        "xraySpeedTestBatch" -> {
                            val socksPort = call.argument<Int>("socksPort")
                            val downloadUrl = call.argument<String>("downloadUrl")
                            val timeoutMs = call.argument<Int>("timeoutMs") ?: 20_000
                            @Suppress("UNCHECKED_CAST")
                            val rawItems = call.argument<List<Map<String, Any?>>>("items")
                            if (socksPort == null || socksPort <= 0 || rawItems.isNullOrEmpty()) {
                                result.error("INVALID_ARGS", "Missing socksPort or items", null)
                                return@setMethodCallHandler
                            }
                            xraySpeedTestBatch(
                                rawItems,
                                socksPort,
                                downloadUrl ?: DEFAULT_SPEED_TEST_URL,
                                timeoutMs,
                                result,
                            )
                        }
                        else        -> result.notImplemented()
                    }
                }
            }
    }

    private fun setupEventChannel(flutterEngine: FlutterEngine) {
        eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .also { ch ->
                ch.setStreamHandler(object : EventChannel.StreamHandler {
                    override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                        eventSink = sink
                        telemetryJob?.cancel()
                        telemetryJob = mainScope.launch {
                            while (isActive) {
                                emitVpnSnapshot()
                                val status = vpnServiceBinder?.getStatus()
                                val delayMs = if (status == VpnRunStatus.RUNNING) {
                                    2_000L
                                } else {
                                    5_000L
                                }
                                delay(delayMs)
                            }
                        }
                    }

                    override fun onCancel(args: Any?) {
                        telemetryJob?.cancel()
                        telemetryJob = null
                        eventSink = null
                    }
                })
            }
    }

    private fun emitVpnSnapshot(
        statusOverride: String? = null,
        errorOverride: String? = null,
    ) {
        val sink = eventSink ?: return
        val b = vpnServiceBinder
        if (b == null) {
            sink.success(mapOf("status" to "disconnected", "error" to errorOverride))
            return
        }
        val error = errorOverride ?: lastStatusError
        sink.success(
            mapOf(
                "status" to (statusOverride ?: b.getStatus().name.lowercase()),
                "error" to error,
                "uploadSpeed" to b.getUploadSpeed(),
                "downloadSpeed" to b.getDownloadSpeed(),
                "totalUpload" to b.getTotalUpload(),
                "totalDownload" to b.getTotalDownload(),
                "durationSeconds" to b.getDurationSeconds(),
            ),
        )
    }

    private fun startVpnWithXray(
        xrayConfig: String,
        socksPort: Int,
        excludePackages: List<String>,
        includePackages: List<String>,
        serverName: String?,
        result: MethodChannel.Result,
    ) {
        if (VpnService.prepare(this) != null) {
            result.error("PERMISSION_DENIED", "VPN permission not granted", null)
            return
        }

        // [FIX-CREDENTIALS-GUARD] Требуем явного вызова getSocksCredentials перед каждым startVpn.
        // Если pending credentials отсутствуют — возвращаем ошибку вместо тихой отправки пустых строк.
        val username = pendingSocksUsername
        val password = pendingSocksPassword
        if (username.isNullOrEmpty() || password.isNullOrEmpty()) {
            android.util.Log.e("KEQDIS", "startVpn: credentials missing — call getSocksCredentials first")
            result.error("NO_CREDENTIALS", "Call getSocksCredentials before startVpn", null)
            return
        }

        // [FIX-IO-ON-MAIN] writeConfig теперь async — IO выполняется в Dispatchers.IO,
        // result.success/error вызывается обратно в Main thread через mainScope.
        mainScope.launch {
            val xrayPath = try {
                withContext(Dispatchers.IO) { writeConfig(xrayConfig, "xray_config.json") }
            } catch (e: IOException) {
                // [FIX-CREDENTIALS-GUARD] При ошибке IO — НЕ сбрасываем credentials,
                // чтобы Dart мог повторить startVpn без повторного вызова getSocksCredentials.
                result.error("IO_ERROR", "Failed to write config: ${e.message}", null)
                return@launch
            }

            android.util.Log.d("KEQDIS", "startVpn: sending credentials to service")

            // Сохраняем порт в SharedPreferences чтобы WorkManager-изолят мог его прочитать
            // через StorageService.getSocksPort(). Flutter хранит ключи с префиксом "flutter."
            getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .edit()
                .putInt("flutter.keqdis_socks_port", socksPort)
                .apply()

            startService(Intent(this@MainActivity, KeqdisVpnService::class.java).apply {
                action = KeqdisVpnService.ACTION_START
                putExtra(KeqdisVpnService.EXTRA_VPN_BACKEND, KeqdisVpnService.VPN_BACKEND_XRAY)
                putExtra(KeqdisVpnService.EXTRA_XRAY_CONFIG, xrayPath)
                putExtra("socks_port", socksPort)
                putStringArrayListExtra("exclude_packages", ArrayList(excludePackages))
                putStringArrayListExtra("include_packages", ArrayList(includePackages))
                if (!serverName.isNullOrBlank()) {
                    putExtra(KeqdisVpnService.EXTRA_SERVER_NAME, serverName)
                }
                // [FIX-CREDENTIALS-GUARD] Передаём локальные переменные — они уже
                // проверены на non-null/non-empty выше. НЕ используем binder как fallback —
                // binder мог вернуть "" после cleanup().
                putExtra(KeqdisVpnService.EXTRA_SOCKS_USERNAME, username)
                putExtra(KeqdisVpnService.EXTRA_SOCKS_PASSWORD, password)
            })

            // [FIX-CREDENTIALS-GUARD] Сбрасываем pending credentials только ПОСЛЕ
            // успешной отправки Intent. При следующем startVpn Dart обязан снова
            // вызвать getSocksCredentials — это гарантирует свежие credentials
            // и синхронизацию с новым xray_config.json.
            pendingSocksUsername = null
            pendingSocksPassword = null

            result.success(null)
        }
    }

    private fun startVpnWithKphttp(
        kphttpToml: String,
        socksPort: Int,
        excludePackages: List<String>,
        includePackages: List<String>,
        serverName: String?,
        result: MethodChannel.Result,
    ) {
        if (VpnService.prepare(this) != null) {
            result.error("PERMISSION_DENIED", "VPN permission not granted", null)
            return
        }

        mainScope.launch {
            val configPath = try {
                withContext(Dispatchers.IO) { writeConfig(kphttpToml, "kphttp_client.toml") }
            } catch (e: IOException) {
                result.error("IO_ERROR", "Failed to write config: ${e.message}", null)
                return@launch
            }

            getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .edit()
                .putInt("flutter.keqdis_socks_port", socksPort)
                .apply()

            startService(Intent(this@MainActivity, KeqdisVpnService::class.java).apply {
                action = KeqdisVpnService.ACTION_START
                putExtra(KeqdisVpnService.EXTRA_VPN_BACKEND, KeqdisVpnService.VPN_BACKEND_KPHTTP)
                putExtra(KeqdisVpnService.EXTRA_KPHTTP_CONFIG, configPath)
                putExtra("socks_port", socksPort)
                putStringArrayListExtra("exclude_packages", ArrayList(excludePackages))
                putStringArrayListExtra("include_packages", ArrayList(includePackages))
                if (!serverName.isNullOrBlank()) {
                    putExtra(KeqdisVpnService.EXTRA_SERVER_NAME, serverName)
                }
            })

            result.success(null)
        }
    }

    private fun stopVpn(result: MethodChannel.Result) {
        // [FIX-CREDENTIALS-GUARD] При явной остановке — тоже сбрасываем pending credentials.
        // Если Dart вызвал getSocksCredentials, но потом stopVpn вместо startVpn —
        // credentials устаревают и должны быть перегенерированы перед следующим startVpn.
        pendingSocksUsername = null
        pendingSocksPassword = null
        startService(Intent(this, KeqdisVpnService::class.java).apply {
            action = KeqdisVpnService.ACTION_STOP
        })
        result.success(null)
    }

    private fun requestVpnPermission(result: MethodChannel.Result) {
        val intent = VpnService.prepare(this)
        if (intent == null) {
            permissionRequestInFlight = false
            result.success(true)
            return
        }

        // Диалог уже на экране — не заменяем pending result, иначе первый connect() потеряет ответ.
        if (permissionRequestInFlight && pendingPermissionResult != null) {
            result.error(
                "PERMISSION_IN_PROGRESS",
                "VPN permission dialog is already shown",
                null,
            )
            return
        }

        permissionRequestInFlight = true
        pendingPermissionResult = result
        vpnPermissionLauncher.launch(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // [FIX-NEW-INTENT] Обновляем intent, чтобы getLaunchAction вернул актуальный extra
        // когда приложение уже запущено в фоне и тайл открывает его через openAppForConnect().
        setIntent(intent)
        notifyLaunchActionIfNeeded()
    }

    private fun notifyLaunchActionIfNeeded() {
        if (intent?.getStringExtra(EXTRA_LAUNCH_ACTION) != "connect_from_notification") return
        mainScope.launch {
            methodChannel?.invokeMethod("onLaunchAction", mapOf("action" to "connect_from_notification"))
        }
    }

    private fun xrayUrlTest(
        xrayConfig: String,
        socksPort: Int,
        testUrl: String,
        timeoutMs: Int,
        result: MethodChannel.Result,
    ) {
        mainScope.launch {
            val payload = withContext(Dispatchers.IO) {
                runCatching {
                    EphemeralXrayPing.urlTest(
                        nativeLibraryDir = applicationInfo.nativeLibraryDir,
                        filesDir = filesDir,
                        assetDir = filesDir.absolutePath,
                        xrayConfigJson = xrayConfig,
                        socksPort = socksPort,
                        testUrl = testUrl,
                        timeoutMs = timeoutMs,
                    )
                }.getOrElse { e ->
                    EphemeralXrayPing.Result(false, null, e.message ?: "url test failed", null)
                }
            }
            result.success(
                mapOf(
                    "success" to payload.success,
                    "latencyMs" to payload.latencyMs,
                    "error" to payload.error,
                    "httpStatus" to payload.httpStatus,
                ),
            )
        }
    }

    private fun xrayUrlTestBatch(
        rawItems: List<Map<String, Any?>>,
        socksPort: Int,
        testUrl: String,
        timeoutMs: Int,
        result: MethodChannel.Result,
    ) {
        mainScope.launch {
            val payload = withContext(Dispatchers.IO) {
                runCatching {
                    val items = rawItems.mapNotNull { map ->
                        val id = map["id"] as? String ?: return@mapNotNull null
                        val config = map["xrayConfig"] as? String ?: return@mapNotNull null
                        if (config.isBlank()) return@mapNotNull null
                        EphemeralXrayPing.BatchItem(id, config)
                    }
                    EphemeralXrayPing.urlTestBatch(
                        nativeLibraryDir = applicationInfo.nativeLibraryDir,
                        filesDir = filesDir,
                        assetDir = filesDir.absolutePath,
                        socksPort = socksPort,
                        items = items,
                        testUrl = testUrl,
                        timeoutMs = timeoutMs,
                    )
                }.getOrElse { e ->
                    emptyList<EphemeralXrayPing.BatchResult>()
                        .also { android.util.Log.e("KEQDIS", "xrayUrlTestBatch failed: ${e.message}") }
                }
            }
            result.success(
                payload.map { item ->
                    mapOf(
                        "id" to item.id,
                        "success" to item.result.success,
                        "latencyMs" to item.result.latencyMs,
                        "error" to item.result.error,
                        "httpStatus" to item.result.httpStatus,
                    )
                },
            )
        }
    }

    private fun xraySpeedTest(
        xrayConfig: String,
        socksPort: Int,
        downloadUrl: String,
        timeoutMs: Int,
        result: MethodChannel.Result,
    ) {
        mainScope.launch {
            val payload = withContext(Dispatchers.IO) {
                runCatching {
                    EphemeralXrayPing.speedTest(
                        nativeLibraryDir = applicationInfo.nativeLibraryDir,
                        filesDir = filesDir,
                        assetDir = filesDir.absolutePath,
                        xrayConfigJson = xrayConfig,
                        socksPort = socksPort,
                        downloadUrl = downloadUrl,
                        timeoutMs = timeoutMs,
                    )
                }.getOrElse { e ->
                    EphemeralXrayPing.SpeedResult(false, null, e.message ?: "speed test failed")
                }
            }
            result.success(
                mapOf(
                    "success" to payload.success,
                    "kbps" to payload.kbps,
                    "error" to payload.error,
                ),
            )
        }
    }

    private fun xraySpeedTestBatch(
        rawItems: List<Map<String, Any?>>,
        socksPort: Int,
        downloadUrl: String,
        timeoutMs: Int,
        result: MethodChannel.Result,
    ) {
        mainScope.launch {
            val payload = withContext(Dispatchers.IO) {
                runCatching {
                    val items = rawItems.mapNotNull { map ->
                        val id = map["id"] as? String ?: return@mapNotNull null
                        val config = map["xrayConfig"] as? String ?: return@mapNotNull null
                        if (config.isBlank()) return@mapNotNull null
                        EphemeralXrayPing.BatchItem(id, config)
                    }
                    EphemeralXrayPing.speedTestBatch(
                        nativeLibraryDir = applicationInfo.nativeLibraryDir,
                        filesDir = filesDir,
                        assetDir = filesDir.absolutePath,
                        socksPort = socksPort,
                        items = items,
                        downloadUrl = downloadUrl,
                        timeoutMs = timeoutMs,
                    )
                }.getOrElse { e ->
                    emptyList<EphemeralXrayPing.SpeedBatchResult>()
                        .also { android.util.Log.e("KEQDIS", "xraySpeedTestBatch failed: ${e.message}") }
                }
            }
            result.success(
                payload.map { item ->
                    mapOf(
                        "id" to item.id,
                        "success" to item.result.success,
                        "kbps" to item.result.kbps,
                        "error" to item.result.error,
                    )
                },
            )
        }
    }

    private fun getPing(address: String, port: Int, timeoutMs: Int, result: MethodChannel.Result) {
        mainScope.launch {
            val ms = withContext(Dispatchers.IO) {
                runCatching {
                    val start = System.currentTimeMillis()
                    Socket().use { it.connect(InetSocketAddress(address, port), timeoutMs) }
                    (System.currentTimeMillis() - start).toInt()
                }.getOrNull()
            }
            // result.success вызывается в Main thread благодаря mainScope (Dispatchers.Main)
            result.success(ms)
        }
    }

    private fun getInstalledApps(includeSystem: Boolean, result: MethodChannel.Result) {
        mainScope.launch {
            val apps = withContext(Dispatchers.IO) {
                val pm = packageManager
                // [FIX-PERF] GET_META_DATA избыточен для получения имени/иконки.
                // Используем 0 — PackageManager сам подтянет нужное через getApplicationLabel/Icon.
                @Suppress("DEPRECATION")
                pm.getInstalledApplications(0)
                    .filter { info ->
                        val isSys = (info.flags and ApplicationInfo.FLAG_SYSTEM) != 0
                        includeSystem || !isSys
                    }
                    .map { info ->
                        val label   = pm.getApplicationLabel(info).toString()
                        val iconB64 = runCatching {
                            drawableToBase64(pm.getApplicationIcon(info.packageName))
                        }.getOrNull()
                        mapOf(
                            "packageName" to info.packageName,
                            "appName"     to label,
                            "isSystem"    to ((info.flags and ApplicationInfo.FLAG_SYSTEM) != 0),
                            "iconBase64"  to iconB64,
                        )
                    }
                    .sortedBy { it["appName"] as String }
            }
            result.success(apps)
        }
    }

    private fun drawableToBase64(d: Drawable): String {
        val size   = ICON_SIZE_PX
        val bmp    = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        d.setBounds(0, 0, size, size)
        d.draw(canvas)
        val out = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.PNG, 85, out)
        bmp.recycle()
        return Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
    }

    private fun getStatus(result: MethodChannel.Result) {
        val b = vpnServiceBinder
        result.success(
            if (b == null) {
                mapOf("status" to "disconnected")
            } else {
                mapOf(
                    "status"          to b.getStatus().name.lowercase(),
                    "uploadSpeed"     to b.getUploadSpeed(),
                    "downloadSpeed"   to b.getDownloadSpeed(),
                    "totalUpload"     to b.getTotalUpload(),
                    "totalDownload"   to b.getTotalDownload(),
                    "durationSeconds" to b.getDurationSeconds(),
                )
            }
        )
    }

    private fun getXrayLogs(maxLines: Int, result: MethodChannel.Result) {
        mainScope.launch {
            val logs = withContext(Dispatchers.IO) {
                runCatching {
                    val process = ProcessBuilder("logcat", "-d", "-v", "time", "-s", "KEQDIS", "KEQDIS_XRAY")
                        .redirectErrorStream(true)
                        .start()
                    val all = BufferedReader(InputStreamReader(process.inputStream)).use { reader ->
                        reader.readLines()
                    }
                    process.waitFor()
                    all.takeLast(maxLines.coerceIn(50, 2000)).joinToString("\n")
                }.getOrElse { e ->
                    "Unable to read logcat: ${e.message}"
                }
            }
            result.success(logs)
        }
    }

    // [FIX-IO-ON-MAIN] writeConfig теперь вызывается только из Dispatchers.IO.
    // Пробрасывает IOException — не глотает ошибки молча.
    @Throws(IOException::class)
    private fun writeConfig(json: String, fileName: String): String {
        val file = File(filesDir, fileName)
        file.writeText(json, Charsets.UTF_8)
        return file.absolutePath
    }

    override fun onDestroy() {
        vpnServiceBinder?.setStatusListener(null)

        // [FIX-UNBIND-CRASH] Вызываем unbindService только если привязка была успешна.
        if (serviceBound) {
            unbindService(serviceConnection)
            serviceBound = false
        }

        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel  = null

        permissionRequestInFlight = false
        pendingPermissionResult?.error(
            "ACTIVITY_DESTROYED",
            "Activity was destroyed while waiting for VPN permission",
            null,
        )
        pendingPermissionResult = null

        // [FIX-CREDENTIALS-GUARD] Сбрасываем pending credentials при уничтожении Activity.
        pendingSocksUsername = null
        pendingSocksPassword = null
        telemetryJob?.cancel()
        telemetryJob = null

        mainScope.cancel()
        super.onDestroy()
    }
}
