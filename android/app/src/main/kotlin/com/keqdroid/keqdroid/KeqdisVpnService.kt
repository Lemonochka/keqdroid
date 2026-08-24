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
        const val VPN_BACKEND_MIHOMO   = "mihomo"
        const val VPN_BACKEND_AWG      = "awg"

        // Какое ядро исполняет конфиг. Уходит в NativeHelper.startCore: у xray и
        // mihomo разный argv и разный способ показать базы geo.
        const val CORE_KIND_XRAY       = "xray"
        const val CORE_KIND_MIHOMO     = "mihomo"
        // Ядро (только для backend xray): chain — libxray.so; keqrnel — единое
        // ядро libkeqrnel.so (sing-box host + встроенный xray) как drop-in.
        const val EXTRA_CORE_ENGINE    = "core_engine"
        const val CORE_ENGINE_CHAIN    = "chain"
        const val CORE_ENGINE_KEQRNEL  = "keqrnel"
        // Файл логов ядра в filesDir; читается getXrayLogs (надёжнее logcat на Android 13+).
        const val CORE_LOG_FILE        = "core_logs.txt"
        // Вердикт mihomo о собственном туннеле — единственный способ узнать,
        // взял ли он наш дескриптор (см. awaitMihomoTun). Строки из
        // listener/listener.go: ReCreateTun.
        const val MIHOMO_TUN_READY     = "[TUN] Tun adapter listening at:"
        const val MIHOMO_TUN_FAILED    = "Start TUN listening error:"
        // Лог tun2socks; пишется только в дебаг-режиме. Нужен экрану «Соединения»:
        // исходный сокет приложения виден больше нигде.
        const val TUN2SOCKS_LOG_FILE   = "tun2socks_logs.txt"
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
        const val KEY_QS_LAST_CORE_KIND   = "qs_last_core_kind"
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
    @Volatile private var lastCoreKind: String = CORE_KIND_XRAY
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
        // PID форкнутых ядер для панели «Внутренности»; -1 — процесс не запущен.
        fun getXrayPid()         = xrayPid
        fun getTun2SocksPid()    = tun2socksPid
        // Чем исполняется ТЕКУЩАЯ сессия. Панель «Внутренности» не вправе
        // выводить это из настройки: выбор ядра меняют на ходу, а работает всё
        // равно то, с которым подключились.
        fun getCoreKind()        = lastCoreKind
    }
    private val binder = LocalBinder()

    override fun onBind(intent: Intent?): IBinder? {
        // Системный биндинг VPN (action android.net.VpnService) обязан получить
        // внутренний binder из super.onBind(), иначе onRevoke() не доставляется:
        // когда VPN перехватывает другое приложение/система, сервис навсегда
        // остаётся в RUNNING, а приложение/тайл показывают «подключено» при
        // мёртвом туннеле. LocalBinder — только для нашей Activity.
        return if (intent?.action == VpnService.SERVICE_INTERFACE) super.onBind(intent) else binder
    }

    // ── Lifecycle ────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        // Самолечение фантомного статуса: процесс могли убить (force stop, OEM,
        // свайп из recents), не дав сервису записать финальный статус — в prefs
        // остаётся connecting/connected. Тайл от этого виснет (STATE_UNAVAILABLE
        // не нажимается), а приложение на холодном старте до привязки binder'а
        // показывает призрачное «подключается/подключено» без телеметрии.
        // Новый инстанс сервиса всегда стартует STOPPED — приводим prefs и
        // рассылку в соответствие. Реальному старту не мешает: ACTION_START
        // придёт в onStartCommand сразу после и выставит connecting.
        val stale = getSharedPreferences(PREFS_QS, Context.MODE_PRIVATE)
            .getString(KEY_QS_STATUS, "disconnected")
            ?.lowercase()
        if (stale != "disconnected" && stale != "error") {
            android.util.Log.w("KEQDIS", "onCreate: healing stale persisted status '$stale' → disconnected")
            setStatus(VpnRunStatus.STOPPED)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        latestStartId = startId
        when (intent?.action) {
            ACTION_TOGGLE -> {
                if (status == VpnRunStatus.RUNNING || status == VpnRunStatus.STARTING) {
                    serviceScope.launch { stopVpn(startId) }
                } else if (status == VpnRunStatus.STOPPED || status == VpnRunStatus.ERROR) {
                    // Сам сервис подключение не собирает (конфиг генерирует Dart) —
                    // открываем приложение, Flutter подхватит по launch action.
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
                        startGuarded(startId) {
                            startVpnWithAwg(startId, uapi, addresses, dns, allowedIps, mtu, excludePkgs, includePkgs)
                        }
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

                // Ядро выводим из backend'а и запоминаем ТАМ ЖЕ, где configPath:
                // файл конфига привязан к ядру (mihomo пишем в YAML, xray — в
                // json), и плитка обязана переподключаться тем же ядром. Иначе
                // повторим старый баг «плитка → ERROR»: libxray не разберёт
                // конфиг mihomo и SOCKS-порт не поднимется.
                val coreKind =
                    if (backend == VPN_BACKEND_MIHOMO) CORE_KIND_MIHOMO else CORE_KIND_XRAY
                lastCoreKind = coreKind

                android.util.Log.d(
                    "KEQDIS",
                    "onStartCommand: backend=$backend core=$coreKind engine=$coreEngine config=$configPath"
                )
                lastXrayConfigPath = configPath

                runCatching {
                    getSharedPreferences(PREFS_QS, Context.MODE_PRIVATE)
                        .edit()
                        .putString(KEY_QS_LAST_BACKEND, backend)
                        .putString(KEY_QS_LAST_CORE_ENGINE, coreEngine)
                        .putString(KEY_QS_LAST_CORE_KIND, coreKind)
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
                    startGuarded(startId) {
                        startVpnWithXray(
                            startId, configPath, socksPort, excludePkgs, includePkgs,
                            socksNoAuth = false, coreEngine = coreEngine, coreKind = coreKind,
                        )
                    }
                }
            }
            ACTION_STOP -> serviceScope.launch { stopVpn(startId) }
        }
        return START_NOT_STICKY
    }

    override fun onRevoke() { serviceScope.launch { stopVpn() }; super.onRevoke() }

    override fun onDestroy() {
        // Полный cleanup() здесь не зовём: runBlocking на main thread с долгой
        // очисткой — это ANR, а после штатного stopVpn() cleanupDone и так
        // станет true через несколько мс. Ветка ниже — только для убийства
        // сервиса без stopVpn() (force kill).
        if (!cleanupDone) {
            // быстрая очистка PID, без wait на процессы
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

    // Вотчдог старта: onStartCommand уже показал «Connecting…», а сам коннект может
    // зависнуть навсегда (застрявший стоп держит opMutex, establish() не вернулся,
    // форк ядра повис) — у пользователя оставался «вечный Connecting…» в уведомлении
    // без какого-либо исхода. По таймауту честно показываем ошибку и глушим сервис.
    private suspend fun startGuarded(startId: Int, block: suspend () -> Unit) {
        try {
            kotlinx.coroutines.withTimeout(45_000L) { block() }
        } catch (e: kotlinx.coroutines.TimeoutCancellationException) {
            android.util.Log.e("KEQDIS", "start watchdog fired: connect attempt hung")
            setStatus(VpnRunStatus.ERROR, "Connection attempt timed out")
            // best-effort вне мьютекса: возможно, завис именно его владелец
            runCatching { cleanup() }
            showControlNotification(
                "Connection timed out",
                isConnected = false,
                isTransitioning = false,
            )
            stopForeground(true)
            unregisterNotificationReceiver()
            stopSelf(startId)
        }
    }

    private suspend fun startVpnWithXray(
        startId: Int,
        xrayConfigPath: String,
        socksPort: Int,
        excludePkgs: List<String>,
        includePkgs: List<String>,
        socksNoAuth: Boolean = false,
        coreEngine: String = CORE_ENGINE_CHAIN,
        coreKind: String = CORE_KIND_XRAY,
    ) = opMutex.withLock {
        // Под opMutex: предыдущий стоп уже завершил cleanup(), порт/процессы свободны.
        if (status == VpnRunStatus.RUNNING || status == VpnRunStatus.STARTING) {
            // Дубль-старт: не оставляем уведомление застрявшим на «Connecting…» —
            // если сессия уже жива, вернём ему актуальное «Connected».
            if (status == VpnRunStatus.RUNNING) {
                showControlNotification("Connected", isConnected = true, isTransitioning = false)
            }
            return@withLock
        }
        setStatus(VpnRunStatus.STARTING)
        try {
            if (!socksNoAuth && (socksUsername.isEmpty() || socksPassword.isEmpty())) {
                throw IllegalStateException("SOCKS5 credentials are empty — Intent was malformed")
            }

            // На Android всегда libxray.so (chain): keqrnel-обёртка ломает сплит-
            // роутинг (см. AndroidTunnelBackend), и libkeqrnel.so в jniLibs нет.
            // coreEngine оставлен в сигнатурах для совместимости, но игнорируется —
            // даже старый сохранённый engine=keqrnel не должен искать отсутствующий бинарь.
            //
            // mihomo занимает в схеме ровно то же место: поднимает локальный SOCKS5,
            // TUN как и раньше держат VpnService + tun2socks. Отличаются только
            // бинарь и argv (см. NativeHelper.startCore).
            // Ядра от прошлой жизни приложения — до старта нового.
            //
            // Без этого новое ядро не займёт SOCKS-порт (его держит старое), а
            // tun2socks подключится к старому ядру с чужими credentials: в логе
            // `rejected username/password`, на экране — «подключено» и мёртвая
            // сеть. Проверка isPortOpen ниже такое не ловит: порт-то открыт.
            if (NativeHelper.killOrphans() > 0) {
                // SIGKILL асинхронен: слушающий сокет освобождается не в тот же
                // миг, а новое ядро полезет за портом сразу.
                var waitedFree = 0
                while (isPortOpen("127.0.0.1", socksPort) && waitedFree < 2000) {
                    delay(100); waitedFree += 100
                }
            }

            val isMihomo = coreKind == CORE_KIND_MIHOMO

            // Порядок зависит от того, кто владеет туннелем.
            //
            //  * xray: ядро о TUN не знает, пакеты ему приносит tun2socks.
            //    Сначала ядро (и его SOCKS-порт), потом интерфейс, потом
            //    tun2socks — так упавшее ядро не оставляет за собой поднятый
            //    интерфейс.
            //  * mihomo: туннель держит оно само через `tun.file-descriptor`,
            //    поэтому интерфейс обязан существовать РАНЬШЕ ядра — номер
            //    дескриптора дописывается в конфиг перед запуском. Взамен
            //    исчезает tun2socks, а с ним лишняя пересылка каждого пакета
            //    через локальный SOCKS; появляются перехват DNS (`dns-hijack`)
            //    и настоящий UDP.
            if (isMihomo) {
                val tun = buildTunInterface(excludePkgs, includePkgs)
                tunInterface = tun
                val tunRawFd = tun.fd
                injectTunFd(xrayConfigPath, tunRawFd)
                activeSocksPort = socksPort
                xrayPid = startXray(
                    getBinaryPath("libmihomo.so"),
                    xrayConfigPath,
                    coreKind,
                    tunFd = tunRawFd,
                )
            } else {
                xrayPid = startXray(
                    getBinaryPath("libxray.so"),
                    xrayConfigPath,
                    coreKind,
                )
            }

            // ждём пока ядро поднимет SOCKS5 порт
            //
            // Признак годится и для mihomo с собственным туннелем: локальные
            // инбаунды у него в том же конфиге и поднимаются тем же стартом, а
            // отдельного «tun готов» ядро наружу не сообщает.
            var waited = 0
            while (!isPortOpen("127.0.0.1", socksPort) && waited < 10000) {
                delay(300); waited += 300
            }
            if (!isPortOpen("127.0.0.1", socksPort))
                throw IllegalStateException(
                    "${if (isMihomo) "mihomo" else "Xray"} SOCKS5 port $socksPort not ready${coreLogTail()}"
                )

            // Открытый SOCKS-порт у mihomo НЕ означает, что туннель взлетел:
            // инбаунды поднимаются раньше tun-листенера (`updateListeners` идёт
            // до `updateTun`), а его падение ядро переживает — пишет ошибку,
            // гасит `tun.enable` и работает дальше. Снаружи всё выглядит
            // здоровым: порт слушается, прокси набирается, статус «подключено»,
            // и только пакеты из tun не читает никто.
            if (isMihomo) awaitMihomoTun()

            if (!isMihomo) {
                // создаём TUN-интерфейс
                val tun = buildTunInterface(excludePkgs, includePkgs)
                tunInterface = tun

                // запускаем tun2socks через нативный fork
                val tunRawFd = tun.fd
                activeSocksPort = socksPort
                startTun2Socks(tunRawFd, socksPort, socksNoAuth = socksNoAuth)
            }

            startTime = System.currentTimeMillis()
            setStatus(VpnRunStatus.RUNNING)
            showControlNotification("Connected", isConnected = true, isTransitioning = false)
            startStatsLoop()

        } catch (e: Exception) {
            if (e is kotlinx.coroutines.CancellationException) {
                // отмена вотчдогом (или скоупом): чистим под мьютексом и пробрасываем —
                // уведомление об исходе выставит startGuarded
                runCatching { cleanup() }
                throw e
            }
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
            // Уже остановлен — но prefs могли пережить убийство процесса со
            // старым connected/connecting: пересинхронизируем статус (prefs +
            // broadcast + ContentObserver), чтобы тайл и приложение отлипли.
            setStatus(VpnRunStatus.STOPPED)
            // Даём сервису шанс завершиться, если это была отдельная
            // stop-команда и более новой не прилетело.
            if (startId != null) stopSelf(startId) else stopSelf()
            return@withLock
        }

        // Статус → STOPPED до cleanup, чтобы плитка обновилась мгновенно,
        // а не после многосекундного убийства процессов.
        setStatus(VpnRunStatus.STOPPED)
        showControlNotification("Disconnected", isConnected = false, isTransitioning = false)
        withContext(Dispatchers.Main) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        }
        unregisterNotificationReceiver()

        // cleanup() ВНУТРИ мьютекса (await), чтобы следующий старт не начался,
        // пока не убиты старые xray/tun2socks и не закрыт TUN: cleanup в
        // отдельной корутине гонялся бы с новым стартом и подвешивал его.
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

        // socksUsername/socksPassword здесь НЕ сбрасываем: они живут до
        // следующего ACTION_START (с его новыми credentials) — так корректно
        // дозавершается уже запущенный tun2socks, а binder может вернуть
        // актуальные значения для диагностики.
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
    ///
    /// [excludeSelf]: в xray-режиме собственный пакет ОБЯЗАН идти мимо туннеля —
    /// исходящие сокеты in-process xray не protect()-ятся и зациклились бы.
    /// В awg-режиме наоборот: WG-сокет защищён protect(), а трафик самого
    /// приложения (чек/скачивание обновлений с GitHub, апдейт подписок) должен
    /// ехать через туннель — напрямую его режут (RKN), и локального прокси,
    /// как у xray, в awg-режиме нет.
    private fun applyAppFilter(
        b: Builder,
        inc: List<String>,
        exc: List<String>,
        excludeSelf: Boolean = true,
    ) {
        if (inc.isNotEmpty()) {
            // Считаем, сколько пакетов реально добавилось: NameNotFoundException
            // нельзя просто глотать — если невалидны ВСЕ пакеты, establish()
            // на Huawei/Honor возвращает null.
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
                // Полный туннель: в awg-режиме (excludeSelf=false) он уже включает
                // и наш пакет, отдельного addAllowed не нужно.
                android.util.Log.w("KEQDIS", "buildTun: include list produced 0 valid apps, falling back to full tunnel")
                if (excludeSelf) runCatching { b.addDisallowedApplication(packageName) }
            } else if (!excludeSelf) {
                runCatching { b.addAllowedApplication(packageName) }
            }
        } else {
            if (excludeSelf) runCatching { b.addDisallowedApplication(packageName) }
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
        if (status == VpnRunStatus.RUNNING || status == VpnRunStatus.STARTING) {
            if (status == VpnRunStatus.RUNNING) {
                showControlNotification("Connected", isConnected = true, isTransitioning = false)
            }
            return@withLock
        }
        setStatus(VpnRunStatus.STARTING)
        try {
            val tun = buildAwgTunInterface(addresses, dns, allowedIps, mtu, excludePkgs, includePkgs)
            tunInterface = tun

            // awgTurnOn забирает владение fd ЦЕЛИКОМ: и на успехе (device.Close()
            // закроет), и на ЛЮБОЙ ошибке (все error-пути api-android.go делают
            // unix.Close). Поэтому detachFd() — строго ДО вызова: если detach'ить
            // только после успеха, провальный awgTurnOn (например, доменный
            // Endpoint, который UAPI не парсит) оставляет fd во владении
            // ParcelFileDescriptor, cleanup() закрывает его вторым разом, и fdsan
            // (Android 11+) валит процесс SIGABRT'ом — приложение «мгновенно
            // закрывается» вместо показа ошибки.
            val tunFd = tun.detachFd()
            val handle = GoBackend.awgTurnOn("awg0", tunFd, uapi)
            if (handle < 0)
                throw IllegalStateException("amneziawg-go failed to start (awgTurnOn=$handle)")
            awgHandle = handle

            // WG egress-сокет должен идти мимо туннеля, иначе петля маршрутизации.
            protectAwgSockets(handle)

            startTime = System.currentTimeMillis()
            setStatus(VpnRunStatus.RUNNING)
            showControlNotification("Connected", isConnected = true, isTransitioning = false)
            startStatsLoop()
        } catch (e: Exception) {
            if (e is kotlinx.coroutines.CancellationException) {
                runCatching { cleanup() }
                throw e
            }
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

        // excludeSelf=false: WG-сокет и так protect()-ится, а собственному
        // трафику приложения (GitHub-обновления, подписки) нужен туннель.
        applyAppFilter(b, inc, exc, excludeSelf = false)
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

        // В дебаг-режиме поднимаем уровень до info и пишем вывод в файл: только
        // там видно, какому приложению принадлежит соединение (строка
        // `[TCP] <сокет приложения> <-> <назначение>`). В обычном режиме всё как
        // раньше — warning и без файла.
        val debug = readDebugMode()
        val logPath = if (debug) File(filesDir, TUN2SOCKS_LOG_FILE).absolutePath else ""
        val logLevel = if (debug) "info" else "warning"

        android.util.Log.i("KEQDIS", "Starting tun2socks: fd=$tunRawFd bin=${bin.absolutePath} log=$logLevel")

        val pid = NativeHelper.startTun2Socks(
            tunRawFd,
            bin.absolutePath,
            proxyUrl,
            logLevel,
            logPath,
            TUN_MTU,
        )
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

    /**
     * Последние строки core_logs.txt для текста ошибки. Само по себе «port not
     * ready» ничего не говорит: ядро чаще всего уже вышло с внятной жалобой на
     * конфиг (например, на geosite:-код, которого нет в базе), а logcat на
     * Android 13+ untrusted_app недоступен. Ограничиваем длину — строка едет в
     * уведомление и в блок ошибки на экране подключения.
     */
    private fun coreLogTail(maxLines: Int = 6, maxChars: Int = 600): String =
        runCatching {
            val file = File(filesDir, CORE_LOG_FILE)
            if (!file.exists() || file.length() == 0L) return@runCatching ""
            val tail = file.readLines()
                .filter { it.isNotBlank() }
                .takeLast(maxLines)
                .joinToString("\n")
                .takeLast(maxChars)
            if (tail.isBlank()) "" else "\n$tail"
        }.getOrDefault("")

    /**
     * Ждёт, пока mihomo действительно возьмёт наш дескриптор.
     *
     * Отдельного «tun готов» ядро наружу не отдаёт, поэтому смотрим лог, и
     * сразу на оба исхода: `[TUN] Tun adapter listening at:` при успехе,
     * `Start TUN listening error:` при отказе. Ошибка ценна сама по себе —
     * причина в ней уже названа, и пользователю уезжает она, а не «не
     * работает».
     *
     * Молчание не считаем отказом: успех ядро пишет уровнем info, а уровень
     * лога выбирает пользователь, и на `warning` строки просто не будет. Ошибка
     * же видна на всех уровнях, кроме `silent`, — поэтому вышедшее время
     * означает «доказательств отказа нет», и это не повод рвать подключение.
     */
    private suspend fun awaitMihomoTun(timeoutMs: Int = 4000) {
        val file = File(filesDir, CORE_LOG_FILE)
        var waited = 0
        while (waited < timeoutMs) {
            val log = runCatching { file.readText() }.getOrDefault("")
            val failure = log.lineSequence().lastOrNull { it.contains(MIHOMO_TUN_FAILED) }
            if (failure != null) {
                throw IllegalStateException(
                    "mihomo did not take over the tunnel: " +
                        failure.substringAfter(MIHOMO_TUN_FAILED).trim().take(300)
                )
            }
            if (log.contains(MIHOMO_TUN_READY)) {
                android.util.Log.i("KEQDIS", "mihomo tun adapter is up")
                return
            }
            delay(100); waited += 100
        }
        android.util.Log.i("KEQDIS", "mihomo tun: no verdict in the log, continuing")
    }

    /**
     * Дописывает в готовый конфиг mihomo номер дескриптора TUN и MTU.
     *
     * Обе величины принадлежат этой стороне и только ей: интерфейс поднимает
     * сервис, дескриптор существует лишь в этом процессе, а [TUN_MTU] —
     * константа сервиса. Держать их копию в Dart значило бы завести второй
     * источник правды для числа, которое ОБЯЗАНО совпадать: у fd-устройства
     * ядро не может спросить MTU у системы и берёт своё умолчание, а
     * расхождение с интерфейсом — это пакеты, которые netstack считает
     * допустимыми, а ядро ОС на записи в tun отбрасывает (ровно та же
     * ловушка, что с `--mtu` у tun2socks).
     *
     * Конфиг переписывается на месте: экран «Соединения» и реконнект из плитки
     * читают координаты API из того же файла.
     */
    private fun injectTunFd(configPath: String, tunFd: Int) {
        val file = File(configPath)
        val root = org.json.JSONObject(file.readText())
        val tun = root.optJSONObject("tun")
            ?: throw IllegalStateException(
                "mihomo config has no `tun` section — the core cannot take over " +
                    "the tunnel without it"
            )
        tun.put("file-descriptor", tunFd)
        tun.put("mtu", TUN_MTU)
        root.put("tun", tun)
        file.writeText(yamlSafeJson(root.toString()))
        android.util.Log.i("KEQDIS", "mihomo tun: fd=$tunFd mtu=$TUN_MTU")
    }

    /**
     * Снимает escape-последовательность `\/`, которую вставляет `org.json`.
     *
     * Конфиг мы пишем обычным JSON, а разбирает его ядро YAML-парсером
     * (`gopkg.in/yaml.v3`) — YAML 1.2 надмножество JSON, и до сих пор это
     * работало. Но `JSONStringer` в Android экранирует ещё и косую черту:
     * `"https://1.1.1.1/dns-query"` превращается в `"https:\/\/1.1.1.1\/…"`.
     * Для JSON это законно, а таблица escape-ов go-yaml (`scannerc.go`) знает
     * `\t \n \r \f \" \\ \uXXXX`, но НЕ `\/` — и разбор обрывается на первом же
     * слэше: `Parse config error: yaml: found unknown escape character`. Ядро не
     * стартует вовсе, а снаружи это выглядит как долгое подключение и падение,
     * потому что мы всё это время ждём SOCKS-порт, которого не будет.
     *
     * Слэшей в конфиге полно всегда: адреса DoH, CIDR-правила, пути транспортов.
     * Поэтому ломается ЛЮБОЙ конфиг, а не какой-то особенный.
     *
     * Идём по строке с учётом самих escape-ов: `\\` копируем парой, чтобы
     * следующий за ней слэш не сошёл за экранированный.
     */
    private fun yamlSafeJson(json: String): String {
        if (!json.contains("\\/")) return json
        val out = StringBuilder(json.length)
        var i = 0
        while (i < json.length) {
            val c = json[i]
            if (c == '\\' && i + 1 < json.length) {
                val next = json[i + 1]
                if (next == '/') out.append('/') else out.append(c).append(next)
                i += 2
                continue
            }
            out.append(c)
            i++
        }
        return out.toString()
    }

    private fun startXray(
        binary: String,
        config: String,
        coreKind: String = CORE_KIND_XRAY,
        tunFd: Int = -1,
    ): Int {
        // NativeHelper.startCore: fork+execv из nativeLibraryDir, дублирует вывод ядра
        // в logcat (KEQDIS_XRAY) и в файл CORE_LOG_FILE (его читает getXrayLogs).
        // Возвращает: pid > 0 — успех, -1 binary not found, -2 config not found, -4 crashed immediately
        XrayGeoAssets.ensure(this, filesDir)
        // Свежий лог ядра на каждую сессию (ping пишет в свой файл/никуда — не мешает).
        runCatching { File(filesDir, CORE_LOG_FILE).writeText("") }
        val pid = NativeHelper.startCore(
            binary, config, filesDir.absolutePath, CORE_LOG_FILE, coreKind, tunFd,
        )
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
                        // Убиваем tun2socks немедленно при падении Xray: иначе
                        // старый tun2socks доживает до следующего запуска и
                        // подключается к новому Xray со старыми credentials
                        // → invalid password.
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
            var tick = 0
            val pm = getSystemService(POWER_SERVICE) as android.os.PowerManager

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

                // Живая активность в нативном уведомлении: Dart-уведомление со
                // скоростями живёт только пока жив Flutter, а этот foreground —
                // всегда. Без обновлений оно застывало на «Connected», и было «не
                // понятно, отвалился серв или нет». notify() вместо startForeground:
                // сервис уже foreground с этим ID, апдейт текста так дешевле.
                // isInteractive: при погашенном экране уведомление никто не видит —
                // не дёргаем NotificationManager (IPC + RemoteViews) 30 раз в минуту
                // всю ночь; после включения экрана текст освежится ближайшим тиком.
                tick++
                if (status == VpnRunStatus.RUNNING && tick % 2 == 0 && pm.isInteractive) {
                    // Пользователь мог оффнуть аптайм и/или скорость в уведомлении
                    // (настройки в Appearance) — собираем строку из включённых частей.
                    val prefs = readNotifBodyPrefs()
                    val parts = ArrayList<String>(3)
                    if (prefs.showUptime) {
                        parts.add(formatUptime(System.currentTimeMillis() - startTime))
                    }
                    if (prefs.showSpeed) {
                        parts.add("↓ ${formatSpeed(downloadSpeed.get())}")
                        parts.add("↑ ${formatSpeed(uploadSpeed.get())}")
                    }
                    val body = if (parts.isEmpty()) "Connected" else parts.joinToString("  ·  ")
                    runCatching {
                        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).notify(
                            NOTIFICATION_ID,
                            buildControlNotification(body, isConnected = true, isTransitioning = false),
                        )
                    }
                }
            }
        }
    }

    private fun formatSpeed(bytesPerSec: Long): String = when {
        bytesPerSec >= 1024 * 1024 ->
            String.format(java.util.Locale.US, "%.1f MB/s", bytesPerSec / (1024.0 * 1024.0))
        bytesPerSec >= 1024 ->
            String.format(java.util.Locale.US, "%.1f KB/s", bytesPerSec / 1024.0)
        else -> "$bytesPerSec B/s"
    }

    private fun formatUptime(ms: Long): String {
        val s = ms / 1000
        val h = s / 3600
        val m = (s % 3600) / 60
        val sec = s % 60
        return when {
            h > 0 -> "${h}h ${m}m"
            m > 0 -> "${m}m ${sec}s"
            else -> "${sec}s"
        }
    }

    // Что показывать в строке уведомления (аптайм / скорость) — настройки из
    // приложения. Flutter хранит AppSettings как JSON-строку в
    // FlutterSharedPreferences с префиксом "flutter.". Читаем прямо оттуда —
    // работает для всех путей старта (Dart, плитка, кнопка уведомления), без
    // прокидывания extra через Intent.
    private data class NotifBodyPrefs(val showUptime: Boolean, val showSpeed: Boolean)

    // Дебаг-режим приложения. Он гейтит подробный лог tun2socks: тот пишет
    // строку на каждое соединение, и держать это включённым всегда незачем.
    private fun readDebugMode(): Boolean {
        return try {
            val raw = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getString("flutter.keqdis_settings", null) ?: return false
            org.json.JSONObject(raw).optBoolean("debugMode", false)
        } catch (e: Exception) {
            false
        }
    }

    private fun readNotifBodyPrefs(): NotifBodyPrefs {
        return try {
            val raw = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getString("flutter.keqdis_settings", null) ?: return NotifBodyPrefs(true, true)
            val o = org.json.JSONObject(raw)
            NotifBodyPrefs(
                o.optBoolean("showUptimeInNotification", true),
                o.optBoolean("showSpeedInNotification", true),
            )
        } catch (e: Exception) {
            NotifBodyPrefs(true, true)
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
                when {
                    isConnected -> "VPN Connected$serverSuffix"
                    // Во время подключения/отключения не пишем «Disconnected»:
                    // сочетание «VPN Disconnected · сервер» + «Connecting…» читалось
                    // как противоречие/зависание.
                    isTransitioning -> "VPN$serverSuffix"
                    else -> "VPN Disconnected$serverSuffix"
                }
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
                        // Тем же ядром, что и в прошлой сессии: конфиг на диске
                        // написан под него, чужое ядро его не разберёт.
                        putExtra(
                            EXTRA_VPN_BACKEND,
                            if (lastCoreKind == CORE_KIND_MIHOMO) VPN_BACKEND_MIHOMO
                            else VPN_BACKEND_XRAY,
                        )
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
