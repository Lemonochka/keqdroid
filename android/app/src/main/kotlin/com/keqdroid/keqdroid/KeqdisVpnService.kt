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
    @Volatile private var lastExcludePackages: List<String> = emptyList()
    @Volatile private var lastIncludePackages: List<String> = emptyList()
    @Volatile private var xrayPid:            Int                   = -1
    @Volatile private var tun2socksPid:       Int                   = -1
    @Volatile private var tunInterface:       ParcelFileDescriptor? = null
    @Volatile private var cleanupDone:       Boolean              = false
    @Volatile private var activeSocksPort:   Int                  = 2080

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
        when (intent?.action) {
            ACTION_TOGGLE -> {
                // Переключение состояния VPN.
                // Если VPN уже запущен или находится в процессе запуска, прекращаем его.
                if (status == VpnRunStatus.RUNNING || status == VpnRunStatus.STARTING) {
                    serviceScope.launch { stopVpn() }
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

                val xrayPath = intent.getStringExtra(EXTRA_XRAY_CONFIG) ?: run {
                    android.util.Log.e("KEQDIS", "onStartCommand: missing EXTRA_XRAY_CONFIG")
                    return START_NOT_STICKY
                }
                val user = intent.getStringExtra(EXTRA_SOCKS_USERNAME)
                val pass = intent.getStringExtra(EXTRA_SOCKS_PASSWORD)
                currentServerName = intent.getStringExtra(EXTRA_SERVER_NAME)
                if (user.isNullOrEmpty() || pass.isNullOrEmpty()) {
                    android.util.Log.e("KEQDIS", "onStartCommand: SOCKS5 credentials missing in Intent — aborting start")
                    return START_NOT_STICKY
                }
                socksUsername = user
                socksPassword = pass
                android.util.Log.d("KEQDIS", "onStartCommand: credentials received backend=$backend")
                lastXrayConfigPath = xrayPath
                lastSocksPort = socksPort
                lastExcludePackages = excludePkgs
                lastIncludePackages = includePkgs

                // Persist "last selected server" snapshot for Quick Settings tile.
                runCatching {
                    getSharedPreferences(PREFS_QS, Context.MODE_PRIVATE)
                        .edit()
                        .putString(KEY_QS_LAST_BACKEND, backend)
                        .putString(KEY_QS_LAST_XRAY_CONFIG, xrayPath)
                        .putInt(KEY_QS_LAST_SOCKS_PORT, socksPort)
                        .putString(KEY_QS_LAST_SOCKS_USERNAME, socksUsername)
                        .putString(KEY_QS_LAST_SOCKS_PASSWORD, socksPassword)
                        .putString(KEY_QS_LAST_SERVER_NAME, currentServerName)
                        .putStringSet(KEY_QS_LAST_EXCLUDE_PACKAGES, excludePkgs.toSet())
                        .putStringSet(KEY_QS_LAST_INCLUDE_PACKAGES, includePkgs.toSet())
                        .apply()
                }

                // [FIX-ANR-TILE] startForeground() ОБЯЗАН быть вызван синхронно в onStartCommand.
                // Когда тайл использует startForegroundService(), Android даёт сервису 5 секунд
                // на вызов startForeground() — иначе ForegroundServiceDidNotStartInTimeException
                // и ANR. startVpnWithXray() работает в корутине и вызывает showControlNotification()
                // через NotificationManager.notify(), который НЕ является startForeground().
                // Поэтому при запуске через тайл startForeground() никогда не вызывался.
                registerNotificationReceiver()
                startForeground(
                    NOTIFICATION_ID,
                    buildControlNotification("Connecting…", isConnected = false, isTransitioning = true)
                )

                serviceScope.launch { startVpnWithXray(xrayPath, socksPort, excludePkgs, includePkgs) }
            }
            ACTION_STOP -> serviceScope.launch { stopVpn() }
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
        xrayConfigPath: String,
        socksPort: Int,
        excludePkgs: List<String>,
        includePkgs: List<String>
    ) {
        if (status == VpnRunStatus.RUNNING || status == VpnRunStatus.STARTING) return
        // registerNotificationReceiver() и startForeground("Connecting…") уже вызваны
        // синхронно в onStartCommand — до запуска этой корутины.
        setStatus(VpnRunStatus.STARTING)
        try {
            // [FIX-CREDENTIALS-GUARD] Дополнительная проверка перед запуском tun2socks.
            // socksUsername/Password должны быть установлены в onStartCommand выше.
            if (socksUsername.isEmpty() || socksPassword.isEmpty()) {
                throw IllegalStateException("SOCKS5 credentials are empty — Intent was malformed")
            }

            // 1. Запускаем Xray (приложение исключено из TUN — см. addDisallowedApplication).
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
            startTun2Socks(tunRawFd, socksPort)

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
            stopSelf()
        }
    }

    private suspend fun stopVpn() {
        if (status == VpnRunStatus.STOPPED) return

        // [FIX-TILE-DELAY] Меняем статус ДО cleanup, чтобы tile обновился сразу.
        // cleanup() может быть долгой (wait for process exit), поэтому запускаем её в фоне.
        setStatus(VpnRunStatus.STOPPED)
        showControlNotification("Disconnected", isConnected = false, isTransitioning = false)
        withContext(Dispatchers.Main) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        }
        unregisterNotificationReceiver()

        // Запускаем очистку в background, чтобы не блокировать обновление UI
        serviceScope.launch(Dispatchers.IO) {
            try {
                cleanup()
            } catch (e: Exception) {
                android.util.Log.w("KEQDIS", "cleanup failed: ${e.message}")
            } finally {
                cleanupDone = true
                // После очистки завершаем сервис
                stopSelf()
            }
        }
    }

    private suspend fun cleanup() {
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
                // Ни одного валидного пакета в allowlist — откатываемся на полный туннель,
                // иначе Huawei вернёт null из establish().
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

        // Huawei/Honor: setUnderlyingNetworks required for establish() with split tunneling.
        val manufacturer = Build.MANUFACTURER.uppercase()
        if (manufacturer == "HUAWEI" || manufacturer == "HONOR") {
            try {
                val cm = getSystemService(android.net.ConnectivityManager::class.java)
                val activeNet = cm?.activeNetwork
                if (activeNet != null) {
                    b.setUnderlyingNetworks(arrayOf(activeNet))
                    android.util.Log.d("KEQDIS", "buildTun: setUnderlyingNetworks applied for $manufacturer")
                } else {
                    android.util.Log.w("KEQDIS", "buildTun: activeNetwork is null on $manufacturer")
                }
            } catch (e: Exception) {
                android.util.Log.w("KEQDIS", "buildTun: setUnderlyingNetworks failed on $manufacturer: ${e.message}")
            }
        }

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


    // ── tun2socks ────────────────────────────────────────────────────────────

    private fun startTun2Socks(tunRawFd: Int, socksPort: Int) {
        // Запускаем libtun2socks.so напрямую из nativeLibraryDir —
        // нативный fork+execv наследует SELinux-контекст родителя (app_data_file)
        // который разрешает execv для файлов из /data/app/.../lib/
        val bin = File(applicationInfo.nativeLibraryDir, "libtun2socks.so")
        if (!bin.exists()) throw IllegalStateException("libtun2socks.so not found in ${applicationInfo.nativeLibraryDir}")

        // [FIX-CREDENTIALS-GUARD] Проверка уже выполнена в startVpn, но дублируем
        // для защиты от вызова startTun2Socks в обход стандартного флоу.
        if (socksUsername.isEmpty() || socksPassword.isEmpty())
            throw IllegalStateException("SOCKS5 credentials missing in startTun2Socks")

        val proxyUrl = "socks5://$socksUsername:$socksPassword@127.0.0.1:$socksPort"

        android.util.Log.i("KEQDIS", "Starting tun2socks: fd=$tunRawFd bin=${bin.absolutePath}")

        val pid = NativeHelper.startTun2Socks(tunRawFd, bin.absolutePath, proxyUrl)
        if (pid <= 0) throw IllegalStateException("fork() failed (pid=$pid)")

        tun2socksPid = pid
        android.util.Log.i("KEQDIS", "tun2socks started pid=$pid")

        serviceScope.launch(Dispatchers.IO) {
            try {
                while (java.io.File("/proc/$pid").exists()) delay(500)
                android.util.Log.w("KEQDIS", "[tun2socks] pid=$pid exited")
                // Игнорируем выход старого процесса при переподключении (новый pid уже в tun2socksPid).
                if ((status == VpnRunStatus.RUNNING || status == VpnRunStatus.STARTING) &&
                    pid == tun2socksPid) {
                    // [FIX-STALE-TUN2SOCKS] Полный cleanup — убиваем Xray тоже,
                    // чтобы не оставлять осиротевший процесс.
                    android.util.Log.w("KEQDIS", "[tun2socks] triggering full cleanup after unexpected exit")
                    tun2socksPid = -1  // уже мёртв
                    cleanup()
                    setStatus(VpnRunStatus.ERROR, "tun2socks exited")
                    stopForeground(true)
                    stopSelf()
                }
            } catch (_: Exception) {}
        }
    }

    // ── Xray ─────────────────────────────────────────────────────────────────

    private fun startXray(binary: String, config: String): Int {
        // NativeHelper.startXray: fork+execv из nativeLibraryDir, читает вывод в logcat (KEQDIS/xray)
        // Возвращает: pid > 0 — успех, -1 binary not found, -2 config not found, -4 crashed immediately
        val pid = NativeHelper.startXray(binary, config, filesDir.absolutePath)
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
                if ((status == VpnRunStatus.RUNNING || status == VpnRunStatus.STARTING) &&
                    monitorPid == xrayPid) {
                    // [FIX-STALE-TUN2SOCKS] Убиваем tun2socks немедленно при падении Xray.
                    // Без этого старый tun2socks продолжает жить и при следующем запуске
                    // подключается к новому Xray со старыми credentials → invalid password.
                    android.util.Log.w("KEQDIS", "[xray] triggering full cleanup after unexpected exit")
                    xrayPid = -1  // уже мёртв — не пытаемся убить повторно в cleanup()
                    cleanup()
                    setStatus(VpnRunStatus.ERROR, "Xray exited unexpectedly")
                    stopForeground(true)
                    stopSelf()
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
