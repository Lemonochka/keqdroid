package com.keqdroid.keqdroid

import android.app.Activity
import android.app.WallpaperManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import androidx.activity.result.ActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
        const val EXTRA_LAUNCH_ACTION    = "action"
        // Значения EXTRA_LAUNCH_ACTION, которые обрабатывает Dart (servers_tab).
        // Держатся здесь, чтобы ярлыки из res/xml/shortcuts.xml и уведомление
        // не разъезжались со строками в коде.
        const val LAUNCH_ACTION_CONNECT    = "connect_from_notification"
        const val LAUNCH_ACTION_DISCONNECT = "disconnect_from_shortcut"
        private val LAUNCH_ACTIONS = setOf(
            LAUNCH_ACTION_CONNECT,
            LAUNCH_ACTION_DISCONNECT,
        )
        private const val ICON_SIZE_PX   = 96
        // Фон окна: держим отдельно от FlutterSharedPreferences — читаем его в
        // onCreate, до того как Flutter вообще поднялся.
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
    private var pendingSocksUsername: String? = null
    private var pendingSocksPassword: String? = null

    // Серверная ссылка (vless:// и т.п.), которой открыли приложение с холодного
    // старта: Dart забирает её через getPendingDeepLink, когда UI уже поднят.
    private var pendingDeepLink: String? = null
    private var eventSink: EventChannel.EventSink? = null
    private var telemetryJob: Job? = null
    private var lastStatusError: String? = null
    private var vpnServiceBinder: KeqdisVpnService.LocalBinder? = null
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null

    // Был ли bindService успешен: unbindService без привязки кидает
    // IllegalArgumentException.
    private var serviceBound = false
    private var vpnStatusReceiverRegistered = false

    // Мгновенные обновления статуса из KeqdisVpnService (плитка QS / уведомление),
    // когда binder ещё не переподключился после рестарта foreground-сервиса.
    private val vpnStatusReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != KeqdisVpnService.BROADCAST_VPN_STATUS_CHANGED) return
            val status = intent.getStringExtra("status")
            mainScope.launch {
                // Emit over EventChannel if Flutter is listening.
                emitVpnSnapshot(statusOverride = status)
                // Additionally notify Flutter via MethodChannel so the Dart side
                // can react even when EventChannel stream isn't active yet.
                try {
                    methodChannel?.invokeMethod("onVpnStatusSnapshot", mapOf("status" to status))
                } catch (_: Exception) {
                    // ignore
                }
            }
        }
    }

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
        // Фон окна — цвет ПРИЛОЖЕНИЯ, а не системной темы.
        //
        // NormalTheme в styles.xml наследуется от Theme.Light/Theme.Black, то
        // есть переключается СИСТЕМНОЙ тёмной темой, а тема приложения
        // выбирается своей настройкой. У человека со светлой системой и тёмным
        // приложением фон окна оставался белым, и там, где поверхность Flutter
        // не достаёт до края экрана (на HyperOS под панелью навигации остаётся
        // полоска в несколько пикселей), он и торчал белой полосой.
        //
        // Цвет присылает Dart на каждую смену темы; здесь берём запомненный,
        // чтобы окно было правильным ещё до первого кадра.
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
        registerVpnStatusReceiver()
        // После setupMethodChannel: слушатель шлёт цвета в Dart и без канала
        // ронял бы их в пустоту.
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
        val filter = IntentFilter(KeqdisVpnService.BROADCAST_VPN_STATUS_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(vpnStatusReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(vpnStatusReceiver, filter)
        }
        vpnStatusReceiverRegistered = true
    }

    /** Статус из QS-prefs, если binder ещё не готов (плитка/уведомление стартуют сервис сами). */
    private fun readQsVpnStatus(): String =
        getSharedPreferences(KeqdisVpnService.PREFS_QS, Context.MODE_PRIVATE)
            .getString(KeqdisVpnService.KEY_QS_STATUS, "disconnected")
            ?.lowercase()
            ?: "disconnected"

    /**
     * ARGB системного акцента (Material You `system_accent1_500`) на Android 12+.
     *
     * Плагин dynamic_color отдаёт схему только когда OEM выставил официальный
     * флаг поддержки Material You — Pixel это делает, а Realme/ColorOS, OneUI и
     * прочие часто НЕ выставляют, хотя ресурсы `system_accent1_*` у них заполнены
     * из обоев/темы. Тогда DynamicColorBuilder возвращает null и приложение
     * застывает на дефолтном сид-цвете. Читаем ресурс напрямую как запасной сид —
     * так «динамические цвета» работают и на не-Pixel устройствах. Возвращаем
     * null на API < 31 (ресурса нет) и при любой ошибке чтения.
     */
    private fun readSystemAccentColor(): Int? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return null
        return runCatching {
            @Suppress("DEPRECATION")
            resources.getColor(android.R.color.system_accent1_500, theme)
        }.getOrNull()
    }

    /**
     * Цвет системных обоев — источник акцента для прошивок, где Material You
     * выключен.
     *
     * Ресурсы `system_accent1_*` есть на любом API 31+, но перекрашивает их
     * системный ThemeOverlayController, и когда OEM его не включает (ColorOS и
     * подобные), там остаётся дефолтная палитра AOSP: значение приходит, оно
     * валидное, но это константа, которая не меняется ни от обоев, ни от темы.
     * Снаружи это выглядит как «приложение всегда одного цвета».
     *
     * Обои же читаются публичным API с API 27 и на всех прошивках, а Material
     * You и сам выводит палитру из них — поэтому как сид они ближе к тому, что
     * пользователь видит вокруг. Null при любой ошибке: вызывающий откатится на
     * `system_accent1_500`.
     */
    private fun readWallpaperAccentColor(): Int? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O_MR1) return null
        return runCatching {
            WallpaperManager.getInstance(this)
                .getWallpaperColors(WallpaperManager.FLAG_SYSTEM)
                ?.primaryColor
                ?.toArgb()
        }.getOrNull()
    }

    /**
     * Сид темы, выбранный в системных настройках.
     *
     * Самый прямой из источников: это не «похожий цвет», а ровно то значение,
     * из которого система развернула свои палитры. Лежит в
     * `Settings.Secure.theme_customization_overlay_packages` — JSON, куда
     * пишут все прошивки, реализующие механизм AOSP (ColorOS/realme UI, MIUI,
     * One UI). Читается обычным приложением без разрешений.
     *
     * Ключ строкой, а не константой: `THEME_CUSTOMIZATION_OVERLAY_PACKAGES`
     * помечен @hide и в SDK его нет.
     *
     * `accent_color` — форма до Android 13; читаем обе, потому что прошивки
     * обновляют этот механизм с задержкой в пару лет.
     */
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

    /**
     * Цвет из настройки темы: `RRGGBB` либо `AARRGGBB`, изредка с решёткой.
     * Всё остальное — не наш формат, и гадать не нужно: пусто честнее.
     */
    private fun parseThemeHex(raw: String?): Int? {
        val hex = raw?.trim()?.removePrefix("#") ?: return null
        val value = when (hex.length) {
            6 -> hex.toLongOrNull(16)?.or(0xFF000000L)
            8 -> hex.toLongOrNull(16)
            else -> null
        } ?: return null
        return value.toInt()
    }

    /** Всё, что удалось добыть; выбирает из этого Dart (см. system_accent.dart). */
    private fun collectAccentCandidates(): Map<String, Any?> = mapOf(
        "themeSetting" to readThemeSettingSeed(),
        "wallpaper" to readWallpaperAccentColor(),
        "systemResource" to readSystemAccentColor(),
    )

    /**
     * Обои сменили — пересобираем тему.
     *
     * Без этого «поставил обои, а приложение прежнего цвета» лечилось только
     * перезапуском: извлечение цвета система запускает при установке обоев, то
     * есть уже ПОСЛЕ того, как мы прочитали их на старте.
     */
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
                            val color = call.argument<Int>("color")
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
                            // Отсутствующий режим — это старый Dart или чужой
                            // вызов: поднимаем VPN, как было всегда.
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
                                        // coreEngine у mihomo смысла не имеет — он
                                        // про связку xray → sing-box.
                                        KeqdisVpnService.CORE_ENGINE_CHAIN,
                                        KeqdisVpnService.VPN_BACKEND_MIHOMO,
                                        // Ядро читает YAML; наш JSON — его подмножество.
                                        "mihomo_config.yaml",
                                        tunnelMode = tunnelMode,
                                    )
                                }
                                KeqdisVpnService.VPN_BACKEND_AWG -> {
                                    val uapi = call.argument<String>("awgUapi") ?: run {
                                        result.error("INVALID_ARGS", "Missing awgUapi", null)
                                        return@setMethodCallHandler
                                    }
                                    val addresses = call.argument<List<*>>("awgAddresses")
                                        ?.filterIsInstance<String>() ?: emptyList()
                                    val dns = call.argument<List<*>>("awgDns")
                                        ?.filterIsInstance<String>() ?: emptyList()
                                    val allowedIps = call.argument<List<*>>("awgAllowedIps")
                                        ?.filterIsInstance<String>() ?: emptyList()
                                    val mtu = call.argument<Int>("awgMtu") ?: 0
                                    startVpnWithAwg(
                                        uapi,
                                        addresses,
                                        dns,
                                        allowedIps,
                                        mtu,
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
                        "getActiveSocksCredentials" -> {
                            // Креды УЖЕ работающей сессии, БЕЗ генерации новых: VpnService
                            // переживает пересоздание Flutter-движка, а Dart-синглтон
                            // Socks5Credentials — нет. Без восстановления свежий изолят ходит
                            // в запароленный локальный http-инбаунд без Proxy-Authorization
                            // и получает 407 (проверка обновлений, рефреш подписок).
                            var user = vpnServiceBinder?.getSocksUsername() ?: ""
                            var pass = vpnServiceBinder?.getSocksPassword() ?: ""
                            if (user.isEmpty() || pass.isEmpty()) {
                                // Binder ещё не привязан (холодный старт) — сервис кладёт
                                // те же креды в QS-prefs при каждом старте xray-сессии.
                                val prefs = getSharedPreferences(KeqdisVpnService.PREFS_QS, Context.MODE_PRIVATE)
                                user = prefs.getString(KeqdisVpnService.KEY_QS_LAST_SOCKS_USERNAME, "") ?: ""
                                pass = prefs.getString(KeqdisVpnService.KEY_QS_LAST_SOCKS_PASSWORD, "") ?: ""
                            }
                            result.success(mapOf("username" to user, "password" to pass))
                        }
                        "getMihomoApi" -> getMihomoApi(result)
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
                            // Системный экран «О приложении» — там пользователь
                            // отзывает любые разрешения (уведомления, камера, и т.д.).
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
                        "getDeviceModel" -> result.success(android.os.Build.MODEL ?: "Android Device")
                        "getNativeInternals" -> {
                            // Панель «Внутренности» читает версии ядер прямо из
                            // файлов (Go build info), поэтому ей нужен каталог с
                            // libxray.so/libtun2socks.so — из Dart он не виден.
                            // PID берём здесь же: они живут в сервисе, а не в Dart.
                            result.success(mapOf(
                                "nativeLibraryDir" to applicationInfo.nativeLibraryDir,
                                "xrayPid" to (vpnServiceBinder?.getXrayPid() ?: -1),
                                "tun2socksPid" to (vpnServiceBinder?.getTun2SocksPid() ?: -1),
                                // Ядро ЖИВОЙ сессии. Binder не привязан (холодный
                                // старт при работающем туннеле) — берём из тех же
                                // QS-prefs, что и всё остальное о прошлом старте.
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
                        // Обои первыми: сюда попадаем только когда dynamic_color
                        // промолчал, то есть Material You у прошивки нет, и
                        // system_accent1_500 с большой вероятностью не перекрашен.
                        // Отдаём ВСЕ источники разом, а выбирает между ними Dart:
                        // отбраковка непеpекрашенной палитры AOSP требует счёта
                        // тонов, а библиотека для этого есть только там.
                        "getSystemAccentColor" -> result.success(collectAccentCandidates())
                        "getLaunchAction" -> {
                            // Возвращает action из Intent если приложение было запущено из уведомления
                            val action = intent?.getStringExtra(EXTRA_LAUNCH_ACTION)
                            result.success(action)
                        }
                        "clearLaunchAction" -> {
                            intent?.removeExtra(EXTRA_LAUNCH_ACTION)
                            result.success(null)
                        }
                        "getPendingDeepLink" -> {
                            // Одноразовая выдача: повторный запрос (resumed после
                            // пересоздания активности) не должен импортировать ссылку дважды.
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
                        "getTun2SocksLogs" -> {
                            val maxLines = call.argument<Int>("maxLines") ?: 300
                            getTun2SocksLogs(maxLines, result)
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
                        // Активность в фоне — цикл не заводим, его поднимет onStart.
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
        // Возобновляем периодическую телеметрию, остановленную в onStop.
        // Dart на resume дополнительно делает refreshStateStream()+syncFromNative().
        if (eventSink != null && telemetryJob == null) startTelemetryLoop()
    }

    override fun onStop() {
        super.onStop()
        // Свернули приложение: Dart-подписка на EventChannel не отменяется, и
        // периодический цикл молотил бы снапшоты каждые 1.5–2с в фоне впустую.
        // Событийные обновления статуса (statusListener, broadcast, QS-плитка)
        // не зависят от цикла и продолжают доходить — синк статуса не страдает.
        telemetryJob?.cancel()
        telemetryJob = null
    }

    private fun emitVpnSnapshot(
        statusOverride: String? = null,
        errorOverride: String? = null,
    ) {
        val sink = eventSink ?: return
        val b = vpnServiceBinder
        if (b == null) {
            val prefsStatus = statusOverride ?: readQsVpnStatus()
            sink.success(
                mapOf(
                    "status" to prefsStatus,
                    "error" to errorOverride,
                    "uploadSpeed" to 0L,
                    "downloadSpeed" to 0L,
                    "totalUpload" to 0L,
                    "totalDownload" to 0L,
                    "durationSeconds" to 0L,
                ),
            )
            return
        }
        val error = errorOverride ?: lastStatusError
        val rawStatus = statusOverride ?: b.getStatus().name.lowercase()
        sink.success(
            mapOf(
                "status" to rawStatus,
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
        coreEngine: String = KeqdisVpnService.CORE_ENGINE_CHAIN,
        // mihomo занимает то же место в схеме (локальный SOCKS под tun2socks),
        // поэтому путь запуска общий — различаются backend и имя файла конфига.
        // Имя разное намеренно: по нему видно, каким ядром писан файл, а
        // оставшийся от прошлой сессии чужой конфиг не подсунется новому ядру.
        backend: String = KeqdisVpnService.VPN_BACKEND_XRAY,
        configFileName: String = "xray_config.json",
        tunnelMode: String = KeqdisVpnService.TUNNEL_MODE_VPN,
    ) {
        // Разрешение на VPN спрашиваем ТОЛЬКО когда собираемся поднимать
        // интерфейс. В режиме прокси establish() не вызывается вовсе, а значит
        // и системный диалог не нужен: требовать его там — просить у человека
        // право, которым не воспользуешься.
        if (tunnelMode != KeqdisVpnService.TUNNEL_MODE_PROXY &&
            VpnService.prepare(this) != null
        ) {
            result.error("PERMISSION_DENIED", "VPN permission not granted", null)
            return
        }

        // Каждому startVpn обязан предшествовать getSocksCredentials: без pending
        // credentials возвращаем ошибку, а не шлём сервису пустые строки.
        val username = pendingSocksUsername
        val password = pendingSocksPassword
        if (username.isNullOrEmpty() || password.isNullOrEmpty()) {
            android.util.Log.e("KEQDIS", "startVpn: credentials missing — call getSocksCredentials first")
            result.error("NO_CREDENTIALS", "Call getSocksCredentials before startVpn", null)
            return
        }

        // Запись конфига — в Dispatchers.IO (на main она давала бы фризы),
        // result.success/error возвращаются в Main thread через mainScope.
        mainScope.launch {
            val xrayPath = try {
                withContext(Dispatchers.IO) { writeConfig(xrayConfig, configFileName) }
            } catch (e: IOException) {
                // Credentials при ошибке IO НЕ сбрасываем: Dart может повторить
                // startVpn без нового вызова getSocksCredentials.
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
                // Локальные переменные, проверенные выше; binder как fallback
                // не годится — после cleanup() он возвращает "".
                putExtra(KeqdisVpnService.EXTRA_SOCKS_USERNAME, username)
                putExtra(KeqdisVpnService.EXTRA_SOCKS_PASSWORD, password)
            })

            // Pending credentials сбрасываем только ПОСЛЕ успешной отправки
            // Intent: следующий startVpn снова требует getSocksCredentials,
            // так креды всегда свежие и совпадают с новым xray_config.json.
            pendingSocksUsername = null
            pendingSocksPassword = null

            result.success(null)
        }
    }

    private fun startVpnWithAwg(
        uapi: String,
        addresses: List<String>,
        dns: List<String>,
        allowedIps: List<String>,
        mtu: Int,
        excludePackages: List<String>,
        includePackages: List<String>,
        serverName: String?,
        result: MethodChannel.Result,
    ) {
        if (VpnService.prepare(this) != null) {
            result.error("PERMISSION_DENIED", "VPN permission not granted", null)
            return
        }

        // AmneziaWG не нуждается в SOCKS-credentials — ядро само владеет TUN.
        startService(Intent(this@MainActivity, KeqdisVpnService::class.java).apply {
            action = KeqdisVpnService.ACTION_START
            putExtra(KeqdisVpnService.EXTRA_VPN_BACKEND, KeqdisVpnService.VPN_BACKEND_AWG)
            putExtra(KeqdisVpnService.EXTRA_AWG_UAPI, uapi)
            putStringArrayListExtra(KeqdisVpnService.EXTRA_AWG_ADDRESSES, ArrayList(addresses))
            putStringArrayListExtra(KeqdisVpnService.EXTRA_AWG_DNS, ArrayList(dns))
            putStringArrayListExtra(KeqdisVpnService.EXTRA_AWG_ALLOWED_IPS, ArrayList(allowedIps))
            if (mtu > 0) putExtra(KeqdisVpnService.EXTRA_AWG_MTU, mtu)
            putStringArrayListExtra("exclude_packages", ArrayList(excludePackages))
            putStringArrayListExtra("include_packages", ArrayList(includePackages))
            if (!serverName.isNullOrBlank()) {
                putExtra(KeqdisVpnService.EXTRA_SERVER_NAME, serverName)
            }
        })

        result.success(null)
    }

    private fun stopVpn(result: MethodChannel.Result) {
        // Явная остановка тоже сбрасывает pending credentials: getSocksCredentials
        // без последующего startVpn оставил бы устаревшие креды.
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
        // Обновляем intent, чтобы getLaunchAction вернул актуальный extra, когда
        // приложение уже в фоне и тайл открывает его через openAppForConnect().
        setIntent(intent)
        notifyLaunchActionIfNeeded()
        // Тёплый старт по серверной ссылке: активность жива — пушим ссылку в Dart
        // сразу; без канала (движок пересоздаётся) откладываем до getPendingDeepLink.
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
        // connect_from_notification — уведомление и плитка QS;
        // disconnect_from_shortcut — ярлык долгого тапа по иконке приложения.
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
                // flags=0: GET_META_DATA для имени/иконки не нужен, их отдаёт
                // getApplicationLabel/Icon.
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
        if (b == null) {
            // Binder ещё/уже не привязан — пробуем восстановить привязку, чтобы
            // следующий опрос отдал живой статус, а не снапшот из prefs.
            // BIND_AUTO_CREATE заодно создаёт сервис, чей onCreate() чинит
            // фантомные connecting/connected, пережившие убийство процесса.
            ensureVpnServiceBound()
            result.success(mapOf("status" to readQsVpnStatus()))
            return
        }
        result.success(
            mapOf(
                "status"          to b.getStatus().name.lowercase(),
                "uploadSpeed"     to b.getUploadSpeed(),
                "downloadSpeed"   to b.getDownloadSpeed(),
                "totalUpload"     to b.getTotalUpload(),
                "totalDownload"   to b.getTotalDownload(),
                "durationSeconds" to b.getDurationSeconds(),
            )
        )
    }

    private fun getXrayLogs(maxLines: Int, result: MethodChannel.Result) {
        mainScope.launch {
            val logs = withContext(Dispatchers.IO) {
                val capped = maxLines.coerceIn(50, 2000)

                // Основной источник — файл логов ядра в filesDir. logcat на Android 13+
                // для untrusted_app недоступен (SELinux), поэтому файл надёжнее.
                val fromFile = runCatching {
                    val f = File(filesDir, KeqdisVpnService.CORE_LOG_FILE)
                    if (f.exists() && f.length() > 0L)
                        f.readLines().takeLast(capped).joinToString("\n")
                    else ""
                }.getOrDefault("")
                if (fromFile.isNotBlank()) return@withContext fromFile

                // Fallback: logcat (работает не на всех устройствах).
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

    /**
     * Лог tun2socks. Пишется только в дебаг-режиме (см. KeqdisVpnService), и
     * только в нём видно, какому приложению принадлежит соединение: строка
     * `[TCP] 10.0.0.2:41234 <-> 216.58.198.162:443`, где первый адрес —
     * сокет самого приложения на TUN. В логе xray на его месте уже наш
     * собственный сокет со стороны SOCKS.
     */
    private fun getTun2SocksLogs(maxLines: Int, result: MethodChannel.Result) {
        mainScope.launch {
            val logs = withContext(Dispatchers.IO) {
                val capped = maxLines.coerceIn(50, 4000)
                runCatching {
                    val f = File(filesDir, KeqdisVpnService.TUN2SOCKS_LOG_FILE)
                    if (f.exists() && f.length() > 0L)
                        f.readLines().takeLast(capped).joinToString("\n")
                    else ""
                }.getOrDefault("")
            }
            result.success(logs)
        }
    }

    // uid → отображаемое имя приложения. Держим отдельно от списка приложений
    // для сплит-туннеля: тот грузится целиком и редко, а здесь запросы идут
    // каждые пару секунд по одному-двум uid.
    private val uidLabelCache = HashMap<Int, String>()

    /**
     * Кто владеет соединением. Работает только у активного VPN-приложения —
     * ровно наш случай, — и только пока соединение живо: `getConnectionOwnerUid`
     * ищет его в таблице сокетов системы, для закрытых вернёт INVALID_UID.
     *
     * Отвечает списком имён, выровненным по входному: пустая строка — не
     * определилось (закрылось, Android младше 10, чужой uid без пакетов).
     */
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

    // Звать только из Dispatchers.IO. Пробрасывает IOException — ошибки
    // записи не глотаются молча.
    @Throws(IOException::class)
    private fun writeConfig(json: String, fileName: String): String {
        val file = File(filesDir, fileName)
        file.writeText(json, Charsets.UTF_8)
        return file.absolutePath
    }

    /**
     * Порт и `secret` RESTful API работающей mihomo-сессии — для экрана
     * «Соединения».
     *
     * Источник намеренно один: файл конфига, который прямо сейчас исполняет
     * ядро. Пара придумана в Dart, но синглтон там не переживает пересоздание
     * Flutter-движка, а из плитки сессию поднимает вообще сервис — Dart о ней
     * узнаёт уже постфактум. Дублируй мы её в prefs отдельным путём, был бы
     * второй источник правды и шанс разъехаться; здесь разъезжаться нечему.
     *
     * Пустой ответ (port=0) значит «нечего показывать»: сессии нет, она не на
     * mihomo, или конфиг писан до появления API.
     */
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

                    // Конфиг mihomo мы пишем обычным JSON (YAML 1.2 — его
                    // надмножество, ядру всё равно), поэтому и читается он
                    // штатным JSON-парсером.
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

        // unbindService без успешной привязки кидает IllegalArgumentException.
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

        pendingSocksUsername = null
        pendingSocksPassword = null
        telemetryJob?.cancel()
        telemetryJob = null

        mainScope.cancel()
        super.onDestroy()
    }
}
