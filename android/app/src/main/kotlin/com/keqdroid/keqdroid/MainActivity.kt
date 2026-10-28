package com.keqdroid.keqdroid

import android.app.Activity
import android.app.WallpaperManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import androidx.activity.result.ActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.ServiceConnection
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.ConnectivityManager
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.system.OsConstants
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
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket

class MainActivity : FlutterFragmentActivity() {

    companion object {
        const val METHOD_CHANNEL         = "keqdis_vpn_channel"
        const val EVENT_CHANNEL          = "keqdis_vpn_status"
        const val PING_PROGRESS_CHANNEL  = "keqdis_ping_progress"
        const val EXTRA_LAUNCH_ACTION    = "action"
        // те же строки в res/xml/shortcuts.xml и в servers_tab на стороне Dart
        const val LAUNCH_ACTION_CONNECT    = "connect_from_notification"
        const val LAUNCH_ACTION_DISCONNECT = "disconnect_from_shortcut"
        private val LAUNCH_ACTIONS = setOf(
            LAUNCH_ACTION_CONNECT,
            LAUNCH_ACTION_DISCONNECT,
        )
        private const val ICON_SIZE_PX   = 96
        // отдельно от FlutterSharedPreferences: читаем в onCreate, до подъёма Flutter
        private const val PREFS_WINDOW = "keqdis_window"
        private const val KEY_WINDOW_BACKGROUND = "window_background"
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
    private var pendingSaveBytes: ByteArray? = null
    private var pendingSaveResult: MethodChannel.Result? = null

    private val saveDocumentLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { activityResult: ActivityResult ->
            val result = pendingSaveResult ?: return@registerForActivityResult
            val bytes = pendingSaveBytes
            pendingSaveResult = null
            pendingSaveBytes = null
            val uri = activityResult.data?.data
            if (activityResult.resultCode != Activity.RESULT_OK || uri == null || bytes == null) {
                result.success(null)
                return@registerForActivityResult
            }
            mainScope.launch {
                try {
                    withContext(Dispatchers.IO) { writeDocument(uri, bytes) }
                    result.success(uri.toString())
                } catch (e: Exception) {
                    result.error("SAVE_FAILED", e.message ?: e.javaClass.simpleName, null)
                }
            }
        }

    private var pendingSocksUsername: String? = null
    private var pendingSocksPassword: String? = null

    // ссылка холодного старта, Dart заберёт её через getPendingDeepLink, когда поднимется UI
    private var pendingDeepLink: String? = null
    private var eventSink: EventChannel.EventSink? = null
    private var telemetryJob: Job? = null
    private var lastStatusError: String? = null
    private var vpnServiceBinder: KeqdisVpnService.LocalBinder? = null
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null

    // нет слушателя, молчим: итог всё равно придёт ответом на вызов
    private var pingProgressChannel: EventChannel? = null
    private var pingProgressSink: EventChannel.EventSink? = null

    // unbindService без привязки кидает IllegalArgumentException
    private var serviceBound = false
    private var vpnStatusReceiverRegistered = false

    // статус от плитки и уведомления, пока binder не переподключился
    private val vpnStatusReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != KeqdisVpnService.BROADCAST_VPN_STATUS_CHANGED) return
            val status = intent.getStringExtra("status")
            mainScope.launch {
                emitVpnSnapshot(statusOverride = status)
                // и через MethodChannel: поток EventChannel может быть ещё не открыт
                try {
                    methodChannel?.invokeMethod("onVpnStatusSnapshot", mapOf("status" to status))
                } catch (_: Exception) {
                    // движок мог уже отцепиться
                }
            }
        }
    }

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, binder: IBinder) {
            vpnServiceBinder = binder as KeqdisVpnService.LocalBinder
            vpnServiceBinder?.setStatusListener { status, extra ->
                lastStatusError = extra
                // EventSink зовётся только с main thread
                mainScope.launch {
                    emitVpnSnapshot(statusOverride = status, errorOverride = extra)
                }
            }
            mainScope.launch { emitVpnSnapshot() }
        }

        override fun onServiceDisconnected(name: ComponentName) {
            vpnServiceBinder?.setStatusListener(null)
            vpnServiceBinder = null
            serviceBound = false
            ensureVpnServiceBound()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // фон окна цвета приложения, а не системы: NormalTheme переключается тёмной темой системы,
        // и на HyperOS под панелью навигации торчала белая полоска. запомненный цвет нужен до первого кадра
        rememberedWindowBackground()?.let { applyWindowBackground(it) }
        pendingDeepLink = deepLinkFrom(intent)
    }

    private fun applyWindowBackground(color: Int) {
        window.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(color))
    }

    private fun rememberWindowBackground(color: Int) {
        getSharedPreferences(PREFS_WINDOW, Context.MODE_PRIVATE)
            .edit()
            .putInt(KEY_WINDOW_BACKGROUND, color)
            .apply()
    }

    private fun rememberedWindowBackground(): Int? {
        val prefs = getSharedPreferences(PREFS_WINDOW, Context.MODE_PRIVATE)
        if (!prefs.contains(KEY_WINDOW_BACKGROUND)) return null
        return prefs.getInt(KEY_WINDOW_BACKGROUND, 0)
    }

    private fun deepLinkFrom(intent: Intent?): String? =
        if (intent?.action == Intent.ACTION_VIEW) intent.data?.toString() else null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        XrayGeoAssets.ensure(this, filesDir)
        ensureVpnServiceBound()
        setupMethodChannel(flutterEngine)
        setupEventChannel(flutterEngine)
        CardMedia(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        pingProgressChannel = EventChannel(
            flutterEngine.dartExecutor.binaryMessenger, PING_PROGRESS_CHANNEL,
        ).also { ch ->
            ch.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                    pingProgressSink = sink
                }

                override fun onCancel(args: Any?) {
                    pingProgressSink = null
                }
            })
        }
        registerVpnStatusReceiver()
        // после setupMethodChannel: без канала цвета ушли бы в пустоту
        startWallpaperColorsWatch()
    }

    override fun onResume() {
        super.onResume()
        ensureVpnServiceBound()
        mainScope.launch { emitVpnSnapshot() }
    }

    private fun ensureVpnServiceBound() {
        if (serviceBound && vpnServiceBinder != null) return
        serviceBound = bindService(
            Intent(this, KeqdisVpnService::class.java),
            serviceConnection,
            Context.BIND_AUTO_CREATE,
        )
    }

    private fun registerVpnStatusReceiver() {
        if (vpnStatusReceiverRegistered) return
        // статус берётся из самого сообщения: до Android 13 без ContextCompat его подделывало любое приложение
        ContextCompat.registerReceiver(
            this,
            vpnStatusReceiver,
            IntentFilter(KeqdisVpnService.BROADCAST_VPN_STATUS_CHANGED),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        vpnStatusReceiverRegistered = true
    }

    private fun readQsVpnStatus(): String =
        getSharedPreferences(KeqdisVpnService.PREFS_QS, Context.MODE_PRIVATE)
            .getString(KeqdisVpnService.KEY_QS_STATUS, "disconnected")
            ?.lowercase()
            ?: "disconnected"

    private fun readQsVpnError(): String? =
        getSharedPreferences(KeqdisVpnService.PREFS_QS, Context.MODE_PRIVATE)
            .getString(KeqdisVpnService.KEY_QS_ERROR, null)

    // dynamic_color молчит, если OEM не выставил флаг Material You (Realme, OneUI), хотя system_accent1_* заполнены.
    // тогда читаем ресурс сами как запасной сид
    private fun readSystemAccentColor(): Int? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return null
        return runCatching {
            @Suppress("DEPRECATION")
            resources.getColor(android.R.color.system_accent1_500, theme)
        }.getOrNull()
    }

    // обои читаются публичным API на любой прошивке, а Material You и сам выводит палитру из них
    private fun readWallpaperAccentColor(): Int? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O_MR1) return null
        return runCatching {
            WallpaperManager.getInstance(this)
                .getWallpaperColors(WallpaperManager.FLAG_SYSTEM)
                ?.primaryColor
                ?.toArgb()
        }.getOrNull()
    }

    // ключ строкой: THEME_CUSTOMIZATION_OVERLAY_PACKAGES помечен @hide.
    // accent_color это форма до Android 13, прошивки отстают на пару лет
    private fun readThemeSettingSeed(): Int? = runCatching {
        val raw = Settings.Secure.getString(
            contentResolver,
            "theme_customization_overlay_packages",
        )
        if (raw.isNullOrBlank()) return null
        val json = org.json.JSONObject(raw)
        val hex = json.optString("android.theme.customization.system_palette")
            .ifBlank { json.optString("android.theme.customization.accent_color") }
        parseThemeHex(hex)
    }.getOrNull()

    private fun parseThemeHex(raw: String?): Int? {
        val hex = raw?.trim()?.removePrefix("#") ?: return null
        val value = when (hex.length) {
            6 -> hex.toLongOrNull(16)?.or(0xFF000000L)
            8 -> hex.toLongOrNull(16)
            else -> null
        } ?: return null
        return value.toInt()
    }

    // выбирает Dart (system_accent.dart)
    private fun collectAccentCandidates(): Map<String, Any?> = mapOf(
        "themeSetting" to readThemeSettingSeed(),
        "wallpaper" to readWallpaperAccentColor(),
        "systemResource" to readSystemAccentColor(),
    )

    // без этого новые обои подхватывались только перезапуском: цвета система извлекает уже после установки
    private var wallpaperColorsListener: WallpaperManager.OnColorsChangedListener? = null

    private fun startWallpaperColorsWatch() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O_MR1) return
        if (wallpaperColorsListener != null) return
        runCatching {
            val listener = WallpaperManager.OnColorsChangedListener { _, which ->
                if (which and WallpaperManager.FLAG_SYSTEM == 0) return@OnColorsChangedListener
                methodChannel?.invokeMethod("onSystemAccentChanged", collectAccentCandidates())
            }
            WallpaperManager.getInstance(this)
                .addOnColorsChangedListener(listener, Handler(Looper.getMainLooper()))
            wallpaperColorsListener = listener
        }
    }

    private fun stopWallpaperColorsWatch() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O_MR1) return
        val listener = wallpaperColorsListener ?: return
        wallpaperColorsListener = null
        runCatching {
            WallpaperManager.getInstance(this).removeOnColorsChangedListener(listener)
        }
    }

    private fun setupMethodChannel(flutterEngine: FlutterEngine) {
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .also { ch ->
                ch.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "setWindowBackgroundColor" -> {
                            // непрозрачный ARGB больше Int.MAX_VALUE и приезжает Long, argument<Int> падал на каждом вызове.
                            // toInt() берёт младшие 32 бита, ровно ARGB
                            val color = call.argument<Number>("color")?.toInt()
                            if (color == null) {
                                result.error("INVALID_ARGS", "Missing color", null)
                            } else {
                                rememberWindowBackground(color)
                                applyWindowBackground(color)
                                result.success(null)
                            }
                        }

                        "startVpn" -> {
                            val backend = call.argument<String>("vpnBackend") ?: "xray"
                            val socksPort       = call.argument<Int>("socksPort") ?: 2080
                            val serverName      = call.argument<String>("serverName")
                            val excludePackages = call.argument<List<*>>("excludePackages")
                                ?.filterIsInstance<String>() ?: emptyList()
                            val includePackages = call.argument<List<*>>("includePackages")
                                ?.filterIsInstance<String>() ?: emptyList()
                            // нет режима значит старый Dart, поднимаем VPN
                            val tunnelMode =
                                if (call.argument<String>("tunnelMode") ==
                                    KeqdisVpnService.TUNNEL_MODE_PROXY
                                ) {
                                    KeqdisVpnService.TUNNEL_MODE_PROXY
                                } else {
                                    KeqdisVpnService.TUNNEL_MODE_VPN
                                }
                            when (backend) {
                                KeqdisVpnService.VPN_BACKEND_XRAY -> {
                                    val xrayConfig = call.argument<String>("xrayConfig") ?: run {
                                        result.error("INVALID_ARGS", "Missing xrayConfig", null)
                                        return@setMethodCallHandler
                                    }
                                    val coreEngine = call.argument<String>("coreEngine")
                                        ?: KeqdisVpnService.CORE_ENGINE_CHAIN
                                    startVpnWithXray(
                                        xrayConfig,
                                        socksPort,
                                        excludePackages,
                                        includePackages,
                                        serverName,
                                        result,
                                        coreEngine,
                                        tunnelMode = tunnelMode,
                                    )
                                }
                                KeqdisVpnService.VPN_BACKEND_MIHOMO -> {
                                    val mihomoConfig = call.argument<String>("mihomoConfig") ?: run {
                                        result.error("INVALID_ARGS", "Missing mihomoConfig", null)
                                        return@setMethodCallHandler
                                    }
                                    startVpnWithXray(
                                        mihomoConfig,
                                        socksPort,
                                        excludePackages,
                                        includePackages,
                                        serverName,
                                        result,
                                        // движок у mihomo ни на что не влияет
                                        KeqdisVpnService.CORE_ENGINE_CHAIN,
                                        KeqdisVpnService.VPN_BACKEND_MIHOMO,
                                        // расширение yaml, внутри JSON: он подмножество YAML
                                        "mihomo_config.yaml",
                                        tunnelMode = tunnelMode,
                                    )
                                }
                                else -> result.error("UNSUPPORTED_BACKEND", "Unsupported VPN backend: $backend", null)
                            }
                        }
                        "stopVpn"              -> stopVpn(result)
                        "requestVpnPermission" -> requestVpnPermission(result)
                        "saveDocument" -> saveDocument(
                            call.argument<String>("fileName") ?: "",
                            call.argument<String>("mimeType") ?: "application/octet-stream",
                            call.argument<ByteArray>("bytes") ?: ByteArray(0),
                            result,
                        )
                        "getSocksCredentials"  -> {
                            // свежие креды уйдут в сервис через Intent при startVpn, так конфиг ядра и прокси приложения совпадают
                            pendingSocksUsername = randomToken(16)
                            pendingSocksPassword = randomToken(24)
                            NativeLog.d("KEQDIS", "getSocksCredentials: generated new credentials")
                            result.success(mapOf(
                                "username" to pendingSocksUsername!!,
                                "password" to pendingSocksPassword!!,
                            ))
                        }
                        "getActiveSocksCredentials" -> {
                            // креды живой сессии, без новых: сервис переживает пересоздание Flutter-движка, а Dart-синглтон нет,
                            // и свежий изолят получал 407 от своего же инбаунда
                            var user = vpnServiceBinder?.getSocksUsername() ?: ""
                            var pass = vpnServiceBinder?.getSocksPassword() ?: ""
                            if (user.isEmpty() || pass.isEmpty()) {
                                // binder ещё не привязан: те же креды сервис кладёт в QS-prefs
                                val prefs = getSharedPreferences(KeqdisVpnService.PREFS_QS, Context.MODE_PRIVATE)
                                user = prefs.getString(KeqdisVpnService.KEY_QS_LAST_SOCKS_USERNAME, "") ?: ""
                                pass = prefs.getString(KeqdisVpnService.KEY_QS_LAST_SOCKS_PASSWORD, "") ?: ""
                            }
                            result.success(mapOf("username" to user, "password" to pass))
                        }
                        "getMihomoApi" -> getMihomoApi(result)
                        "getDialFailures" -> result.success(NativeHelper.dialFailures())
                        "getPhysicalNetworks" -> result.success(
                            mapOf(
                                "count" to KeqdisVpnService.physicalNetworks,
                                "changes" to KeqdisVpnService.networkChanges,
                            ),
                        )
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
                        "openAppSettings" -> {
                            try {
                                startActivity(
                                    Intent(
                                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                        android.net.Uri.fromParts("package", packageName, null),
                                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                )
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("OPEN_SETTINGS_FAILED", e.message, null)
                            }
                        }
                        // снятая оптимизация батареи разрешает старт из фона. в VPN право даёт согласие на VPN, в режиме прокси его нет
                        "isIgnoringBatteryOptimizations" -> {
                            val pm = getSystemService(android.os.PowerManager::class.java)
                            result.success(pm?.isIgnoringBatteryOptimizations(packageName) ?: false)
                        }
                        "requestIgnoreBatteryOptimizations" -> {
                            try {
                                startActivity(
                                    Intent(
                                        Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                        android.net.Uri.fromParts("package", packageName, null),
                                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                )
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("BATTERY_OPT_REQUEST_FAILED", e.message, null)
                            }
                        }
                        "getOemAutostart" -> result.success(OemAutostart.kind(this))
                        "openOemAutostart" -> {
                            try {
                                OemAutostart.open(this)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("OPEN_AUTOSTART_FAILED", e.message, null)
                            }
                        }
                        "getProcessExits" -> result.success(ProcessExits.recent(this))
                        "getDeviceModel" -> result.success(android.os.Build.MODEL ?: "Android Device")
                        // по режиму интерфейса, а не по размеру: планшет в альбомной тоже широкий
                        "isTelevision" -> result.success(
                            (getSystemService(android.content.Context.UI_MODE_SERVICE) as? android.app.UiModeManager)
                                ?.currentModeType == android.content.res.Configuration.UI_MODE_TYPE_TELEVISION,
                        )
                        "getNativeInternals" -> {
                            // версии ядер панель читает из файлов, а nativeLibraryDir из Dart не виден
                            result.success(mapOf(
                                "nativeLibraryDir" to applicationInfo.nativeLibraryDir,
                                "xrayPid" to (vpnServiceBinder?.getXrayPid() ?: -1),
                                // binder не привязан при живом туннеле, берём из QS-prefs
                                "coreKind" to (vpnServiceBinder?.getCoreKind()
                                    ?: getSharedPreferences(KeqdisVpnService.PREFS_QS, Context.MODE_PRIVATE)
                                        .getString(KeqdisVpnService.KEY_QS_LAST_CORE_KIND, "")
                                    ?: ""),
                                "abis" to android.os.Build.SUPPORTED_ABIS.toList(),
                                "sdkInt" to android.os.Build.VERSION.SDK_INT,
                                "release" to (android.os.Build.VERSION.RELEASE ?: ""),
                                "manufacturer" to (android.os.Build.MANUFACTURER ?: ""),
                            ))
                        }
                        // отдаём все источники, выбирает Dart: отбраковке неперекрашенной палитры AOSP нужен счёт тонов, библиотека только там
                        "getSystemAccentColor" -> result.success(collectAccentCandidates())
                        "getLaunchAction" -> {
                            val action = intent?.getStringExtra(EXTRA_LAUNCH_ACTION)
                            result.success(action)
                        }
                        "clearLaunchAction" -> {
                            intent?.removeExtra(EXTRA_LAUNCH_ACTION)
                            result.success(null)
                        }
                        "getPendingDeepLink" -> {
                            // одноразово: после пересоздания активности ссылку импортировали бы дважды
                            result.success(pendingDeepLink)
                            pendingDeepLink = null
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
                        "getNativeLog" -> mainScope.launch {
                            result.success(withContext(Dispatchers.IO) { NativeLog.read() })
                        }
                        "resolveConnectionOwners" -> {
                            val items = call.argument<List<Map<String, Any?>>>("connections")
                                ?: emptyList()
                            resolveConnectionOwners(items, result)
                        }
                        "toggleVpn" -> {
                            try {
                                val intent = Intent(this@MainActivity, KeqdisVpnService::class.java)
                                intent.action = KeqdisVpnService.ACTION_TOGGLE
                                startService(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("TOGGLE_FAILED", e.message, null)
                            }
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
                            // пусто значит xray, как до выбора ядра
                            val core = call.argument<String>("core")
                                ?: EphemeralXrayPing.CORE_XRAY
                            val testUrl = call.argument<String>("testUrl")
                            val timeoutMs = call.argument<Int>("timeoutMs") ?: 15_000
                            val keepAlive = call.argument<Boolean>("keepAlive") ?: true
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
                                keepAlive,
                                core,
                                result,
                            )
                        }
                        "xrayUrlTestMulti" -> {
                            val config = call.argument<String>("config")
                            val core = call.argument<String>("core")
                                ?: EphemeralXrayPing.CORE_XRAY
                            val testUrl = call.argument<String>("testUrl")
                            val timeoutMs = call.argument<Int>("timeoutMs") ?: 15_000
                            val keepAlive = call.argument<Boolean>("keepAlive") ?: true
                            val concurrency = call.argument<Int>("concurrency") ?: 16
                            val rawProbes = call.argument<List<Map<String, Any?>>>("probes")
                            if (config.isNullOrBlank() || rawProbes.isNullOrEmpty()) {
                                result.error("INVALID_ARGS", "Missing config or probes", null)
                                return@setMethodCallHandler
                            }
                            xrayUrlTestMulti(
                                config,
                                rawProbes,
                                testUrl ?: "https://connectivitycheck.gstatic.com/generate_204",
                                timeoutMs,
                                keepAlive,
                                concurrency,
                                core,
                                call.argument<String>("batchId"),
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
                            val core = call.argument<String>("core")
                                ?: EphemeralXrayPing.CORE_XRAY
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
                                core,
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
                        // в фоне цикл не заводим, его поднимет onStart
                        if (lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) {
                            startTelemetryLoop()
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

    private fun startTelemetryLoop() {
        telemetryJob?.cancel()
        telemetryJob = mainScope.launch {
            while (isActive) {
                emitVpnSnapshot()
                val status = vpnServiceBinder?.getStatus()
                val delayMs = when (status) {
                    VpnRunStatus.RUNNING -> 2_000L
                    VpnRunStatus.STARTING -> 500L
                    else -> 1_500L
                }
                delay(delayMs)
            }
        }
    }

    override fun onStart() {
        super.onStart()
        if (eventSink != null && telemetryJob == null) startTelemetryLoop()
    }

    override fun onStop() {
        super.onStop()
        // свернули: подписка Dart не отменяется, и цикл молотил бы снапшоты в фоне. события статуса идут и без него
        telemetryJob?.cancel()
        telemetryJob = null
    }

    // одна карта на событие и опрос: опрос не клал ошибку, и строка под кнопкой мигала между причиной и общим текстом,
    // а список под шапкой прыгал. поле, забытое в одном пути, это мигание на экране
    private fun vpnSnapshot(
        statusOverride: String? = null,
        errorOverride: String? = null,
    ): Map<String, Any?> {
        val b = vpnServiceBinder
        if (b == null) {
            // статус и ошибка в prefs парой, иначе ошибка без причины
            return mapOf(
                "status" to (statusOverride ?: readQsVpnStatus()),
                "error" to (errorOverride ?: lastStatusError ?: readQsVpnError()),
                "uploadSpeed" to 0L,
                "downloadSpeed" to 0L,
                "totalUpload" to 0L,
                "totalDownload" to 0L,
                "durationSeconds" to 0L,
            )
        }
        return mapOf(
            "status" to (statusOverride ?: b.getStatus().name.lowercase()),
            "error" to (errorOverride ?: lastStatusError),
            "uploadSpeed" to b.getUploadSpeed(),
            "downloadSpeed" to b.getDownloadSpeed(),
            "totalUpload" to b.getTotalUpload(),
            "totalDownload" to b.getTotalDownload(),
            "durationSeconds" to b.getDurationSeconds(),
        )
    }

    private fun emitVpnSnapshot(
        statusOverride: String? = null,
        errorOverride: String? = null,
    ) {
        val sink = eventSink ?: return
        sink.success(vpnSnapshot(statusOverride, errorOverride))
    }

    private fun startVpnWithXray(
        xrayConfig: String,
        socksPort: Int,
        excludePackages: List<String>,
        includePackages: List<String>,
        serverName: String?,
        result: MethodChannel.Result,
        coreEngine: String = KeqdisVpnService.CORE_ENGINE_CHAIN,
        // имя файла по ядру: оставшийся чужой конфиг не подсунется новому ядру
        backend: String = KeqdisVpnService.VPN_BACKEND_XRAY,
        configFileName: String = "xray_config.json",
        tunnelMode: String = KeqdisVpnService.TUNNEL_MODE_VPN,
    ) {
        // разрешение VPN только когда поднимаем интерфейс: в режиме прокси establish() не зовётся
        if (tunnelMode != KeqdisVpnService.TUNNEL_MODE_PROXY &&
            VpnService.prepare(this) != null
        ) {
            result.error("PERMISSION_DENIED", "VPN permission not granted", null)
            return
        }

        // без getSocksCredentials ошибка, пустые строки сервису не шлём
        val username = pendingSocksUsername
        val password = pendingSocksPassword
        if (username.isNullOrEmpty() || password.isNullOrEmpty()) {
            NativeLog.e("KEQDIS", "startVpn: credentials missing — call getSocksCredentials first")
            result.error("NO_CREDENTIALS", "Call getSocksCredentials before startVpn", null)
            return
        }

        // запись на IO: на main она фризила
        mainScope.launch {
            val xrayPath = try {
                withContext(Dispatchers.IO) { writeConfig(xrayConfig, configFileName) }
            } catch (e: IOException) {
                // креды при ошибке IO не сбрасываем: Dart может повторить startVpn
                result.error("IO_ERROR", "Failed to write config: ${e.message}", null)
                return@launch
            }

            NativeLog.d("KEQDIS", "startVpn: sending credentials to service")

            // порт для WorkManager-изолята (StorageService.getSocksPort), ключи Flutter с префиксом flutter.
            getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .edit()
                .putInt("flutter.keqdis_socks_port", socksPort)
                .apply()

            startService(Intent(this@MainActivity, KeqdisVpnService::class.java).apply {
                action = KeqdisVpnService.ACTION_START
                putExtra(KeqdisVpnService.EXTRA_VPN_BACKEND, backend)
                putExtra(KeqdisVpnService.EXTRA_XRAY_CONFIG, xrayPath)
                putExtra(KeqdisVpnService.EXTRA_CORE_ENGINE, coreEngine)
                putExtra(KeqdisVpnService.EXTRA_TUNNEL_MODE, tunnelMode)
                putExtra("socks_port", socksPort)
                putStringArrayListExtra("exclude_packages", ArrayList(excludePackages))
                putStringArrayListExtra("include_packages", ArrayList(includePackages))
                if (!serverName.isNullOrBlank()) {
                    putExtra(KeqdisVpnService.EXTRA_SERVER_NAME, serverName)
                }
                // binder после cleanup() отдаёт пустые строки, поэтому локальные
                putExtra(KeqdisVpnService.EXTRA_SOCKS_USERNAME, username)
                putExtra(KeqdisVpnService.EXTRA_SOCKS_PASSWORD, password)
            })

            // сбрасываем только после отправки: следующий startVpn снова требует свежие креды
            pendingSocksUsername = null
            pendingSocksPassword = null

            result.success(null)
        }
    }

    private fun stopVpn(result: MethodChannel.Result) {
        // иначе getSocksCredentials без startVpn оставил бы устаревшие креды
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

        // диалог уже на экране: заменим pending result, и первый connect() потеряет ответ
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

    private fun saveDocument(
        fileName: String,
        mimeType: String,
        bytes: ByteArray,
        result: MethodChannel.Result,
    ) {
        if (pendingSaveResult != null) {
            result.error("SAVE_IN_PROGRESS", "Save dialog is already shown", null)
            return
        }
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeType
            putExtra(Intent.EXTRA_TITLE, fileName)
        }
        pendingSaveResult = result
        pendingSaveBytes = bytes
        try {
            saveDocumentLauncher.launch(intent)
        } catch (e: Exception) {
            // урезанные прошивки без ACTION_CREATE_DOCUMENT
            pendingSaveResult = null
            pendingSaveBytes = null
            result.error("SAVE_UNAVAILABLE", e.message ?: e.javaClass.simpleName, null)
        }
    }

    // file_picker пишет в w, а обрезать файл провайдер не обязан: от старого бэкапа оставался хвост.
    // провайдер без wt получит w, хвост после JSON отрежет импорт (KeqdisBackup.parse)
    private fun writeDocument(uri: android.net.Uri, bytes: ByteArray) {
        val stream = try {
            contentResolver.openOutputStream(uri, "wt")
        } catch (_: Exception) {
            null
        } ?: contentResolver.openOutputStream(uri, "w")
            ?: throw IOException("No output stream for $uri")
        stream.use { it.write(bytes) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // иначе getLaunchAction вернёт старый extra, когда тайл открывает уже живое приложение
        setIntent(intent)
        notifyLaunchActionIfNeeded()
        // движок пересоздаётся и канала нет: отложим до getPendingDeepLink
        deepLinkFrom(intent)?.let { url ->
            val ch = methodChannel
            if (ch == null) {
                pendingDeepLink = url
            } else {
                mainScope.launch { ch.invokeMethod("onDeepLink", mapOf("url" to url)) }
            }
        }
    }

    private fun notifyLaunchActionIfNeeded() {
        val action = intent?.getStringExtra(EXTRA_LAUNCH_ACTION) ?: return
        if (action !in LAUNCH_ACTIONS) return
        mainScope.launch {
            methodChannel?.invokeMethod("onLaunchAction", mapOf("action" to action))
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
        keepAlive: Boolean,
        core: String,
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
                        keepAlive = keepAlive,
                        core = core,
                    )
                }.getOrElse { e ->
                    emptyList<EphemeralXrayPing.BatchResult>()
                        .also { NativeLog.e("KEQDIS", "xrayUrlTestBatch failed: ${e.message}") }
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

    private fun xrayUrlTestMulti(
        config: String,
        rawProbes: List<Map<String, Any?>>,
        testUrl: String,
        timeoutMs: Int,
        keepAlive: Boolean,
        concurrency: Int,
        core: String,
        batchId: String?,
        result: MethodChannel.Result,
    ) {
        // пробы отвечают из пула, а синк на главном потоке
        val onEach: ((EphemeralXrayPing.BatchResult) -> Unit)? = batchId?.let { id ->
            { item ->
                mainScope.launch {
                    pingProgressSink?.success(
                        mapOf(
                            "batch" to id,
                            "id" to item.id,
                            "success" to item.result.success,
                            "latencyMs" to item.result.latencyMs,
                            "error" to item.result.error,
                            "httpStatus" to item.result.httpStatus,
                        ),
                    )
                }
            }
        }
        mainScope.launch {
            val payload = withContext(Dispatchers.IO) {
                runCatching {
                    val probes = rawProbes.mapNotNull { map ->
                        val id = map["id"] as? String ?: return@mapNotNull null
                        val port = (map["port"] as? Number)?.toInt() ?: return@mapNotNull null
                        if (port <= 0) return@mapNotNull null
                        EphemeralXrayPing.MultiProbe(id, port)
                    }
                    EphemeralXrayPing.urlTestMulti(
                        nativeLibraryDir = applicationInfo.nativeLibraryDir,
                        filesDir = filesDir,
                        assetDir = filesDir.absolutePath,
                        configJson = config,
                        probes = probes,
                        testUrl = testUrl,
                        timeoutMs = timeoutMs,
                        keepAlive = keepAlive,
                        concurrency = concurrency,
                        core = core,
                        onEach = onEach,
                    )
                }.getOrElse { e ->
                    emptyList<EphemeralXrayPing.BatchResult>()
                        .also { NativeLog.e("KEQDIS", "xrayUrlTestMulti failed: ${e.message}") }
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
        core: String,
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
                        core = core,
                    )
                }.getOrElse { e ->
                    emptyList<EphemeralXrayPing.SpeedBatchResult>()
                        .also { NativeLog.e("KEQDIS", "xraySpeedTestBatch failed: ${e.message}") }
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
            result.success(ms)
        }
    }

    private fun getInstalledApps(includeSystem: Boolean, result: MethodChannel.Result) {
        mainScope.launch {
            val apps = withContext(Dispatchers.IO) {
                val pm = packageManager
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
        if (vpnServiceBinder == null) {
            // BIND_AUTO_CREATE заодно создаёт сервис, а его onCreate() чинит фантомные connecting
            ensureVpnServiceBound()
        }
        result.success(vpnSnapshot())
    }

    private fun getXrayLogs(maxLines: Int, result: MethodChannel.Result) {
        mainScope.launch {
            val logs = withContext(Dispatchers.IO) {
                val capped = maxLines.coerceIn(50, 2000)

                val fromFile = runCatching {
                    val f = File(filesDir, KeqdisVpnService.CORE_LOG_FILE)
                    if (f.exists() && f.length() > 0L)
                        f.readLines().takeLast(capped).joinToString("\n")
                    else ""
                }.getOrDefault("")
                if (fromFile.isNotBlank()) return@withContext fromFile

                runCatching {
                    val process = ProcessBuilder("logcat", "-d", "-v", "time", "-s", "KEQDIS", "KEQDIS_XRAY")
                        .redirectErrorStream(true)
                        .start()
                    val all = BufferedReader(InputStreamReader(process.inputStream)).use { reader ->
                        reader.readLines()
                    }
                    process.waitFor()
                    all.takeLast(capped).joinToString("\n")
                }.getOrElse { e ->
                    "Unable to read core logs: ${e.message}"
                }
            }
            result.success(logs)
        }
    }

    // отдельно от списка приложений сплита: тот грузится целиком и редко, а тут запросы каждые пару секунд
    private val uidLabelCache = HashMap<Int, String>()

    // getConnectionOwnerUid работает только у активного VPN и только для живого соединения. пустая строка: не определилось
    private fun resolveConnectionOwners(
        items: List<Map<String, Any?>>,
        result: MethodChannel.Result,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || items.isEmpty()) {
            result.success(items.map { "" })
            return
        }
        mainScope.launch {
            val names = withContext(Dispatchers.IO) {
                val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                items.map { item ->
                    runCatching {
                        val udp = (item["protocol"] as? String)?.lowercase() == "udp"
                        val proto =
                            if (udp) OsConstants.IPPROTO_UDP else OsConstants.IPPROTO_TCP
                        val local = InetSocketAddress(
                            InetAddress.getByName(item["srcIp"] as String),
                            (item["srcPort"] as Number).toInt(),
                        )
                        val remote = InetSocketAddress(
                            InetAddress.getByName(item["dstIp"] as String),
                            (item["dstPort"] as Number).toInt(),
                        )
                        val uid = cm.getConnectionOwnerUid(proto, local, remote)
                        if (uid == android.os.Process.INVALID_UID) "" else labelForUid(uid)
                    }.getOrDefault("")
                }
            }
            result.success(names)
        }
    }

    private fun labelForUid(uid: Int): String {
        uidLabelCache[uid]?.let { return it }
        val label = runCatching {
            val pkgs = packageManager.getPackagesForUid(uid)
            if (pkgs.isNullOrEmpty()) {
                ""
            } else {
                val info = packageManager.getApplicationInfo(pkgs[0], 0)
                packageManager.getApplicationLabel(info).toString()
            }
        }.getOrDefault("")
        uidLabelCache[uid] = label
        return label
    }

    // только с Dispatchers.IO
    @Throws(IOException::class)
    private fun writeConfig(json: String, fileName: String): String {
        val file = File(filesDir, fileName)
        file.writeText(json, Charsets.UTF_8)
        return file.absolutePath
    }

    // источник один, конфиг на диске: Dart-синглтон не переживает пересоздание движка, а из плитки сессию поднимает сервис.
    // port=0 значит показывать нечего
    private fun getMihomoApi(result: MethodChannel.Result) {
        mainScope.launch {
            val payload = withContext(Dispatchers.IO) {
                runCatching {
                    val prefs = getSharedPreferences(KeqdisVpnService.PREFS_QS, Context.MODE_PRIVATE)
                    val coreKind = prefs.getString(KeqdisVpnService.KEY_QS_LAST_CORE_KIND, "")
                    if (coreKind != KeqdisVpnService.CORE_KIND_MIHOMO) return@runCatching null

                    val path = prefs.getString(KeqdisVpnService.KEY_QS_LAST_XRAY_CONFIG, "")
                    if (path.isNullOrEmpty()) return@runCatching null
                    val file = File(path)
                    if (!file.isFile) return@runCatching null

                    val json = org.json.JSONObject(file.readText(Charsets.UTF_8))
                    val controller = json.optString("external-controller")
                    val secret = json.optString("secret")
                    val port = controller.substringAfterLast(':', "").toIntOrNull() ?: 0
                    if (port <= 0 || secret.isEmpty()) return@runCatching null

                    mapOf("port" to port, "secret" to secret)
                }.getOrNull()
            }
            result.success(payload ?: mapOf("port" to 0, "secret" to ""))
        }
    }

    override fun onDestroy() {
        vpnServiceBinder?.setStatusListener(null)
        stopWallpaperColorsWatch()

        if (vpnStatusReceiverRegistered) {
            try {
                unregisterReceiver(vpnStatusReceiver)
            } catch (_: Exception) {}
            vpnStatusReceiverRegistered = false
        }

        if (serviceBound) {
            unbindService(serviceConnection)
            serviceBound = false
        }

        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        pingProgressChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel  = null
        pingProgressChannel = null
        pingProgressSink = null

        permissionRequestInFlight = false
        pendingPermissionResult?.error(
            "ACTIVITY_DESTROYED",
            "Activity was destroyed while waiting for VPN permission",
            null,
        )
        pendingPermissionResult = null

        pendingSocksUsername = null
        pendingSocksPassword = null
        telemetryJob?.cancel()
        telemetryJob = null

        mainScope.cancel()
        super.onDestroy()
    }
}
