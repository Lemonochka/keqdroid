package com.keqdroid.keqdroid

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.net.Uri
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.VpnService
import android.os.Binder
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.os.Build
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.amnezia.awg.GoBackend
import java.io.File
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.atomic.AtomicLong

enum class VpnRunStatus { STOPPED, STARTING, RUNNING, ERROR }
typealias StatusListener = (status: String, extra: String?) -> Unit

class KeqdisVpnService : VpnService() {

    companion object {
        const val ACTION_START         = "com.keqdis.vpn.START"
        const val ACTION_STOP          = "com.keqdis.vpn.STOP"
        const val ACTION_TOGGLE         = "com.keqdis.vpn.TOGGLE"
        const val EXTRA_XRAY_CONFIG    = "xray_config_path"
        const val EXTRA_SOCKS_USERNAME = "socks_username"
        const val EXTRA_SOCKS_PASSWORD = "socks_password"
        const val EXTRA_SERVER_NAME    = "server_name"
        const val EXTRA_VPN_BACKEND    = "vpn_backend"
        const val VPN_BACKEND_XRAY     = "xray"
        const val VPN_BACKEND_AWG      = "awg"
        // Ядро (только для backend xray): chain — libxray.so; keqrnel — единое
        // ядро libkeqrnel.so (sing-box host + встроенный xray) как drop-in.
        const val EXTRA_CORE_ENGINE    = "core_engine"
        const val CORE_ENGINE_CHAIN    = "chain"
        const val CORE_ENGINE_KEQRNEL  = "keqrnel"
        // Файл логов ядра в filesDir; читается getXrayLogs (надёжнее logcat на Android 13+).
        const val CORE_LOG_FILE        = "core_logs.txt"
        // AmneziaWG: ядро amneziawg-go само владеет TUN, конфиг приходит из .conf.
        const val EXTRA_AWG_UAPI        = "awg_uapi"
        const val EXTRA_AWG_ADDRESSES   = "awg_addresses"
        const val EXTRA_AWG_DNS         = "awg_dns"
        const val EXTRA_AWG_ALLOWED_IPS = "awg_allowed_ips"
        const val EXTRA_AWG_MTU         = "awg_mtu"
        const val NOTIFICATION_ID      = 1337
        const val CHANNEL_ID           = "keqdis_vpn"
        const val CHANNEL_ID_CONTROL   = "keqdis_vpn_control"
        const val TUN_ADDRESS          = "172.19.0.1"
        const val TUN_PREFIX           = 30
        const val TUN_MTU              = 1400

        // Broadcast action для кнопок уведомления
        const val BROADCAST_ACTION_CONNECT    = "com.keqdis.vpn.NOTIF_CONNECT"
        const val BROADCAST_ACTION_DISCONNECT = "com.keqdis.vpn.NOTIF_DISCONNECT"

        // Broadcast action for QS tile updates
        const val BROADCAST_VPN_STATUS_CHANGED = "com.keqdis.vpn.STATUS_CHANGED"

        // SharedPreferences keys used by Quick Settings tile.
        const val PREFS_QS = "keqdis_vpn_prefs"
        const val KEY_QS_STATUS = "qs_status"
        const val KEY_QS_ERROR = "qs_error"
        const val KEY_QS_LAST_XRAY_CONFIG = "qs_last_xray_config"
        const val KEY_QS_LAST_SOCKS_USERNAME = "qs_last_socks_username"
        const val KEY_QS_LAST_SOCKS_PASSWORD = "qs_last_socks_password"
        const val KEY_QS_LAST_SOCKS_PORT = "qs_last_socks_port"
        const val KEY_QS_LAST_BACKEND = "qs_last_backend"
        // Движок ядра последнего старта (chain/keqrnel) — плитка должна
        // переподключаться тем же движком, что и записанный configPath.
        const val KEY_QS_LAST_CORE_ENGINE = "qs_last_core_engine"
        const val KEY_QS_LAST_SERVER_NAME = "qs_last_server_name"
        const val KEY_QS_LAST_EXCLUDE_PACKAGES = "qs_last_exclude_packages"
        const val KEY_QS_LAST_INCLUDE_PACKAGES = "qs_last_include_packages"

        private const val UNDERLYING_UPDATE_MIN_INTERVAL_MS = 1_500L
    }

    // Credentials приходят через Intent от MainActivity — так они гарантированно совпадают с теми что были записаны в Xray конфиг
    @Volatile var socksUsername: String    = ""
    @Volatile var socksPassword: String    = ""

    @Volatile private var status              = VpnRunStatus.STOPPED
    @Volatile private var currentServerName: String? = null
    @Volatile private var lastXrayConfigPath: String? = null
    @Volatile private var lastSocksPort: Int = 2080
    @Volatile private var lastCoreEngine: String = CORE_ENGINE_KEQRNEL
    @Volatile private var lastExcludePackages: List<String> = emptyList()
    @Volatile private var lastIncludePackages: List<String> = emptyList()
    @Volatile private var xrayPid:            Int                   = -1
    @Volatile private var tun2socksPid:       Int                   = -1
    // AmneziaWG tunnel handle из amneziawg-go (>=0 когда активен awg-бэкенд).
    @Volatile private var awgHandle:          Int                   = -1
    @Volatile private var tunInterface:       ParcelFileDescriptor? = null
    @Volatile private var cleanupDone:       Boolean              = false
    @Volatile private var activeSocksPort:   Int                  = 2080

    // Сериализует start/stop/teardown: без этого быстрое перещёлкивание плитки в
    // шторке запускало новый старт поверх ещё идущего cleanup() предыдущего стопа —
    // они дрались за xrayPid/tun2socksPid/tunInterface и SOCKS-порт, старт падал в
    // ERROR и приложение приходилось перезапускать. Под мьютексом операции идут
    // строго по очереди, и стоп дожидается cleanup() ДО того, как стартует следующий.
    private val opMutex = Mutex()
    // startId последней команды (для stopSelf(startId): сервис не убьётся, если уже
    // прилетела более новая команда — например, старт в очереди за стопом).
    @Volatile private var latestStartId = 0

    private val serviceScope = CoroutineScope(
        Dispatchers.IO + SupervisorJob() + CoroutineExceptionHandler { _, e ->
            android.util.Log.e("KEQDIS", "Uncaught coroutine: ${e.message}", e)
        }
    )
    @Volatile private var statusListener: StatusListener? = null
    private var startTime     = 0L
    private val uploadTotal   = AtomicLong(0)
    private val downloadTotal = AtomicLong(0)
    private val uploadSpeed   = AtomicLong(0)
    private val downloadSpeed = AtomicLong(0)

    // BroadcastReceiver для обработки нажатий на кнопки уведомления
    private var notificationActionReceiver: BroadcastReceiver? = null

    // ── Binder ──────────────────────────────────────────────────────────────

    inner class LocalBinder : Binder() {
        fun getStatus()          = status
        fun getSocksUsername()   = socksUsername
        fun getSocksPassword()   = socksPassword
        fun setStatusListener(l: StatusListener?) { statusListener = l }
        fun getUploadSpeed()     = uploadSpeed.get()
        fun getDownloadSpeed()   = downloadSpeed.get()
        fun getTotalUpload()     = uploadTotal.get()
        fun getTotalDownload()   = downloadTotal.get()
        fun getDurationSeconds() = if (startTime > 0) (System.currentTimeMillis() - startTime) / 1000L else 0L
    }
    private val binder = LocalBinder()
    override fun onBind(intent: Intent?): IBinder = binder

    // ── Lifecycle ────────────────────────────────────────────────────────────

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        latestStartId = startId
        when (intent?.action) {
            ACTION_TOGGLE -> {
                // Переключение состояния VPN.
                // Если VPN уже запущен или находится в процессе запуска, прекращаем его.
                if (status == VpnRunStatus.RUNNING || status == VpnRunStatus.STARTING) {
                    serviceScope.launch { stopVpn(startId) }
                } else if (status == VpnRunStatus.STOPPED || status == VpnRunStatus.ERROR) {
                    // Запросим Flutter обработать подключение через launchPendingIntent
                    val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                    launchIntent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    launchIntent?.putExtra("action", "connect_from_notification")
                    startActivity(launchIntent)
                }
                return START_NOT_STICKY
            }
            ACTION_START -> {
                val backend = intent.getStringExtra(EXTRA_VPN_BACKEND) ?: VPN_BACKEND_XRAY
                val socksPort   = intent.getIntExtra("socks_port", 2080)
                val excludePkgs = intent.getStringArrayListExtra("exclude_packages") ?: arrayListOf()
                val includePkgs = intent.getStringArrayListExtra("include_packages") ?: arrayListOf()
                currentServerName = intent.getStringExtra(EXTRA_SERVER_NAME)
                lastSocksPort = socksPort
                lastExcludePackages = excludePkgs
                lastIncludePackages = includePkgs

                if (backend == VPN_BACKEND_AWG) {
                    val uapi = intent.getStringExtra(EXTRA_AWG_UAPI) ?: run {
                        android.util.Log.e("KEQDIS", "onStartCommand: missing EXTRA_AWG_UAPI")
                        return START_NOT_STICKY
                    }
                    val addresses = intent.getStringArrayListExtra(EXTRA_AWG_ADDRESSES) ?: arrayListOf()
                    val dns = intent.getStringArrayListExtra(EXTRA_AWG_DNS) ?: arrayListOf()
                    val allowedIps = intent.getStringArrayListExtra(EXTRA_AWG_ALLOWED_IPS) ?: arrayListOf()
                    val mtu = intent.getIntExtra(EXTRA_AWG_MTU, 0)

                    runCatching {
                        getSharedPreferences(PREFS_QS, Context.MODE_PRIVATE).edit()
                            .putString(KEY_QS_LAST_BACKEND, backend)
                            .putString(KEY_QS_LAST_SERVER_NAME, currentServerName)
                            .apply()
                    }

                    registerNotificationReceiver()
                    startForeground(
                        NOTIFICATION_ID,
                        buildControlNotification("Connecting…", isConnected = false, isTransitioning = true)
                    )
                    serviceScope.launch {
                        startVpnWithAwg(startId, uapi, addresses, dns, allowedIps, mtu, excludePkgs, includePkgs)
                    }
                    return START_NOT_STICKY
                }

                val configPath = intent.getStringExtra(EXTRA_XRAY_CONFIG) ?: run {
                    android.util.Log.e("KEQDIS", "onStartCommand: missing EXTRA_XRAY_CONFIG")
                    return START_NOT_STICKY
                }
                val user = intent.getStringExtra(EXTRA_SOCKS_USERNAME)
                val pass = intent.getStringExtra(EXTRA_SOCKS_PASSWORD)
                if (user.isNullOrEmpty() || pass.isNullOrEmpty()) {
                    android.util.Log.e("KEQDIS", "onStartCommand: SOCKS5 credentials missing in Intent — aborting start")
                    return START_NOT_STICKY
                }
                socksUsername = user
                socksPassword = pass

                // Движок ядра. Сохраняем его в QS-prefs вместе с configPath: файл
                // конфига привязан к движку (keqrnel пишет sing-box-формат, chain —
                // сырой xray). Плитка переподключается по этому же файлу, поэтому
                // обязана использовать ТОТ ЖЕ движок — иначе libxray не распарсит
                // sing-box-конфиг ("Listen on specific ip without port") и порт не поднимется.
                val coreEngine = intent.getStringExtra(EXTRA_CORE_ENGINE) ?: CORE_ENGINE_CHAIN
                lastCoreEngine = coreEngine

                android.util.Log.d("KEQDIS", "onStartCommand: backend=$backend engine=$coreEngine config=$configPath")
                lastXrayConfigPath = configPath

                runCatching {
                    getSharedPreferences(PREFS_QS, Context.MODE_PRIVATE)
                        .edit()
                        .putString(KEY_QS_LAST_BACKEND, backend)
                        .putString(KEY_QS_LAST_CORE_ENGINE, coreEngine)
                        .putString(KEY_QS_LAST_XRAY_CONFIG, configPath)
                        .putInt(KEY_QS_LAST_SOCKS_PORT, socksPort)
                        .putString(KEY_QS_LAST_SOCKS_USERNAME, socksUsername)
                        .putString(KEY_QS_LAST_SOCKS_PASSWORD, socksPassword)
                        .putString(KEY_QS_LAST_SERVER_NAME, currentServerName)
                        .putStringSet(KEY_QS_LAST_EXCLUDE_PACKAGES, excludePkgs.toSet())
                        .putStringSet(KEY_QS_LAST_INCLUDE_PACKAGES, includePkgs.toSet())
                        .apply()
                }

                registerNotificationReceiver()
                startForeground(
                    NOTIFICATION_ID,
                    buildControlNotification("Connecting…", isConnected = false, isTransitioning = true)
                )

                serviceScope.launch {
                    startVpnWithXray(
                        startId, configPath, socksPort, excludePkgs, includePkgs,
                        socksNoAuth = false, coreEngine = coreEngine,
                    )
                }
            }
            ACTION_STOP -> serviceScope.launch { stopVpn(startId) }
        }
        return START_NOT_STICKY
    }

    override fun onRevoke() { serviceScope.launch { stopVpn() }; super.onRevoke() }

    override fun onDestroy() {
        // [FIX-ANR] Не вызываем cleanup() если она уже запущена в stopVpn().
        // runBlocking на main thread может вызвать ANR если cleanup долгая.
        // Если stopVpn() был вызван, cleanupDone будет true через несколько мс.
        // Если сервис убит без stopVpn() (emergency kill), do quick cleanup без wait.
        if (!cleanupDone) {
            // Только быстрая очистка PID, без wait на процессы
            runCatching {
                if (tun2socksPid > 0) {
                    try { android.os.Process.killProcess(tun2socksPid) } catch (_: Exception) {}
                }
                if (xrayPid > 0) {
                    try { android.os.Process.killProcess(xrayPid) } catch (_: Exception) {}
                }
                try { tunInterface?.close() } catch (_: Exception) {}
            }
        }
        unregisterNotificationReceiver()
        serviceScope.cancel()
        super.onDestroy()
    }

    // ── Start / Stop ─────────────────────────────────────────────────────────

    private suspend fun startVpnWithXray(
        startId: Int,
        xrayConfigPath: String,
        socksPort: Int,
        excludePkgs: List<String>,
        includePkgs: List<String>,
        socksNoAuth: Boolean = false,
        coreEngine: String = CORE_ENGINE_CHAIN,
    ) = opMutex.withLock {
        // Под opMutex: предыдущий стоп уже завершил cleanup(), порт/процессы свободны.
        if (status == VpnRunStatus.RUNNING || status == VpnRunStatus.STARTING) return@withLock
        setStatus(VpnRunStatus.STARTING)
        try {
            if (!socksNoAuth && (socksUsername.isEmpty() || socksPassword.isEmpty())) {
                throw IllegalStateException("SOCKS5 credentials are empty — Intent was malformed")
            }

            // На Android всегда libxray.so (chain): keqrnel-обёртка ломала сплит-
            // роутинг (см. AndroidTunnelBackend), а libkeqrnel.so удалён из jniLibs.
            // coreEngine оставлен в сигнатурах для совместимости, но игнорируется —
            // даже старый сохранённый engine=keqrnel не должен искать удалённый бинарь.
            xrayPid = startXray(getBinaryPath("libxray.so"), xrayConfigPath)

            // 2. Ждём пока Xray поднимет SOCKS5 порт
            var waited = 0
            while (!isPortOpen("127.0.0.1", socksPort) && waited < 10000) {
                delay(300); waited += 300
            }
            if (!isPortOpen("127.0.0.1", socksPort))
                throw IllegalStateException("Xray SOCKS5 port $socksPort not ready")

            // 3. Создаём TUN-интерфейс
            val tun = buildTunInterface(excludePkgs, includePkgs)
            tunInterface = tun

            // 4. Запускаем tun2socks через нативный fork
            val tunRawFd = tun.fd
            activeSocksPort = socksPort
            startTun2Socks(tunRawFd, socksPort, socksNoAuth = socksNoAuth)

            startTime = System.currentTimeMillis()
            setStatus(VpnRunStatus.RUNNING)
            showControlNotification("Connected", isConnected = true, isTransitioning = false)
            startStatsLoop()

        } catch (e: Exception) {
            android.util.Log.e("KEQDIS", "startVpn failed: ${e.message}", e)
            setStatus(VpnRunStatus.ERROR, e.message)
            cleanup()
            showControlNotification(e.message ?: "Error", isConnected = false, isTransitioning = false)
            stopForeground(true)
            unregisterNotificationReceiver()
            // stopSelf(startId): не убьём сервис, если уже пришёл более новый старт.
            stopSelf(startId)
        }
    }

    private suspend fun stopVpn(startId: Int? = null) = opMutex.withLock {
        if (status == VpnRunStatus.STOPPED) {
            // Уже остановлен — но всё равно даём сервису шанс завершиться, если
            // это была отдельная stop-команда и более новой не прилетело.
            if (startId != null) stopSelf(startId) else stopSelf()
            return@withLock
        }

        // [FIX-TILE-DELAY] Статус → STOPPED сразу, чтобы плитка обновилась мгновенно.
        setStatus(VpnRunStatus.STOPPED)
        showControlNotification("Disconnected", isConnected = false, isTransitioning = false)
        withContext(Dispatchers.Main) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        }
        unregisterNotificationReceiver()

        // cleanup() ВНУТРИ мьютекса (await), чтобы следующий старт не начался, пока
        // не убиты старые xray/tun2socks и не закрыт TUN. Раньше cleanup уезжал в
        // отдельную корутину и гонялся с новым стартом — отсюда и зависания.
        try {
            cleanup()
        } catch (e: Exception) {
            android.util.Log.w("KEQDIS", "cleanup failed: ${e.message}")
        } finally {
            cleanupDone = true
            if (startId != null) stopSelf(startId) else stopSelf()
        }
    }

    private suspend fun cleanup() {
        val h = awgHandle
        if (h >= 0) {
            try { GoBackend.awgTurnOff(h) }
            catch (e: Exception) { android.util.Log.w("KEQDIS", "awgTurnOff failed: ${e.message}") }
            awgHandle = -1
        }

        val t2sPid = tun2socksPid
        if (t2sPid > 0) {
            try { android.os.Process.killProcess(t2sPid) } catch (_: Exception) {}
            tun2socksPid = -1
        }

        try { tunInterface?.close() } catch (_: Exception) {}
        tunInterface = null

        val xPid = xrayPid
        if (xPid > 0) {
            try { android.os.Process.killProcess(xPid) } catch (_: Exception) {}
            withContext(Dispatchers.IO) {
                try {
                    withTimeout(3000) { while (File("/proc/$xPid").exists()) delay(100) }
                } catch (_: Exception) {
                    try { android.os.Process.killProcess(xPid) } catch (_: Exception) {}
                }
            }
            xrayPid = -1
        }

        // [FIX-CREDENTIALS-GUARD] НЕ сбрасываем socksUsername/socksPassword здесь.
        // Credentials живут до следующего ACTION_START — это позволяет корректно
        // завершить уже запущенный tun2socks после cleanup, и даёт binder возможность
        // вернуть актуальные значения для диагностики.
        // Сброс происходит только при получении нового ACTION_START с новыми credentials.
        startTime = 0L
        uploadTotal.set(0); downloadTotal.set(0)
        uploadSpeed.set(0); downloadSpeed.set(0)
    }

    // ── TUN interface ────────────────────────────────────────────────────────

    private fun buildTunInterface(exc: List<String>, inc: List<String>): ParcelFileDescriptor {
        val b = Builder()
            .setMtu(TUN_MTU)
            .addAddress(TUN_ADDRESS, TUN_PREFIX)
            .addRoute("0.0.0.0", 0)
            .addDnsServer("8.8.8.8")
            .setSession("KEQDIS")
            .setBlocking(false)

        applyAppFilter(b, inc, exc)
        applyHuaweiUnderlying(b)

        val tun = b.establish()
        if (tun == null) {
            android.util.Log.e(
                "KEQDIS",
                "buildTun: establish() returned null — " +
                        "manufacturer=${Build.MANUFACTURER} model=${Build.MODEL} " +
                        "inc=${inc.size} exc=${exc.size}",
            )
            throw IllegalStateException(
                "TUN establish() returned null on ${Build.MANUFACTURER} ${Build.MODEL}. " +
                        "Split tunneling may not be supported on this device.",
            )
        }
        return tun
    }


    /// inc/exc split-tunnel app filter, общий для xray- и awg-туннелей.
    private fun applyAppFilter(b: Builder, inc: List<String>, exc: List<String>) {
        if (inc.isNotEmpty()) {
            // [FIX-HUAWEI] Считаем сколько пакетов реально добавилось.
            // runCatching молча глотал PackageManager.NameNotFoundException —
            // если все пакеты невалидны, establish() на Huawei/Honor возвращает null.
            var addedInc = 0
            inc.forEach { pkg ->
                try {
                    b.addAllowedApplication(pkg)
                    addedInc++
                } catch (e: Exception) {
                    android.util.Log.w("KEQDIS", "buildTun: addAllowedApplication skipped pkg=$pkg err=${e.message}")
                }
            }
            if (addedInc == 0) {
                android.util.Log.w("KEQDIS", "buildTun: include list produced 0 valid apps, falling back to full tunnel")
                runCatching { b.addDisallowedApplication(packageName) }
            }
        } else {
            runCatching { b.addDisallowedApplication(packageName) }
            exc.forEach { pkg ->
                try {
                    b.addDisallowedApplication(pkg)
                } catch (e: Exception) {
                    android.util.Log.w("KEQDIS", "buildTun: addDisallowedApplication skipped pkg=$pkg err=${e.message}")
                }
            }
        }
    }

    /// Huawei/Honor: setUnderlyingNetworks нужен для establish() со split tunneling.
    private fun applyHuaweiUnderlying(b: Builder) {
        val manufacturer = Build.MANUFACTURER.uppercase()
        if (manufacturer != "HUAWEI" && manufacturer != "HONOR") return
        try {
            val cm = getSystemService(android.net.ConnectivityManager::class.java)
            val activeNet = cm?.activeNetwork
            if (activeNet != null) {
                b.setUnderlyingNetworks(arrayOf(activeNet))
            } else {
                android.util.Log.w("KEQDIS", "buildTun: activeNetwork is null on $manufacturer")
            }
        } catch (e: Exception) {
            android.util.Log.w("KEQDIS", "buildTun: setUnderlyingNetworks failed on $manufacturer: ${e.message}")
        }
    }

    // ── AmneziaWG ─────────────────────────────────────────────────────────────

    private suspend fun startVpnWithAwg(
        startId: Int,
        uapi: String,
        addresses: List<String>,
        dns: List<String>,
        allowedIps: List<String>,
        mtu: Int,
        excludePkgs: List<String>,
        includePkgs: List<String>,
    ) = opMutex.withLock {
        if (status == VpnRunStatus.RUNNING || status == VpnRunStatus.STARTING) return@withLock
        setStatus(VpnRunStatus.STARTING)
        try {
            val tun = buildAwgTunInterface(addresses, dns, allowedIps, mtu, excludePkgs, includePkgs)
            tunInterface = tun

            val handle = GoBackend.awgTurnOn("awg0", tun.fd, uapi)
            if (handle < 0)
                throw IllegalStateException("amneziawg-go failed to start (awgTurnOn=$handle)")
            awgHandle = handle
            // fd теперь принадлежит ядру (device.Close() его закроет) — снимаем владение
            // у ParcelFileDescriptor, чтобы cleanup() не закрыл его повторно.
            runCatching { tun.detachFd() }

            // WG egress-сокет должен идти мимо туннеля, иначе петля маршрутизации.
            protectAwgSockets(handle)

            startTime = System.currentTimeMillis()
            setStatus(VpnRunStatus.RUNNING)
            showControlNotification("Connected", isConnected = true, isTransitioning = false)
            startStatsLoop()
        } catch (e: Exception) {
            android.util.Log.e("KEQDIS", "startVpnWithAwg failed: ${e.message}", e)
            setStatus(VpnRunStatus.ERROR, e.message)
            cleanup()
            showControlNotification(e.message ?: "Error", isConnected = false, isTransitioning = false)
            stopForeground(true)
            unregisterNotificationReceiver()
            stopSelf(startId)
        }
    }

    private fun protectAwgSockets(handle: Int) {
        val v4 = GoBackend.awgGetSocketV4(handle)
        if (v4 >= 0) runCatching { protect(v4) }
        val v6 = GoBackend.awgGetSocketV6(handle)
        if (v6 >= 0) runCatching { protect(v6) }
    }

    private fun buildAwgTunInterface(
        addresses: List<String>,
        dns: List<String>,
        allowedIps: List<String>,
        mtu: Int,
        exc: List<String>,
        inc: List<String>,
    ): ParcelFileDescriptor {
        val b = Builder()
            .setMtu(if (mtu > 0) mtu else 1280)
            .setSession("KEQDIS-AWG")
            .setBlocking(true)

        var addrCount = 0
        addresses.forEach { addr ->
            parseCidr(addr)?.let { (ip, prefix) ->
                try { b.addAddress(ip, prefix); addrCount++ }
                catch (e: Exception) { android.util.Log.w("KEQDIS", "awg addAddress skipped $addr: ${e.message}") }
            }
        }
        if (addrCount == 0)
            throw IllegalStateException("AmneziaWG config has no valid Interface Address")

        var routeCount = 0
        allowedIps.forEach { cidr ->
            parseCidr(cidr)?.let { (ip, prefix) ->
                try { b.addRoute(ip, prefix); routeCount++ }
                catch (e: Exception) { android.util.Log.w("KEQDIS", "awg addRoute skipped $cidr: ${e.message}") }
            }
        }
        if (routeCount == 0) runCatching { b.addRoute("0.0.0.0", 0) }

        if (dns.isEmpty()) {
            b.addDnsServer("1.1.1.1")
        } else {
            dns.forEach { d ->
                val ip = d.substringBefore('/').trim()
                runCatching { b.addDnsServer(ip) }
            }
        }

        applyAppFilter(b, inc, exc)
        applyHuaweiUnderlying(b)

        return b.establish() ?: throw IllegalStateException(
            "TUN establish() returned null on ${Build.MANUFACTURER} ${Build.MODEL}")
    }

    /// Разбирает `ip/prefix` (или голый ip → /32 для v4, /128 для v6).
    private fun parseCidr(raw: String): Pair<String, Int>? {
        val s = raw.trim()
        if (s.isEmpty()) return null
        val slash = s.indexOf('/')
        if (slash < 0) {
            return Pair(s, if (s.contains(':')) 128 else 32)
        }
        val ip = s.substring(0, slash).trim()
        val prefix = s.substring(slash + 1).trim().toIntOrNull() ?: return null
        return if (ip.isEmpty()) null else Pair(ip, prefix)
    }

    // ── tun2socks ────────────────────────────────────────────────────────────

    private fun startTun2Socks(tunRawFd: Int, socksPort: Int, socksNoAuth: Boolean = false) {
        val bin = File(applicationInfo.nativeLibraryDir, "libtun2socks.so")
        if (!bin.exists()) throw IllegalStateException("libtun2socks.so not found in ${applicationInfo.nativeLibraryDir}")

        val proxyUrl = if (socksNoAuth) {
            "socks5://127.0.0.1:$socksPort"
        } else {
            if (socksUsername.isEmpty() || socksPassword.isEmpty())
                throw IllegalStateException("SOCKS5 credentials missing in startTun2Socks")
            "socks5://$socksUsername:$socksPassword@127.0.0.1:$socksPort"
        }

        android.util.Log.i("KEQDIS", "Starting tun2socks: fd=$tunRawFd bin=${bin.absolutePath}")

        val pid = NativeHelper.startTun2Socks(tunRawFd, bin.absolutePath, proxyUrl)
        if (pid <= 0) throw IllegalStateException("fork() failed (pid=$pid)")

        tun2socksPid = pid
        android.util.Log.i("KEQDIS", "tun2socks started pid=$pid")

        serviceScope.launch(Dispatchers.IO) {
            try {
                while (java.io.File("/proc/$pid").exists()) delay(500)
                android.util.Log.w("KEQDIS", "[tun2socks] pid=$pid exited")
                // Реакцию на смерть процесса гоним через opMutex и перепроверяем под
                // ним: при переподключении старый pid уже не равен tun2socksPid, а
                // статус мог уйти в STOPPED — тогда это плановое завершение, не ошибка.
                opMutex.withLock {
                    if ((status == VpnRunStatus.RUNNING || status == VpnRunStatus.STARTING) &&
                        pid == tun2socksPid) {
                        android.util.Log.w("KEQDIS", "[tun2socks] triggering full cleanup after unexpected exit")
                        tun2socksPid = -1  // уже мёртв
                        setStatus(VpnRunStatus.ERROR, "tun2socks exited")
                        cleanup()
                        cleanupDone = true
                        withContext(Dispatchers.Main) { stopForeground(STOP_FOREGROUND_REMOVE) }
                        unregisterNotificationReceiver()
                        // Без stopSelf(): сервис остаётся в ERROR и переиспользуется
                        // следующим стартом из плитки, не убивая поставленную в очередь команду.
                    }
                }
            } catch (_: Exception) {}
        }
    }

    // ── Xray ─────────────────────────────────────────────────────────────────

    private fun startXray(binary: String, config: String): Int {
        // NativeHelper.startXray: fork+execv из nativeLibraryDir, дублирует вывод ядра
        // в logcat (KEQDIS_XRAY) и в файл CORE_LOG_FILE (его читает getXrayLogs).
        // Возвращает: pid > 0 — успех, -1 binary not found, -2 config not found, -4 crashed immediately
        XrayGeoAssets.ensure(this, filesDir)
        // Свежий лог ядра на каждую сессию (ping пишет в свой файл/никуда — не мешает).
        runCatching { File(filesDir, CORE_LOG_FILE).writeText("") }
        val pid = NativeHelper.startXray(binary, config, filesDir.absolutePath, CORE_LOG_FILE)
        when {
            pid == -1 -> throw IllegalStateException("Xray binary not found: $binary")
            pid == -2 -> throw IllegalStateException("Xray config not found: $config")
            pid == -4 -> throw IllegalStateException("Xray crashed on startup — see logcat KEQDIS/xray")
            pid <= 0  -> throw IllegalStateException("fork() for Xray failed (pid=$pid)")
            else -> {} // valid pid
        }
        android.util.Log.i("KEQDIS", "Xray started pid=$pid")

        // Запускаем мониторинг процесса Xray
        val monitorPid = pid
        serviceScope.launch(Dispatchers.IO) {
            try {
                while (File("/proc/$pid").exists()) delay(500)
                android.util.Log.w("KEQDIS", "[xray] pid=$pid exited")
                opMutex.withLock {
                    if ((status == VpnRunStatus.RUNNING || status == VpnRunStatus.STARTING) &&
                        monitorPid == xrayPid) {
                        // [FIX-STALE-TUN2SOCKS] Убиваем tun2socks немедленно при падении Xray.
                        // Без этого старый tun2socks продолжает жить и при следующем запуске
                        // подключается к новому Xray со старыми credentials → invalid password.
                        android.util.Log.w("KEQDIS", "[xray] triggering full cleanup after unexpected exit")
                        xrayPid = -1  // уже мёртв — не пытаемся убить повторно в cleanup()
                        setStatus(VpnRunStatus.ERROR, "Xray exited unexpectedly")
                        cleanup()
                        cleanupDone = true
                        withContext(Dispatchers.Main) { stopForeground(STOP_FOREGROUND_REMOVE) }
                        unregisterNotificationReceiver()
                        // Без stopSelf(): см. монитор tun2socks.
                    }
                }
            } catch (_: Exception) {}
        }
        return pid
    }

    // ── Stats loop ────────────────────────────────────────────────────────────

    private fun startStatsLoop() {
        serviceScope.launch {
            val uid = android.os.Process.myUid()
            var prevRx = android.net.TrafficStats.getUidRxBytes(uid).coerceAtLeast(0)
            var prevTx = android.net.TrafficStats.getUidTxBytes(uid).coerceAtLeast(0)

            while (status == VpnRunStatus.RUNNING || status == VpnRunStatus.STARTING) {
                delay(1000)
                val rx = android.net.TrafficStats.getUidRxBytes(uid).coerceAtLeast(0)
                val tx = android.net.TrafficStats.getUidTxBytes(uid).coerceAtLeast(0)

                val deltaRx = if (rx >= prevRx) rx - prevRx else 0L
                val deltaTx = if (tx >= prevTx) tx - prevTx else 0L

                downloadTotal.addAndGet(deltaRx)
                uploadTotal.addAndGet(deltaTx)
                downloadSpeed.set(deltaRx)
                uploadSpeed.set(deltaTx)

                prevRx = rx; prevTx = tx
            }
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun getBinaryPath(name: String): String {
        // Запускаем .so напрямую из nativeLibraryDir (/data/app/.../lib/arm64/).
        // Файлы там имеют SELinux-метку apk_data_file — execv разрешён.
        // codeCacheDir и filesDir — app_data_file — execv заблокирован SELinux на Android 10+.
        val bin = File(applicationInfo.nativeLibraryDir, name)
        if (!bin.exists()) throw IllegalStateException("$name not found in ${applicationInfo.nativeLibraryDir}")
        android.util.Log.i("KEQDIS", "Using binary: ${bin.absolutePath}")
        return bin.absolutePath
    }

    private suspend fun isPortOpen(host: String, port: Int) = withContext(Dispatchers.IO) {
        try { Socket().use { it.connect(InetSocketAddress(host, port), 300) }; true }
        catch (_: Exception) { false }
    }

    private fun setStatus(s: VpnRunStatus, e: String? = null) {
        status = s
        val statusStr = when (s) {
            VpnRunStatus.STOPPED  -> "disconnected"
            VpnRunStatus.STARTING -> "connecting"
            VpnRunStatus.RUNNING  -> "connected"
            VpnRunStatus.ERROR    -> "error"
        }

        // Log transitions to final states for QS tile debugging
        if (s == VpnRunStatus.STOPPED || s == VpnRunStatus.RUNNING || s == VpnRunStatus.ERROR) {
            android.util.Log.d("KEQDIS_QS", "setStatus: $s → statusStr=$statusStr")
        }

        // Persist status for Quick Settings tile (and other Android-only consumers).
        // We intentionally keep it separate from FlutterSharedPreferences.
        runCatching {
            getSharedPreferences(PREFS_QS, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_QS_STATUS, statusStr)
                .putString(KEY_QS_ERROR, e)
                .apply()
        }

        // Notify ContentProvider to update Quick Settings tile via ContentObserver.
        // This is more reliable than requestListeningState() which only works when QS is open.
        runCatching {
            contentResolver.notifyChange(VpnStatusProvider.STATUS_URI, null)
        }.onFailure { e ->
            android.util.Log.w("KEQDIS", "notifyChange failed: ${e.message}")
        }

        statusListener?.invoke(statusStr, e)

        // Broadcast status change for QS tile update
        runCatching {
            sendBroadcast(Intent().apply {
                action = BROADCAST_VPN_STATUS_CHANGED
                putExtra("status", statusStr)
                setPackage(packageName)
            })
        }.onFailure { ex ->
            android.util.Log.w("KEQDIS", "broadcastStatusChange failed: ${ex.message}")
        }
    }

    private fun buildNotification(text: String): Notification {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "VPN Status", NotificationManager.IMPORTANCE_LOW)
            )
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("KEQDIS VPN")
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentIntent(
                PendingIntent.getActivity(
                    this, 0,
                    Intent(this, MainActivity::class.java),
                    PendingIntent.FLAG_IMMUTABLE
                )
            )
            .setOngoing(true)
            .build()
    }

    private fun updateNotification(text: String) {
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
            .notify(NOTIFICATION_ID, buildNotification(text))
    }

    // ── Уведомление с кнопками управления ─────────────────────────────────────

    private fun buildControlNotification(
        text: String,
        isConnected: Boolean,
        isTransitioning: Boolean
    ): Notification {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID_CONTROL) == null) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID_CONTROL,
                    "VPN Control",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "VPN connection control and status"
                    setShowBadge(false)
                }
            )
        }

        // Intent для открытия приложения
        val contentIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val serverSuffix = currentServerName
            ?.takeIf { it.isNotBlank() }
            ?.let { " · $it" }
            ?: ""

        val builder = NotificationCompat.Builder(this, CHANNEL_ID_CONTROL)
            .setContentTitle(
                if (isConnected) "VPN Connected$serverSuffix" else "VPN Disconnected$serverSuffix"
            )
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentIntent(contentIntent)
            .setOngoing(isConnected)
            .setAutoCancel(!isConnected)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setShowWhen(false)
            .setOnlyAlertOnce(true)

        // Добавляем кнопки действий только если не в процессе переключения
        if (!isTransitioning) {
            if (isConnected) {
                // Кнопка "Отключить"
                val disconnectIntent = Intent(BROADCAST_ACTION_DISCONNECT).apply {
                    setPackage(packageName)
                }
                val disconnectPending = PendingIntent.getBroadcast(
                    this, 1,
                    disconnectIntent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
                builder.addAction(
                    android.R.drawable.ic_menu_close_clear_cancel,
                    "Disconnect",
                    disconnectPending
                )
            } else {
                // Кнопка "Подключить"
                val connectIntent = if (
                    !lastXrayConfigPath.isNullOrBlank() &&
                    socksUsername.isNotBlank() &&
                    socksPassword.isNotBlank()
                ) {
                    Intent(this, KeqdisVpnService::class.java).apply {
                        action = ACTION_START
                        putExtra(EXTRA_VPN_BACKEND, VPN_BACKEND_XRAY)
                        putExtra(EXTRA_CORE_ENGINE, lastCoreEngine)
                        putExtra(EXTRA_XRAY_CONFIG, lastXrayConfigPath)
                        putExtra("socks_port", lastSocksPort)
                        putStringArrayListExtra("exclude_packages", ArrayList(lastExcludePackages))
                        putStringArrayListExtra("include_packages", ArrayList(lastIncludePackages))
                        putExtra(EXTRA_SOCKS_USERNAME, socksUsername)
                        putExtra(EXTRA_SOCKS_PASSWORD, socksPassword)
                        currentServerName?.takeIf { it.isNotBlank() }?.let {
                            putExtra(EXTRA_SERVER_NAME, it)
                        }
                    }
                } else {
                    // Fallback для самого первого запуска после cold start.
                    Intent(this, KeqdisVpnService::class.java).apply {
                        action = ACTION_TOGGLE
                    }
                }
                val connectPending = PendingIntent.getService(
                    this, 2,
                    connectIntent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
                builder.addAction(
                    android.R.drawable.ic_menu_send,
                    "Connect",
                    connectPending
                )
            }
        }

        return builder.build()
    }

    // Обновляет foreground-уведомление сервиса. Использует startForeground() вместо
    // NotificationManager.notify() — это единственный корректный способ обновить
    // уведомление foreground-сервиса без race condition на Android 12+.
    private fun showControlNotification(
        text: String,
        isConnected: Boolean,
        isTransitioning: Boolean
    ) {
        startForeground(NOTIFICATION_ID, buildControlNotification(text, isConnected, isTransitioning))
    }

    private fun registerNotificationReceiver() {
        if (notificationActionReceiver != null) return

        notificationActionReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    BROADCAST_ACTION_CONNECT -> {
                        android.util.Log.d("KEQDIS", "[notification] Connect pressed")
                        // Открываем приложение для подключения
                        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                        launchIntent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        launchIntent?.putExtra("action", "connect_from_notification")
                        startActivity(launchIntent)
                    }
                    BROADCAST_ACTION_DISCONNECT -> {
                        android.util.Log.d("KEQDIS", "[notification] Disconnect pressed")
                        serviceScope.launch { stopVpn() }
                    }
                }
            }
        }

        val filter = IntentFilter().apply {
            addAction(BROADCAST_ACTION_CONNECT)
            addAction(BROADCAST_ACTION_DISCONNECT)
        }
        registerReceiver(notificationActionReceiver, filter, RECEIVER_NOT_EXPORTED)
    }

    private fun unregisterNotificationReceiver() {
        notificationActionReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {}
            notificationActionReceiver = null
        }
    }
}
