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
import android.net.ConnectivityManager
import android.net.Network
import android.net.VpnService
import android.os.Binder
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.File
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URL
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
        // строка в лог ядра: откуда сессия, которую поднял не человек
        const val EXTRA_LOG_NOTE       = "log_note"
        const val VPN_BACKEND_XRAY     = "xray"
        const val VPN_BACKEND_MIHOMO   = "mihomo"

        const val CORE_KIND_XRAY       = "xray"
        const val CORE_KIND_MIHOMO     = "mihomo"
        // движок остался со времён keqrnel: на Android он всегда chain, поле живёт ради старых записей плитки
        const val EXTRA_CORE_ENGINE    = "core_engine"
        const val CORE_ENGINE_CHAIN    = "chain"
        const val CORE_ENGINE_KEQRNEL  = "keqrnel"
        // в режиме прокси establish() не зовётся: ни интерфейса, ни диалога разрешения.
        // ядро слушает 127.0.0.1, а loopback на Android общий для всех приложений
        const val EXTRA_TUNNEL_MODE    = "tunnel_mode"
        const val TUNNEL_MODE_VPN      = "tun"
        const val TUNNEL_MODE_PROXY    = "proxy"
        const val CORE_LOG_FILE        = "core_logs.txt"

        // без второй строки пустой хвост лога читается как логи не пишутся
        const val CORE_GONE_HINT =
            "a process killed from outside gets no chance to write a farewell, " +
                "so silence above this line is the symptom, not a missing log; " +
                "the usual killers are the child process limits of Android 12+ " +
                "and vendor battery savers"
        // только так узнать, взял ли mihomo наш дескриптор. строки из listener/listener.go: ReCreateTun
        const val MIHOMO_TUN_READY     = "[TUN] Tun adapter listening at:"
        const val MIHOMO_TUN_FAILED    = "Start TUN listening error:"
        const val NOTIFICATION_ID      = 1337
        const val CHANNEL_ID_CONTROL   = "keqdis_vpn_control"
        const val TUN_ADDRESS          = "172.19.0.1"
        const val TUN_PREFIX           = 30
        const val TUN_MTU              = 1400
        // второй хост нашей /30, слушать на нём некому: запрос всё равно уйдёт в tun0 и попадёт в перехват 53.
        // держать в паре с _androidTunDns в Dart
        const val TUN_DNS_ADDRESS      = "172.19.0.2"

        const val BROADCAST_ACTION_DISCONNECT = "com.keqdis.vpn.NOTIF_DISCONNECT"

        const val BROADCAST_VPN_STATUS_CHANGED = "com.keqdis.vpn.STATUS_CHANGED"

        const val PREFS_QS = "keqdis_vpn_prefs"
        const val KEY_QS_STATUS = "qs_status"

        // в памяти процесса: запись в prefs переживает его смерть, и после убийства приложения там оставался connected.
        // плитка верила записи и на нажатие слала стоп. поле с каждым запуском начинается с disconnected
        @JvmStatic
        @Volatile
        var liveStatus: String = "disconnected"
            private set

        // для сторожа автовыбора: -1 пока сеть не слушаем. по счётчику смен он узнаёт новую сеть и кончает паузу
        @JvmStatic
        @Volatile
        var physicalNetworks: Int = -1
            private set
        @JvmStatic
        @Volatile
        var networkChanges: Int = 0
            private set
        const val KEY_QS_ERROR = "qs_error"
        const val KEY_QS_LAST_XRAY_CONFIG = "qs_last_xray_config"
        const val KEY_QS_LAST_SOCKS_USERNAME = "qs_last_socks_username"
        const val KEY_QS_LAST_SOCKS_PASSWORD = "qs_last_socks_password"
        const val KEY_QS_LAST_SOCKS_PORT = "qs_last_socks_port"
        const val KEY_QS_LAST_BACKEND = "qs_last_backend"
        const val KEY_QS_LAST_CORE_ENGINE = "qs_last_core_engine"
        const val KEY_QS_LAST_CORE_KIND   = "qs_last_core_kind"
        // плитка обязана переподключаться тем же режимом, иначе из только прокси поднимала бы полноценный VPN
        const val KEY_QS_LAST_TUNNEL_MODE = "qs_last_tunnel_mode"
        const val KEY_QS_LAST_SERVER_NAME = "qs_last_server_name"
        const val KEY_QS_LAST_EXCLUDE_PACKAGES = "qs_last_exclude_packages"
        const val KEY_QS_LAST_INCLUDE_PACKAGES = "qs_last_include_packages"

        // статус тут не годится: новый процесс чинит его в onCreate раньше onStartCommand
        const val KEY_QS_SESSION_WANTED = "qs_session_wanted"

        const val KEY_QS_DIRECT_START_BLOCKED_ON = "qs_direct_start_blocked_on"

        // null, если файл конфига пропал (путь в prefs переживает очистку данных) или запись от старого AWG-ядра
        fun snapshotStartIntent(context: Context): Intent? {
            val prefs = context.getSharedPreferences(PREFS_QS, Context.MODE_PRIVATE)
            val backend = prefs.getString(KEY_QS_LAST_BACKEND, VPN_BACKEND_XRAY) ?: VPN_BACKEND_XRAY
            if (backend != VPN_BACKEND_XRAY && backend != VPN_BACKEND_MIHOMO) return null
            val config = prefs.getString(KEY_QS_LAST_XRAY_CONFIG, null)
            val user = prefs.getString(KEY_QS_LAST_SOCKS_USERNAME, null)
            val pass = prefs.getString(KEY_QS_LAST_SOCKS_PASSWORD, null)
            if (config.isNullOrBlank() || user.isNullOrBlank() || pass.isNullOrBlank() ||
                !File(config).exists()
            ) return null
            val exclude = prefs.getStringSet(KEY_QS_LAST_EXCLUDE_PACKAGES, emptySet()) ?: emptySet()
            val include = prefs.getStringSet(KEY_QS_LAST_INCLUDE_PACKAGES, emptySet()) ?: emptySet()
            val serverName = prefs.getString(KEY_QS_LAST_SERVER_NAME, null)

            return Intent(context, KeqdisVpnService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_VPN_BACKEND, backend)
                // chain явно: иначе всплыл бы keqrnel, сохранённый старыми версиями
                putExtra(EXTRA_CORE_ENGINE, CORE_ENGINE_CHAIN)
                // режим тоже явно: иначе из только прокси поднимался бы VPN, на который может не быть разрешения
                putExtra(
                    EXTRA_TUNNEL_MODE,
                    prefs.getString(KEY_QS_LAST_TUNNEL_MODE, TUNNEL_MODE_VPN) ?: TUNNEL_MODE_VPN,
                )
                putExtra(EXTRA_XRAY_CONFIG, config)
                putExtra("socks_port", prefs.getInt(KEY_QS_LAST_SOCKS_PORT, 2080))
                putStringArrayListExtra("exclude_packages", ArrayList(exclude))
                putStringArrayListExtra("include_packages", ArrayList(include))
                putExtra(EXTRA_SOCKS_USERNAME, user)
                putExtra(EXTRA_SOCKS_PASSWORD, pass)
                if (!serverName.isNullOrBlank()) putExtra(EXTRA_SERVER_NAME, serverName)
            }
        }

        fun startsTunnel(intent: Intent): Boolean =
            intent.getStringExtra(EXTRA_TUNNEL_MODE) != TUNNEL_MODE_PROXY

        // подъём Wi-Fi это три события подряд, и каждое может увести default network. до устойчивого состояния около 2 с
        private const val HANDOVER_DEBOUNCE_MS = 2_000L

        // ядро, прожившее дольше 30 с, поднимаем всегда. трижды подряд умершее сразу сломано само,
        // круг перезапусков прятал бы это за подключено
        private const val CORE_QUICK_DEATH_MS = 30_000L
        private const val CORE_MAX_QUICK_DEATHS = 3

        private const val MEMORY_SNAPSHOT_TICKS = 600
        private const val MEMORY_GROWTH_ALARM = 256L * 1024 * 1024
    }

    // креды приходят от MainActivity, так они совпадают с записанными в конфиг ядра
    @Volatile var socksUsername: String    = ""
    @Volatile var socksPassword: String    = ""

    @Volatile private var status              = VpnRunStatus.STOPPED
    @Volatile private var currentServerName: String? = null
    @Volatile private var lastXrayConfigPath: String? = null
    @Volatile private var lastSocksPort: Int = 2080
    @Volatile private var lastCoreEngine: String = CORE_ENGINE_KEQRNEL
    @Volatile private var lastCoreKind: String = CORE_KIND_XRAY
    @Volatile private var lastTunnelMode: String = TUNNEL_MODE_VPN
    @Volatile private var lastExcludePackages: List<String> = emptyList()
    @Volatile private var lastIncludePackages: List<String> = emptyList()
    @Volatile private var xrayPid:            Int                   = -1
    @Volatile private var coreStartedAt:      Long                  = 0L
    @Volatile private var quickCoreDeaths:    Int                   = 0
    @Volatile private var tunInterface:       ParcelFileDescriptor? = null
    @Volatile private var ownerServer:        ConnectionOwnerServer? = null
    @Volatile private var tunOnlySelected:    Boolean               = false
    @Volatile private var cleanupDone:       Boolean              = false
    @Volatile private var activeSocksPort:   Int                  = 2080

    @Volatile private var networkCallback: ConnectivityManager.NetworkCallback? = null
    // список, а не одна сеть: весь вопрос в том, жива ли рядом с новой старая
    private val liveNetworks = LinkedHashSet<Network>()
    @Volatile private var watchStartedAt = 0L
    @Volatile private var handoverJob: Job? = null

    // без него быстрое перещёлкивание плитки пускало старт поверх ещё идущего cleanup() стопа,
    // и они дрались за pid, TUN и SOCKS-порт
    private val opMutex = Mutex()
    // stopSelf(startId) не убьёт сервис, если уже пришла более новая команда
    @Volatile private var latestStartId = 0

    private val serviceScope = CoroutineScope(
        Dispatchers.IO + SupervisorJob() + CoroutineExceptionHandler { _, e ->
            NativeLog.e("KEQDIS", "Uncaught coroutine: ${e.message}", e)
        }
    )
    @Volatile private var statusListener: StatusListener? = null
    private var startTime     = 0L
    private val uploadTotal   = AtomicLong(0)
    private val downloadTotal = AtomicLong(0)
    private val uploadSpeed   = AtomicLong(0)
    private val downloadSpeed = AtomicLong(0)

    private var notificationActionReceiver: BroadcastReceiver? = null

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
        fun getXrayPid()         = xrayPid
        // текущая сессия, а не настройка: ядро меняют на ходу, а работает то, с которым подключились
        fun getCoreKind()        = lastCoreKind
    }
    private val binder = LocalBinder()

    override fun onBind(intent: Intent?): IBinder? {
        // системному биндингу нужен super.onBind(), иначе onRevoke() не придёт,
        // и при перехвате VPN другим приложением сервис навсегда останется в RUNNING
        return if (intent?.action == VpnService.SERVICE_INTERFACE) super.onBind(intent) else binder
    }

    override fun onCreate() {
        super.onCreate()
        // новый экземпляр сервиса всегда STOPPED: процесс могли убить, не дав записать финальный статус,
        // и тайл висел бы в connecting. настоящему старту не мешает, ACTION_START придёт следом
        val stale = getSharedPreferences(PREFS_QS, Context.MODE_PRIVATE)
            .getString(KEY_QS_STATUS, "disconnected")
            ?.lowercase()
        if (stale != "disconnected" && stale != "error") {
            NativeLog.w("KEQDIS", "onCreate: healing stale persisted status '$stale' → disconnected")
            setStatus(VpnRunStatus.STOPPED)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        latestStartId = startId
        // без команды это перезапуск системой после смерти процесса (START_STICKY), с action VpnService это Постоянный VPN.
        // Dart не запущен, конфиг собрать некому, поэтому по снапшоту, как плитка
        if (intent == null || intent.action == VpnService.SERVICE_INTERFACE) {
            return runCatching { restoreSession(startId, alwaysOn = intent != null) }
                .getOrElse {
                    // упавший здесь процесс система подняла бы снова тем же путём, по кругу
                    NativeLog.e("KEQDIS", "restore failed: ${it.message}", it)
                    stopSelf(startId)
                    START_NOT_STICKY
                }
        }
        when (intent.action) {
            ACTION_TOGGLE -> {
                if (status == VpnRunStatus.RUNNING || status == VpnRunStatus.STARTING) {
                    serviceScope.launch { stopVpn(startId) }
                } else if (status == VpnRunStatus.STOPPED || status == VpnRunStatus.ERROR) {
                    // конфиг собирает Dart, поэтому открываем приложение
                    val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                    launchIntent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    launchIntent?.putExtra("action", "connect_from_notification")
                    startActivity(launchIntent)
                }
                return START_NOT_STICKY
            }
            ACTION_START -> return startSession(
                intent, startId, logNote = intent.getStringExtra(EXTRA_LOG_NOTE),
            )
            ACTION_STOP -> serviceScope.launch { stopVpn(startId) }
        }
        return START_NOT_STICKY
    }

    // после перезапуска поднимаем, только если сессия должна была жить, иначе поднялось бы выключенное человеком.
    // Постоянный VPN выполняем всегда
    private fun restoreSession(startId: Int, alwaysOn: Boolean): Int {
        // пока туннель поднимается, система шлёт запуск ещё раз (Vpn.startAlwaysOnVpn)
        if (status == VpnRunStatus.RUNNING || status == VpnRunStatus.STARTING) return START_STICKY

        val wanted = getSharedPreferences(PREFS_QS, Context.MODE_PRIVATE)
            .getBoolean(KEY_QS_SESSION_WANTED, false)
        if (!alwaysOn && !wanted) {
            NativeLog.i("KEQDIS", "restore: no session was supposed to be up, staying down")
            stopSelf(startId)
            return START_NOT_STICKY
        }

        val start = snapshotStartIntent(this)
        val refusal = when {
            start == null -> "there is no server to reconnect to, connect from the app once"
            // Постоянный VPN ждёт интерфейс, и система висела бы в подключается
            alwaysOn && !startsTunnel(start) ->
                "the last session was a local proxy, and always-on VPN needs a tunnel"
            startsTunnel(start) && VpnService.prepare(this) != null ->
                "the VPN permission was taken away"
            else -> null
        }
        if (start == null || refusal != null) {
            NativeLog.w("KEQDIS", "restore (alwaysOn=$alwaysOn): $refusal")
            appendCoreLog("could not bring the VPN back: $refusal")
            rememberSessionWanted(false)
            stopSelf(startId)
            return START_NOT_STICKY
        }

        // сессия без человека пишет в лог, откуда взялась: это ответ на почему отключилось
        val note = if (alwaysOn) {
            "started by the system always-on VPN setting"
        } else {
            "the system restarted the VPN after the app process died " +
                "(${ProcessExits.describeLast(this) ?: "no exit record"}), reconnecting"
        }
        return startSession(start, startId, logNote = note)
    }

    private fun startSession(intent: Intent, startId: Int, logNote: String? = null): Int {
        val backend = intent.getStringExtra(EXTRA_VPN_BACKEND) ?: VPN_BACKEND_XRAY
        val socksPort   = intent.getIntExtra("socks_port", 2080)
        val excludePkgs = intent.getStringArrayListExtra("exclude_packages") ?: arrayListOf()
        val includePkgs = intent.getStringArrayListExtra("include_packages") ?: arrayListOf()
        currentServerName = intent.getStringExtra(EXTRA_SERVER_NAME)
        lastSocksPort = socksPort
        lastExcludePackages = excludePkgs
        lastIncludePackages = includePkgs

        val configPath = intent.getStringExtra(EXTRA_XRAY_CONFIG) ?: run {
            NativeLog.e("KEQDIS", "onStartCommand: missing EXTRA_XRAY_CONFIG")
            return START_NOT_STICKY
        }
        val user = intent.getStringExtra(EXTRA_SOCKS_USERNAME)
        val pass = intent.getStringExtra(EXTRA_SOCKS_PASSWORD)
        if (user.isNullOrEmpty() || pass.isNullOrEmpty()) {
            NativeLog.e("KEQDIS", "onStartCommand: SOCKS5 credentials missing in Intent — aborting start")
            return START_NOT_STICKY
        }
        socksUsername = user
        socksPassword = pass

        val coreEngine = intent.getStringExtra(EXTRA_CORE_ENGINE) ?: CORE_ENGINE_CHAIN
        lastCoreEngine = coreEngine

        // ядро запоминаем рядом с configPath: конфиг mihomo libxray не разберёт, и плитка падала в ERROR
        val coreKind =
            if (backend == VPN_BACKEND_MIHOMO) CORE_KIND_MIHOMO else CORE_KIND_XRAY
        lastCoreKind = coreKind

        val tunnelMode =
            if (intent.getStringExtra(EXTRA_TUNNEL_MODE) == TUNNEL_MODE_PROXY) {
                TUNNEL_MODE_PROXY
            } else {
                TUNNEL_MODE_VPN
            }
        lastTunnelMode = tunnelMode

        NativeLog.i(
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
                .putString(KEY_QS_LAST_TUNNEL_MODE, tunnelMode)
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
        try {
            startForeground(
                NOTIFICATION_ID,
                buildControlNotification("Connecting…", isConnected = false, isTransitioning = true)
            )
        } catch (e: Exception) {
            // после перезапуска системой foreground разрешает исключение REASON_OP_ACTIVATE_VPN, и прошивка вправе его не признать.
            // необработанный отказ уронил бы процесс, и система поднимала бы его снова
            NativeLog.e("KEQDIS", "startForeground refused: $e")
            appendCoreLog("the system did not let the VPN run in the foreground: ${e.message}")
            unregisterNotificationReceiver()
            stopSelf(startId)
            return START_NOT_STICKY
        }

        // этого ждёт плитка (verifyStarted), чтобы отличить запрет системы от задержки. setStatus() нельзя:
        // STARTING в status принимается за дубль-старт. только с холодного, иначе плитка откатилась бы с подключено
        if (status == VpnRunStatus.STOPPED || status == VpnRunStatus.ERROR) {
            liveStatus = "connecting"
        }

        serviceScope.launch {
            startGuarded(startId) {
                startVpnWithXray(
                    startId, configPath, socksPort, excludePkgs, includePkgs,
                    socksNoAuth = false, coreEngine = coreEngine, coreKind = coreKind,
                    tunnelMode = tunnelMode, logNote = logNote,
                )
            }
        }
        // убитый процесс Android поднимет и позовёт без команды, сессия восстановится сама.
        // с NOT_STICKY туннель пропадал до ручного подключения
        return START_STICKY
    }

    private fun rememberSessionWanted(wanted: Boolean) {
        runCatching {
            getSharedPreferences(PREFS_QS, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_QS_SESSION_WANTED, wanted)
                .apply()
        }
    }

    override fun onRevoke() { serviceScope.launch { stopVpn() }; super.onRevoke() }

    override fun onDestroy() {
        // полный cleanup() тут был бы runBlocking на main thread, то есть ANR. ветка только для убийства без stopVpn()
        if (!cleanupDone) {
            runCatching {
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

    // коннект мог зависнуть навсегда (стоп держит opMutex, establish() не вернулся), и в уведомлении висело Connecting без исхода

    private suspend fun startGuarded(startId: Int, block: suspend () -> Unit) {
        try {
            kotlinx.coroutines.withTimeout(45_000L) { block() }
        } catch (e: kotlinx.coroutines.TimeoutCancellationException) {
            NativeLog.e("KEQDIS", "start watchdog fired: connect attempt hung")
            setStatus(VpnRunStatus.ERROR, "Connection attempt timed out")
            // вне мьютекса: возможно, завис его владелец
            runCatching { cleanup() }
            showControlNotification(
                "Connection timed out",
                isConnected = false,
                isTransitioning = false,
            )
            stopForeground(STOP_FOREGROUND_REMOVE)
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
        tunnelMode: String = TUNNEL_MODE_VPN,
        logNote: String? = null,
    ) = opMutex.withLock {
        if (status == VpnRunStatus.RUNNING || status == VpnRunStatus.STARTING) {
            if (status == VpnRunStatus.RUNNING) {
                showControlNotification("Connected", isConnected = true, isTransitioning = false)
            }
            return@withLock
        }
        setStatus(VpnRunStatus.STARTING)
        // под opMutex: при смене сервера стоп и старт идут подряд, записанным должно остаться последнее
        rememberSessionWanted(true)
        quickCoreDeaths = 0
        try {
            if (!socksNoAuth && (socksUsername.isEmpty() || socksPassword.isEmpty())) {
                throw IllegalStateException("SOCKS5 credentials are empty — Intent was malformed")
            }

            // сначала ядра от прошлой жизни приложения: старое держит SOCKS-порт, и прокси приложения уходит в чужую сессию
            // с чужими кредами (rejected username/password). isPortOpen ниже этого не ловит, порт-то открыт
            if (NativeHelper.killOrphans() > 0) {
                // SIGKILL асинхронен, сокет освобождается не сразу
                var waitedFree = 0
                while (isPortOpen("127.0.0.1", socksPort) && waitedFree < 2000) {
                    delay(100); waitedFree += 100
                }
            }

            val isMihomo = coreKind == CORE_KIND_MIHOMO
            val proxyOnly = tunnelMode == TUNNEL_MODE_PROXY
            // спрашиваем конфиг, а не настройку: по нему ядро себя ведёт, и он же лежит на диске для плитки,
            // а настройка могла смениться между сборкой конфига и реконнектом
            val xrayOwnsTun = !isMihomo && !proxyOnly && xrayConfigHasTun(xrayConfigPath)

            // интерфейс раньше ядра: номер дескриптора нужен на старте. mihomo получает его в конфиге, xray в окружении
            if (isMihomo && !proxyOnly) {
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
            } else if (isMihomo) {
                activeSocksPort = socksPort
                xrayPid = startXray(
                    getBinaryPath("libmihomo.so"),
                    xrayConfigPath,
                    coreKind,
                )
            } else if (xrayOwnsTun) {
                val tun = buildTunInterface(excludePkgs, includePkgs)
                tunInterface = tun
                val tunRawFd = tun.fd
                injectXrayTunMtu(xrayConfigPath)
                activeSocksPort = socksPort
                xrayPid = startXray(
                    getBinaryPath("libxray.so"),
                    xrayConfigPath,
                    coreKind,
                    tunFd = tunRawFd,
                )
            } else {
                // VPN без tun-инбаунда значит на диске конфиг старой версии (плитка сразу после обновления):
                // интерфейс встанет, а читать его будет некому
                if (!proxyOnly) {
                    throw IllegalStateException(
                        "Config predates the in-core tunnel — reconnect from the app once"
                    )
                }
                xrayPid = startXray(
                    getBinaryPath("libxray.so"),
                    xrayConfigPath,
                    coreKind,
                )
            }
            // после startXray: он начинает лог с чистого листа
            logNote?.let { appendCoreLog(it) }

            val coreName = if (isMihomo) "mihomo" else "Xray"
            var waited = 0
            while (!isPortOpen("127.0.0.1", socksPort) && waited < 10000) {
                // смерть ядра видна по /proc: после двойного fork оно нам внук, waitpid звать некому.
                // раньше она стоила десяти секунд ожидания порта
                val pid = xrayPid
                if (pid > 0 && !File("/proc/$pid").exists())
                    throw IllegalStateException("$coreName exited on startup${coreLogTail()}")
                // шаг мелкий: пауза целиком уходит в ожидание человека
                delay(100); waited += 100
            }
            if (!isPortOpen("127.0.0.1", socksPort))
                throw IllegalStateException(
                    "$coreName SOCKS5 port $socksPort not ready${coreLogTail()}"
                )

            // открытый порт у mihomo не значит, что туннель взлетел: tun-листенер поднимается позже,
            // а его падение ядро переживает молча, и снаружи подключено без трафика
            if (isMihomo && !proxyOnly) awaitMihomoTun()

            if (proxyOnly) {
                // порт объявляем и без туннеля: на него смотрят Внутренности и плитка
                activeSocksPort = socksPort
            }

            startTime = System.currentTimeMillis()
            setStatus(VpnRunStatus.RUNNING)
            // в режиме прокси ключика VPN в статусбаре нет, без подписи непонятно, работает ли что-то
            showControlNotification(
                if (proxyOnly) "Proxy · 127.0.0.1:$socksPort" else "Connected",
                isConnected = true,
                isTransitioning = false,
            )
            startStatsLoop()
            startNetworkWatch()
            startHyperOsUnderlyingWatch()

        } catch (e: Exception) {
            if (e is kotlinx.coroutines.CancellationException) {
                // отмена вотчдогом: чистим и пробрасываем, исход покажет startGuarded
                runCatching { cleanup() }
                throw e
            }
            NativeLog.e("KEQDIS", "startVpn failed: ${e.message}", e)
            setStatus(VpnRunStatus.ERROR, e.message)
            cleanup()
            showControlNotification(e.message ?: "Error", isConnected = false, isTransitioning = false)
            stopForeground(STOP_FOREGROUND_REMOVE)
            unregisterNotificationReceiver()
            stopSelf(startId)
        }
    }

    private suspend fun stopVpn(startId: Int? = null) = opMutex.withLock {
        rememberSessionWanted(false)
        if (status == VpnRunStatus.STOPPED) {
            // prefs могли пережить убийство процесса с connected, пересинхронизируем, чтобы тайл отлип
            setStatus(VpnRunStatus.STOPPED)
            if (startId != null) stopSelf(startId) else stopSelf()
            return@withLock
        }

        // STOPPED до cleanup: плитка обновится сразу, а не после многосекундного убийства процессов
        setStatus(VpnRunStatus.STOPPED)
        handoverJob?.cancel()
        handoverJob = null
        showControlNotification("Disconnected", isConnected = false, isTransitioning = false)
        withContext(Dispatchers.Main) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        }
        unregisterNotificationReceiver()

        // cleanup() внутри мьютекса: в отдельной корутине он гонялся бы с новым стартом
        try {
            cleanup()
        } catch (e: Exception) {
            NativeLog.w("KEQDIS", "cleanup failed: ${e.message}")
        } finally {
            cleanupDone = true
            if (startId != null) stopSelf(startId) else stopSelf()
        }
    }

    private suspend fun cleanup() {
        stopNetworkWatch()

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
        ownerServer?.close()
        ownerServer = null

        // креды не сбрасываем: с ними дозавершается запущенное ядро, живут до следующего старта
        startTime = 0L
        uploadTotal.set(0); downloadTotal.set(0)
        uploadSpeed.set(0); downloadSpeed.set(0)
    }

    // открытые соединения ядра после подъёма Wi-Fi оставались на LTE 78 с (Pixel 6a, 30.08.2026), а это вдесятеро медленнее.
    // само ядро не узнает: у xray монитора сети нет, у mihomo он только с auto-route, а netlink с Android 14 закрыт.
    // registerDefaultNetworkCallback в VPN-приложении отдаёт наш же туннель, поэтому NOT_VPN и порядок событий

    private fun startNetworkWatch() {
        if (networkCallback != null) return
        val cm = getSystemService(ConnectivityManager::class.java) ?: return
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = onPhysicalNetworkUp(network)
            override fun onLost(network: Network) = onPhysicalNetworkDown(network)
        }
        val request = android.net.NetworkRequest.Builder()
            .addCapability(android.net.NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(android.net.NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()
        watchStartedAt = System.currentTimeMillis()
        runCatching { cm.registerNetworkCallback(request, cb) }
            .onSuccess { networkCallback = cb }
            .onFailure { NativeLog.w("KEQDIS", "network watch: register failed: ${it.message}") }
    }

    // отложенный сброс тут не отменяем: сюда приходят и из самого сброса, отмена прервала бы текущую корутину
    private fun stopNetworkWatch() {
        networkCallback?.let { cb ->
            runCatching {
                getSystemService(ConnectivityManager::class.java)?.unregisterNetworkCallback(cb)
            }
        }
        networkCallback = null
        synchronized(liveNetworks) {
            liveNetworks.clear()
            physicalNetworks = -1
        }
        watchStartedAt = 0L
        stopHyperOsUnderlyingWatch()
    }

    // переезд только когда рядом уже была живая сеть: старая никуда не делась, и её соединения рвать нам
    private fun onPhysicalNetworkUp(network: Network) {
        val hadOther = synchronized(liveNetworks) {
            val other = liveNetworks.any { it != network }
            liveNetworks.add(network)
            physicalNetworks = liveNetworks.size
            networkChanges++
            other
        }
        applyHuaweiUnderlying(network)
        if (!hadOther) return
        // регистрация приносит все живые сети пачкой, на старте это похоже на переезд
        if (System.currentTimeMillis() - watchStartedAt < HANDOVER_DEBOUNCE_MS) return

        NativeLog.i("KEQDIS", "handover: network $network came up next to a live one")
        handoverJob?.cancel()
        handoverJob = serviceScope.launch {
            delay(HANDOVER_DEBOUNCE_MS)
            resetCoreConnections()
        }
    }

    // сокеты ушли вместе с сетью. забываем её, иначе её возвращение не будет переездом
    private fun onPhysicalNetworkDown(network: Network) {
        val remaining = synchronized(liveNetworks) {
            liveNetworks.remove(network)
            physicalNetworks = liveNetworks.size
            networkChanges++
            liveNetworks.lastOrNull()
        }
        remaining?.let { applyHuaweiUnderlying(it) }
    }

    // у mihomo DELETE /connections, статус даже не мигнёт. у xray такой команды нет: rmo и sib проверены на живом ядре,
    // установленные соединения переживают оба. поэтому у xray перезапуск: секунда простоя против полутора минут
    private suspend fun resetCoreConnections() {
        if (status != VpnRunStatus.RUNNING) return

        if (lastCoreKind == CORE_KIND_MIHOMO) {
            if (closeMihomoConnections()) {
                NativeLog.i("KEQDIS", "handover: mihomo connections closed via API")
            } else {
                // сорванный рестарт дороже медленной минуты
                NativeLog.w("KEQDIS", "handover: mihomo API did not answer, leaving connections as is")
            }
            return
        }

        restartCoreAfterHandover()
    }

    private suspend fun closeMihomoConnections(): Boolean = withContext(Dispatchers.IO) {
        val creds = mihomoApiCredentials() ?: return@withContext false
        val (port, secret) = creds
        runCatching {
            val conn = (URL("http://127.0.0.1:$port/connections").openConnection() as HttpURLConnection)
                .apply {
                    requestMethod = "DELETE"
                    setRequestProperty("Authorization", "Bearer $secret")
                    connectTimeout = 1500
                    readTimeout = 1500
                }
            try { conn.responseCode in 200..299 } finally { conn.disconnect() }
        }.getOrDefault(false)
    }

    // источник тот же, что у MainActivity.getMihomoApi, и единственный: сессию из плитки поднимает сервис
    private fun mihomoApiCredentials(): Pair<Int, String>? = runCatching {
        val path = lastXrayConfigPath ?: return@runCatching null
        val file = File(path)
        if (!file.isFile) return@runCatching null
        val json = org.json.JSONObject(file.readText(Charsets.UTF_8))
        val port = json.optString("external-controller").substringAfterLast(':', "").toIntOrNull() ?: 0
        val secret = json.optString("secret")
        if (port <= 0 || secret.isEmpty()) null else port to secret
    }.getOrNull()

    private suspend fun restartCoreAfterHandover() = opMutex.withLock {
        if (status != VpnRunStatus.RUNNING) return@withLock
        val config = lastXrayConfigPath ?: return@withLock
        val previousPid = xrayPid
        if (previousPid <= 0) return@withLock

        try {
            // обнулить до убийства: монитор сверяет pid с xrayPid и принял бы перезапуск за смерть ядра
            xrayPid = -1
            runCatching { android.os.Process.killProcess(previousPid) }
            withTimeoutOrNull(3000) {
                while (File("/proc/$previousPid").exists()) delay(100)
            }
            relaunchCore(config)
            NativeLog.i("KEQDIS", "handover: core restarted pid=$xrayPid")
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            // дальше сессия нежизнеспособна, ведём себя как монитор при падении ядра
            NativeLog.e("KEQDIS", "handover: core restart failed: ${e.message}", e)
            setStatus(VpnRunStatus.ERROR, "Core restart after network change failed")
            cleanup()
            cleanupDone = true
            withContext(Dispatchers.Main) { stopForeground(STOP_FOREGROUND_REMOVE) }
            showControlNotification("Error", isConnected = false, isTransitioning = false)
        }
    }

    // интерфейс не трогаем, иначе система покажет разрыв VPN. дескриптор жил в убитом процессе, новому ядру отдаём заново
    private suspend fun relaunchCore(config: String) {
        val port = activeSocksPort
        var waitedFree = 0
        while (isPortOpen("127.0.0.1", port) && waitedFree < 2000) {
            delay(100); waitedFree += 100
        }

        // без дескриптора ядро считает туннелем fd 0, свой stdin: порт слушается, подключено, а из туннеля не читает никто.
        // у mihomo номер уже в конфиге с injectTunFd, интерфейс прежний
        val isMihomo = lastCoreKind == CORE_KIND_MIHOMO
        val tunFd = tunInterface?.takeIf { isMihomo || xrayConfigHasTun(config) }?.fd ?: -1
        // лог не обнулялся, вердикт прошлого ядра в нём лежит, смотрим только новое
        val logFrom = File(filesDir, CORE_LOG_FILE).length()
        xrayPid = startXray(
            getBinaryPath(if (isMihomo) "libmihomo.so" else "libxray.so"),
            config,
            lastCoreKind,
            tunFd = tunFd,
            freshLog = false,
        )

        var waited = 0
        while (!isPortOpen("127.0.0.1", port) && waited < 10000) {
            delay(300); waited += 300
        }
        if (!isPortOpen("127.0.0.1", port)) {
            throw IllegalStateException("SOCKS5 port $port not ready after core restart")
        }
        if (isMihomo && tunFd >= 0) awaitMihomoTun(from = logFrom)
    }

    private fun buildTunInterface(exc: List<String>, inc: List<String>): ParcelFileDescriptor {
        val b = Builder()
            .setMtu(TUN_MTU)
            .addAddress(TUN_ADDRESS, TUN_PREFIX)
            .addRoute("0.0.0.0", 0)
            // пустышка из нашей /30, не публичный резолвер. с 8.8.8.8 Private DNS в режиме Автоматически находил DoT на 853,
            // а перехват ловит только 53, и весь системный DNS уходил мимо. здесь на 853 отвечать некому
            .addDnsServer(TUN_DNS_ADDRESS)
            .setSession("KEQDIS")
            .setBlocking(false)

        // без этого VPN с target 10+ считается лимитной сетью даже на домашнем Wi-Fi. false: признак берётся у сети под туннелем
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) b.setMetered(false)

        applyAppFilter(b, inc, exc)
        applyHuaweiUnderlying(b)
        applyHyperOsUnderlying(b)

        val tun = b.establish()
        if (tun == null) {
            NativeLog.e(
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


    // свой пакет мимо туннеля: ядро работает под нашим uid, без protect() его сокеты зациклились бы
    private fun applyAppFilter(b: Builder, inc: List<String>, exc: List<String>) {
        tunOnlySelected = false
        if (inc.isNotEmpty()) {
            // считаем добавленные: если невалидны все, establish() на Huawei/Honor возвращает null
            var addedInc = 0
            inc.forEach { pkg ->
                try {
                    b.addAllowedApplication(pkg)
                    addedInc++
                } catch (e: Exception) {
                    NativeLog.w("KEQDIS", "buildTun: addAllowedApplication skipped pkg=$pkg err=${e.message}")
                }
            }
            if (addedInc == 0) {
                NativeLog.w("KEQDIS", "buildTun: include list produced 0 valid apps, falling back to full tunnel")
                runCatching { b.addDisallowedApplication(packageName) }
            }
            tunOnlySelected = addedInc > 0
        } else {
            runCatching { b.addDisallowedApplication(packageName) }
            exc.forEach { pkg ->
                try {
                    b.addDisallowedApplication(pkg)
                } catch (e: Exception) {
                    NativeLog.w("KEQDIS", "buildTun: addDisallowedApplication skipped pkg=$pkg err=${e.message}")
                }
            }
        }
    }

    // Huawei/Honor: без setUnderlyingNetworks establish() со сплитом не работает
    private fun applyHuaweiUnderlying(b: Builder) {
        if (!needsExplicitUnderlying()) return
        val manufacturer = Build.MANUFACTURER.uppercase()
        try {
            val cm = getSystemService(android.net.ConnectivityManager::class.java)
            val activeNet = cm?.activeNetwork
            if (activeNet != null) {
                b.setUnderlyingNetworks(arrayOf(activeNet))
            } else {
                NativeLog.w("KEQDIS", "buildTun: activeNetwork is null on $manufacturer")
            }
        } catch (e: Exception) {
            NativeLog.w("KEQDIS", "buildTun: setUnderlyingNetworks failed on $manufacturer: ${e.message}")
        }
    }

    private fun needsExplicitUnderlying(): Boolean {
        val manufacturer = Build.MANUFACTURER.uppercase()
        return manufacturer == "HUAWEI" || manufacturer == "HONOR"
    }

    // везде, кроме Huawei/Honor и HyperOS, подложку не трогаем: наш вызов её только ломает, так туннель и стал подложкой себе.
    // где задали руками, обновляем руками, иначе первая сеть сессии залипает
    private fun applyHuaweiUnderlying(network: Network) {
        if (!needsExplicitUnderlying()) return
        if (tunInterface == null) return   // режим прокси: establish() не звался
        runCatching { setUnderlyingNetworks(arrayOf(network)) }
            .onFailure { NativeLog.w("KEQDIS", "handover: setUnderlyingNetworks failed: ${it.message}") }
    }

    // HyperOS 4, Xiaomi 17 Ultra (20.10.2026): без подложки исключённые из VPN приложения через пару минут виснут,
    // с ней работают, как в Incy. ro.mi.os.version.name OS2.0 и code 2 на POCO M6 Pro, code 4 на HyperOS 4; бренд Xiaomi бывает и с AOSP.
    // номер сборки OS2.0.201.0... на случай, если прошивка не даст прочитать свойства; getprop, а не скрытый SystemProperties
    private val hyperOsVersion: String? by lazy {
        val props = runCatching {
            val p = ProcessBuilder("sh", "-c", "getprop ro.mi.os.version.name; getprop ro.mi.os.version.code").start()
            val out = p.inputStream.bufferedReader().use { it.readText() }
            p.waitFor()
            out.lines().map { it.trim() }
        }.getOrDefault(emptyList())
        val name = props.getOrNull(0).orEmpty()
        val code = props.getOrNull(1).orEmpty()
        val build = Build.VERSION.INCREMENTAL.orEmpty()
        val xiaomi = listOf(Build.MANUFACTURER, Build.BRAND).any { it.orEmpty().lowercase() in setOf("xiaomi", "redmi", "poco") }
        when {
            name.isNotEmpty() -> "$name (name)"
            code.isNotEmpty() -> "code $code"
            xiaomi && Regex("^OS\\d").containsMatchIn(build) -> "$build (build)"
            else -> null
        }
    }
    @Volatile private var hyperOsUnderlyingCallback: ConnectivityManager.NetworkCallback? = null
    @Volatile private var hyperOsUnderlyingNet: Network? = null

    private fun isPhysicalInternet(caps: android.net.NetworkCapabilities) =
        caps.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
            caps.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_NOT_VPN) &&
            !caps.hasTransport(android.net.NetworkCapabilities.TRANSPORT_VPN)

    private fun applyHyperOsUnderlying(b: Builder) {
        val version = hyperOsVersion ?: return
        runCatching {
            val cm = getSystemService(ConnectivityManager::class.java)
            val net = cm?.activeNetwork?.takeIf { n ->
                cm.getNetworkCapabilities(n)?.let { isPhysicalInternet(it) } == true
            }
            hyperOsUnderlyingNet = net
            if (net != null) b.setUnderlyingNetworks(arrayOf(net))
            NativeLog.i("KEQDIS", "underlying: HyperOS $version, start on ${net ?: "system default"}")
        }.onFailure { NativeLog.w("KEQDIS", "underlying: HyperOS start failed: ${it.message}") }
    }

    // requestNetwork, а не registerNetworkCallback: приходит одна лучшая сеть, а не все живые подряд
    private fun startHyperOsUnderlyingWatch() {
        if (hyperOsVersion == null || tunInterface == null || hyperOsUnderlyingCallback != null) return
        val cm = getSystemService(ConnectivityManager::class.java) ?: return
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onCapabilitiesChanged(network: Network, caps: android.net.NetworkCapabilities) {
                if (!isPhysicalInternet(caps) || network == hyperOsUnderlyingNet) return
                hyperOsUnderlyingNet = network
                setHyperOsUnderlying(network)
            }

            override fun onLost(network: Network) {
                if (network != hyperOsUnderlyingNet) return
                hyperOsUnderlyingNet = null
                setHyperOsUnderlying(null)
            }
        }
        val request = android.net.NetworkRequest.Builder()
            .addCapability(android.net.NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(android.net.NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()
        runCatching { cm.requestNetwork(request, cb) }
            .onSuccess { hyperOsUnderlyingCallback = cb }
            .onFailure { NativeLog.w("KEQDIS", "underlying: requestNetwork failed: ${it.message}") }
    }

    private fun stopHyperOsUnderlyingWatch() {
        hyperOsUnderlyingCallback?.let { cb ->
            runCatching { getSystemService(ConnectivityManager::class.java)?.unregisterNetworkCallback(cb) }
        }
        hyperOsUnderlyingCallback = null
        hyperOsUnderlyingNet = null
    }

    // null отдаёт выбор системе. пустой массив значил бы, что у VPN нет сети вовсе
    private fun setHyperOsUnderlying(network: Network?) {
        if (tunInterface == null) return
        val applied = runCatching { setUnderlyingNetworks(network?.let { arrayOf(it) }) }.getOrDefault(false)
        NativeLog.i("KEQDIS", "underlying: $network, applied=$applied")
    }

    // для случая, когда ядро исчезло молча: убитый процесс прощания не пишет, а logcat на Android 13+ приложению закрыт.
    // метка времени как у core_log_line в forkexec.c, файл там открыт с O_APPEND, дописывать параллельно можно

    private fun appendCoreLog(vararg lines: String) {
        runCatching {
            val stamp = java.text.SimpleDateFormat("MM-dd HH:mm:ss ", java.util.Locale.US)
                .format(java.util.Date())
            File(filesDir, CORE_LOG_FILE)
                .appendText(lines.joinToString("") { "$stamp[keqdis] $it\n" })
        }
    }

    // port not ready ничего не говорит, ядро обычно уже вышло с жалобой на конфиг. длина ограничена: строка едет в уведомление
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

    // файл обнуляется по размеру: если он стал короче метки, новое в нём всё
    private fun coreLogSince(file: File, from: Long): String {
        val bytes = file.readBytes()
        val start = if (from in 0..bytes.size.toLong()) from.toInt() else 0
        return String(bytes, start, bytes.size - start, Charsets.UTF_8)
    }

    // смотрим лог на оба исхода: ошибка ценна, причина в ней уже названа.
    // вышедшее время не отказ: значит, ядро пишет лог мимо нас
    private suspend fun awaitMihomoTun(timeoutMs: Int = 4000, from: Long = 0L) {
        val file = File(filesDir, CORE_LOG_FILE)
        var waited = 0
        while (waited < timeoutMs) {
            val log = runCatching { coreLogSince(file, from) }.getOrDefault("")
            val failure = log.lineSequence().lastOrNull { it.contains(MIHOMO_TUN_FAILED) }
            if (failure != null) {
                throw IllegalStateException(
                    "mihomo did not take over the tunnel: " +
                        failure.substringAfter(MIHOMO_TUN_FAILED).trim().take(300)
                )
            }
            if (NativeHelper.tunReadyCount() > tunReadyFrom || log.contains(MIHOMO_TUN_READY)) {
                NativeLog.i("KEQDIS", "mihomo tun adapter is up")
                return
            }
            delay(100); waited += 100
        }
        NativeLog.i("KEQDIS", "mihomo tun: no verdict in the log, continuing")
    }

    private fun xrayConfigHasTun(configPath: String): Boolean = runCatching {
        val inbounds = org.json.JSONObject(File(configPath).readText())
            .optJSONArray("inbounds") ?: return false
        for (i in 0 until inbounds.length()) {
            if (inbounds.optJSONObject(i)?.optString("protocol") == "tun") return true
        }
        false
    }.getOrElse {
        NativeLog.w("KEQDIS", "xrayConfigHasTun: ${it.message}")
        false
    }

    // MTU fd-устройства ядру спросить неоткуда, а расхождение с интерфейсом это пакеты, которые ядро ОС отбросит при записи в tun
    private fun injectXrayTunMtu(configPath: String) {
        val file = File(configPath)
        val root = org.json.JSONObject(file.readText())
        val inbounds = root.optJSONArray("inbounds")
            ?: throw IllegalStateException("xray config has no inbounds")
        for (i in 0 until inbounds.length()) {
            val inbound = inbounds.optJSONObject(i) ?: continue
            if (inbound.optString("protocol") != "tun") continue
            val settings = inbound.optJSONObject("settings") ?: org.json.JSONObject()
            settings.put("mtu", TUN_MTU)
            inbound.put("settings", settings)
            file.writeText(root.toString())
            NativeLog.i("KEQDIS", "xray tun: mtu=$TUN_MTU")
            return
        }
        throw IllegalStateException("xray config has no tun inbound")
    }
    // дескриптор и MTU знает только сервис, копия в Dart была бы вторым источником для числа, которое обязано совпасть.
    // переписываем на месте: экран Соединения и плитка читают API из этого же файла
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
        NativeLog.i("KEQDIS", "mihomo tun: fd=$tunFd mtu=$TUN_MTU")
    }

    // JSONStringer экранирует слэш, а такого escape go-yaml не знает (scannerc.go): yaml: found unknown escape character.
    // слэши есть в любом конфиге, поэтому ломался любой. \\ копируем парой, чтобы следующий слэш не сошёл за экранированный
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

    // система вправе убить ядро, не трогая сервис: с Android 12 дочерние процессы ищутся по cgroup.
    // интерфейс при этом цел, поэтому ядро поднимаем на нём, и приложения видят секунду тишины, а не разрыв VPN
    private suspend fun reviveCore(deadPid: Int): Boolean {
        val config = lastXrayConfigPath ?: return false
        val lived = android.os.SystemClock.elapsedRealtime() - coreStartedAt
        quickCoreDeaths = if (lived < CORE_QUICK_DEATH_MS) quickCoreDeaths + 1 else 0
        if (quickCoreDeaths >= CORE_MAX_QUICK_DEATHS) {
            appendCoreLog("the core keeps dying right after start, closing the session")
            return false
        }
        return try {
            relaunchCore(config)
            appendCoreLog("started the core again on the same tunnel, pid $xrayPid")
            NativeLog.i("KEQDIS", "[xray] pid=$deadPid revived as pid=$xrayPid")
            true
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            NativeLog.e("KEQDIS", "[xray] revive of pid=$deadPid failed: ${e.message}", e)
            appendCoreLog("could not start the core again: ${e.message}")
            false
        }
    }

    // до info ради счётчика отказов. копия рядом: плитка и оживление стартуют с исходного файла,
    // и поднятый уровень выдал бы себя за выбор человека
    private fun sessionConfigFor(config: String, coreKind: String): String {
        if (coreKind == CORE_KIND_MIHOMO) return raiseMihomoLogLevel(config)
        val levels = listOf("debug", "info", "warning", "error", "none")
        val info = levels.indexOf("info")
        if (coreKind != CORE_KIND_XRAY) {
            NativeHelper.setCoreLogLevel(0)
            return config
        }
        return try {
            val source = File(config)
            val json = org.json.JSONObject(source.readText())
            val log = json.optJSONObject("log") ?: org.json.JSONObject().also { json.put("log", it) }
            // без поля xray пишет с warning
            val chosen = levels.indexOf(log.optString("loglevel", "warning").lowercase())
                .let { if (it < 0) levels.indexOf("warning") else it }
            if (chosen <= info) {
                NativeHelper.setCoreLogLevel(0)
                return config
            }
            log.put("loglevel", "info")
            val run = File(source.parentFile, "xray_session_run.json")
            run.writeText(json.toString())
            NativeHelper.setCoreLogLevel(chosen)
            run.absolutePath
        } catch (e: Exception) {
            // не разобрали: как есть, без счётчика отказов
            NativeLog.w("KEQDIS", "session log level left as is: ${e.message}")
            NativeHelper.setCoreLogLevel(0)
            config
        }
    }

    // mihomo строку TUN поднялся пишет на info, и при warning подключение ждало её четыре секунды. без поля он и так на info
    private fun raiseMihomoLogLevel(config: String): String {
        val levels = listOf("debug", "info", "warning", "error", "silent")
        return try {
            val source = File(config)
            val text = source.readText()
            val value = (Regex(""""log-level"\s*:\s*"(\w+)"""").find(text)
                ?: Regex("""(?m)^log-level:\s*['"]?(\w+)""").find(text))
                ?.groups?.get(1)
            val chosen = levels.indexOf(value?.value?.lowercase())
            if (value == null || chosen <= levels.indexOf("info")) {
                NativeHelper.setCoreLogLevel(0)
                return config
            }
            val run = File(source.parentFile, "mihomo_session_run.yaml")
            run.writeText(text.replaceRange(value.range, "info"))
            NativeHelper.setCoreLogLevel(chosen)
            run.absolutePath
        } catch (e: Exception) {
            NativeLog.w("KEQDIS", "session log level left as is: ${e.message}")
            NativeHelper.setCoreLogLevel(0)
            config
        }
    }

    // вердикт ищем только среди того, что написало текущее ядро
    private var tunReadyFrom = 0L

    private fun startXray(
        binary: String,
        config: String,
        coreKind: String = CORE_KIND_XRAY,
        tunFd: Int = -1,
        freshLog: Boolean = true,
    ): Int {
        // -1 нет бинаря, -2 нет конфига, -4 умер сразу
        XrayGeoAssets.ensure(this, filesDir)
        // свежий лог на каждую сессию. перезапуск внутри сессии его не трогает: строки до него объясняют, зачем он был
        if (freshLog) runCatching { File(filesDir, CORE_LOG_FILE).writeText("") }
        tunReadyFrom = NativeHelper.tunReadyCount()
        val owner = if (tunFd >= 0) {
            ownerServer ?: runCatching { ConnectionOwnerServer(this) }
                .onFailure { NativeLog.w("KEQDIS", "owner socket not started: ${it.message}") }
                .getOrNull()
                ?.also { ownerServer = it }
        } else {
            null
        }
        owner?.systemOutsideVpn = tunOnlySelected
        val pid = NativeHelper.startCore(
            binary, sessionConfigFor(config, coreKind), filesDir.absolutePath,
            CORE_LOG_FILE, coreKind, tunFd, owner?.name ?: "",
        )
        when {
            pid == -1 -> throw IllegalStateException("Xray binary not found: $binary")
            pid == -2 -> throw IllegalStateException("Xray config not found: $config")
            // логом, а не отсылкой к logcat: его на Android 13+ не прочесть
            pid == -4 -> throw IllegalStateException(
                "${if (coreKind == CORE_KIND_MIHOMO) "mihomo" else "Xray"} " +
                    "exited on startup${coreLogTail()}"
            )
            pid <= 0  -> throw IllegalStateException("fork() for Xray failed (pid=$pid)")
            else -> {}
        }
        NativeLog.i("KEQDIS", "Xray started pid=$pid")
        coreStartedAt = android.os.SystemClock.elapsedRealtime()

        val monitorPid = pid
        serviceScope.launch(Dispatchers.IO) {
            try {
                while (File("/proc/$pid").exists()) delay(500)
                NativeLog.w("KEQDIS", "[xray] pid=$pid exited")
                opMutex.withLock {
                    if ((status == VpnRunStatus.RUNNING || status == VpnRunStatus.STARTING) &&
                        monitorPid == xrayPid) {
                        appendCoreLog(
                            "core process $pid is gone, and the app did not stop it",
                            CORE_GONE_HINT,
                        )
                        xrayPid = -1  // уже мёртв, повторно в cleanup() не убиваем
                        if (status == VpnRunStatus.RUNNING && reviveCore(pid)) return@withLock
                        NativeLog.w("KEQDIS", "[xray] triggering full cleanup after unexpected exit")
                        setStatus(VpnRunStatus.ERROR, "Xray exited unexpectedly")
                        cleanup()
                        cleanupDone = true
                        withContext(Dispatchers.Main) { stopForeground(STOP_FOREGROUND_REMOVE) }
                        unregisterNotificationReceiver()
                        // без stopSelf(): сервис в ERROR переиспользуется следующим стартом из плитки
                    }
                }
            } catch (_: Exception) {}
        }
        return pid
    }

    private fun startStatsLoop() {
        serviceScope.launch {
            val uid = android.os.Process.myUid()
            var prevRx = android.net.TrafficStats.getUidRxBytes(uid).coerceAtLeast(0)
            var prevTx = android.net.TrafficStats.getUidTxBytes(uid).coerceAtLeast(0)
            var tick = 0
            val pm = getSystemService(POWER_SERVICE) as android.os.PowerManager

            while (status == VpnRunStatus.RUNNING || status == VpnRunStatus.STARTING) {
                delay(1000)
                // пятая секунда как отправная точка, дальше раз в десять минут
                if (tick % MEMORY_SNAPSHOT_TICKS == 5) logMemory()
                val rx = android.net.TrafficStats.getUidRxBytes(uid).coerceAtLeast(0)
                val tx = android.net.TrafficStats.getUidTxBytes(uid).coerceAtLeast(0)

                val deltaRx = if (rx >= prevRx) rx - prevRx else 0L
                val deltaTx = if (tx >= prevTx) tx - prevTx else 0L

                downloadTotal.addAndGet(deltaRx)
                uploadTotal.addAndGet(deltaTx)
                downloadSpeed.set(deltaRx)
                uploadSpeed.set(deltaTx)

                prevRx = rx; prevTx = tx

                // Dart-уведомление со скоростями живёт, пока жив Flutter, а это всегда: без обновлений застывало на Connected.
                // при погашенном экране не обновляем, 30 IPC в минуту всю ночь ни к чему
                tick++
                if (status == VpnRunStatus.RUNNING && tick % 2 == 0 && pm.isInteractive) {
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

    private var lastMemoryPss = 0L
    private var nextMemoryThreshold = 1024L * 1024 * 1024

    // процесс уже разрастался до 2,3 ГБ при VPN, и чем, без чисел по времени не понять. ядро живёт своим процессом и в PSS не входит
    private fun logMemory() {
        runCatching {
            val info = android.os.Debug.MemoryInfo().also { android.os.Debug.getMemoryInfo(it) }
            val total = info.totalPss * 1024L
            val graphics = info.getMemoryStat("summary.graphics")?.toLongOrNull()?.times(1024)
            val threads = procStatusValue("self", "Threads")
            val files = File("/proc/self/fd").list()?.size
            val core = xrayPid.takeIf { it > 0 }?.let { procStatusValue("$it", "VmRSS") }
            val line = "memory: pss ${mb(total)} (java ${mb(info.dalvikPss * 1024L)}, " +
                "native ${mb(info.nativePss * 1024L)}" +
                (graphics?.let { ", graphics ${mb(it)}" } ?: "") +
                "), threads ${threads ?: "?"}, open files ${files ?: "?"}, " +
                "core ${core?.let { mb(it * 1024) } ?: "not running"}"

            val alarms = ArrayList<String>(2)
            if (total >= nextMemoryThreshold) {
                while (total >= nextMemoryThreshold) nextMemoryThreshold *= 2
                alarms.add("now above ${mb(nextMemoryThreshold / 2)}")
            }
            if (lastMemoryPss > 0 && total - lastMemoryPss >= MEMORY_GROWTH_ALARM) {
                alarms.add("grew by ${mb(total - lastMemoryPss)} since last time")
            }
            lastMemoryPss = total
            if (alarms.isEmpty()) NativeLog.i("KEQDIS", line)
            else NativeLog.w("KEQDIS", "$line; ${alarms.joinToString(", ")}")
        }.onFailure { NativeLog.d("KEQDIS", "memory snapshot failed: ${it.message}") }
    }

    // у VmRSS килобайты, у Threads штуки
    private fun procStatusValue(pid: String, key: String): Long? = runCatching {
        File("/proc/$pid/status").useLines { lines ->
            lines.firstOrNull { it.startsWith("$key:") }
                ?.substringAfter(':')?.trim()?.substringBefore(' ')?.toLongOrNull()
        }
    }.getOrNull()

    private fun mb(bytes: Long): String = "${bytes / (1024 * 1024)} MB"

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

    // читаем прямо из FlutterSharedPreferences (JSON AppSettings под flutter.): так работает любой путь старта без extra в Intent
    private data class NotifBodyPrefs(val showUptime: Boolean, val showSpeed: Boolean)

    // подробный лог пишет строку на каждое соединение, держать его всегда незачем
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

    private fun getBinaryPath(name: String): String {
        // исполнять можно только из nativeLibraryDir (apk_data_file), в filesDir и codeCacheDir execv на Android 10+ запрещён SELinux
        val bin = File(applicationInfo.nativeLibraryDir, name)
        if (!bin.exists()) throw IllegalStateException("$name not found in ${applicationInfo.nativeLibraryDir}")
        NativeLog.i("KEQDIS", "Using binary: ${bin.absolutePath}")
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
        liveStatus = statusStr
        ProcessExits.noteVpnStatus(this, statusStr)
        // оборвавшуюся ошибкой после смерти процесса не поднимаем: ошибка вернулась бы с ней, и перезапуски пошли бы по кругу
        if (s == VpnRunStatus.ERROR) rememberSessionWanted(false)

        if (s == VpnRunStatus.STOPPED || s == VpnRunStatus.RUNNING || s == VpnRunStatus.ERROR) {
            NativeLog.i("KEQDIS_QS", "setStatus: $s → statusStr=$statusStr")
        }

        runCatching {
            getSharedPreferences(PREFS_QS, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_QS_STATUS, statusStr)
                .putString(KEY_QS_ERROR, e)
                .apply()
        }

        // ContentObserver надёжнее requestListeningState(): тот работает, только пока открыта шторка
        runCatching {
            contentResolver.notifyChange(VpnStatusProvider.STATUS_URI, null)
        }.onFailure { e ->
            NativeLog.w("KEQDIS", "notifyChange failed: ${e.message}")
        }

        statusListener?.invoke(statusStr, e)

        runCatching {
            sendBroadcast(Intent().apply {
                action = BROADCAST_VPN_STATUS_CHANGED
                putExtra("status", statusStr)
                setPackage(packageName)
            })
        }.onFailure { ex ->
            NativeLog.w("KEQDIS", "broadcastStatusChange failed: ${ex.message}")
        }
    }

    private fun buildControlNotification(
        text: String,
        isConnected: Boolean,
        isTransitioning: Boolean
    ): Notification {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        // каналов до Android 8 нет, и вызов ронял службу на первом же уведомлении
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            nm.getNotificationChannel(CHANNEL_ID_CONTROL) == null
        ) {
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

        val contentIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        // в заголовке только сервер: статус во второй строке, и VPN Connected над Connected его дублировал
        val title = currentServerName?.takeIf { it.isNotBlank() } ?: "VPN"

        val builder = NotificationCompat.Builder(this, CHANNEL_ID_CONTROL)
            .setContentTitle(title)
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

        if (!isTransitioning) {
            if (isConnected) {
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
                val connectIntent = if (
                    !lastXrayConfigPath.isNullOrBlank() &&
                    socksUsername.isNotBlank() &&
                    socksPassword.isNotBlank()
                ) {
                    Intent(this, KeqdisVpnService::class.java).apply {
                        action = ACTION_START
                        // тем же ядром: конфиг на диске написан под него
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
                if (intent?.action != BROADCAST_ACTION_DISCONNECT) return
                NativeLog.i("KEQDIS", "[notification] Disconnect pressed")
                serviceScope.launch { stopVpn() }
            }
        }

        // до Android 13 флаг понимает только ContextCompat, иначе отключить VPN могло любое приложение
        ContextCompat.registerReceiver(
            this,
            notificationActionReceiver,
            IntentFilter(BROADCAST_ACTION_DISCONNECT),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
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
