package com.keqdroid.keqdroid

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.ServiceConnection
import android.database.ContentObserver
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.net.VpnService
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.widget.Toast
import androidx.core.content.ContextCompat

class VpnQuickTileService : TileService() {

    companion object {
        // глиф строки состояния: плитка тонирует иконку, цветной логотип там белый кружок, а ic_launcher_monochrome с полями адаптивной иконки мелкий.
        // тот же ресурс в манифесте для редактора плиток
        private val TILE_ICON_RES = R.drawable.ic_notification

        // connecting не случайно: плитка на нём нажимается, см. updateTileFromPrefs
        private val ACTIVE_STATUSES = setOf("connected", "running", "connecting", "starting")
    }

    private val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(selfChange: Boolean) {
            updateTileFromPrefs()
        }
    }

    private var retryHandler: Handler? = null
    private val retryRunnable = Runnable { updateTileFromPrefs() }
    private val RETRY_DELAY_MS = 500L
    private var retryCount = 0
    private val MAX_RETRIES = 10

    private val statusReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == KeqdisVpnService.BROADCAST_VPN_STATUS_CHANGED) {
                updateTileFromPrefs()
            }
        }
    }

    // если процесс убили с VPN, в prefs навсегда остаётся connecting. BIND_AUTO_CREATE создаёт сервис, и его onCreate() чинит prefs
    private var healConnection: ServiceConnection? = null

    private fun healStaleStatusViaBind() {
        if (healConnection != null) return
        val status = getSharedPreferences(KeqdisVpnService.PREFS_QS, MODE_PRIVATE)
            .getString(KeqdisVpnService.KEY_QS_STATUS, "disconnected")
            ?.lowercase()
            ?: "disconnected"
        if (status == "disconnected" || status == "error") return
        val conn = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName?, service: IBinder?) {}
            override fun onServiceDisconnected(name: ComponentName?) {}
        }
        healConnection = try {
            if (bindService(
                    Intent(this, KeqdisVpnService::class.java),
                    conn,
                    Context.BIND_AUTO_CREATE,
                )
            ) conn else null
        } catch (e: Exception) {
            NativeLog.w("KEQDIS_QS", "heal bind failed: ${e.message}")
            null
        }
    }

    private fun releaseHealBind() {
        healConnection?.let { runCatching { unbindService(it) } }
        healConnection = null
    }

    override fun onStartListening() {
        super.onStartListening()
        try {
            contentResolver.registerContentObserver(
                VpnStatusProvider.STATUS_URI,
                false,
                observer
            )
        } catch (e: Exception) {
            NativeLog.e("KEQDIS", "Failed to register content observer: ${e.message}")
        }

        try {
            // до Android 13 без ContextCompat плитке мог прислать статус кто угодно
            ContextCompat.registerReceiver(
                this,
                statusReceiver,
                IntentFilter(KeqdisVpnService.BROADCAST_VPN_STATUS_CHANGED),
                ContextCompat.RECEIVER_NOT_EXPORTED,
            )
        } catch (e: Exception) {
            NativeLog.e("KEQDIS", "Failed to register broadcast receiver: ${e.message}")
        }

        retryCount = 0
        healStaleStatusViaBind()
        updateTileFromPrefs()
    }

    override fun onStopListening() {
        super.onStopListening()
        retryHandler?.removeCallbacks(retryRunnable)
        retryHandler = null
        retryCount = 0
        releaseHealBind()
        try {
            contentResolver.unregisterContentObserver(observer)
        } catch (_: Exception) {}
        try {
            unregisterReceiver(statusReceiver)
        } catch (_: Exception) {}
    }

    override fun onClick() {
        super.onClick()
        // исключение из onClick система гасит молча, плитка просто дёргается. поэтому ни один шаг не падает наружу
        runCatching { handleClick() }.onFailure { t ->
            NativeLog.e("KEQDIS_QS", "onClick failed: $t", t)
            toast(R.string.tile_error_start)
        }
    }

    private fun handleClick() {
        val prefs = getSharedPreferences(KeqdisVpnService.PREFS_QS, MODE_PRIVATE)
        val status = (prefs.getString(KeqdisVpnService.KEY_QS_STATUS, "disconnected")
            ?: "disconnected").lowercase()
        NativeLog.i("KEQDIS_QS", "onClick: status=$status")

        // запись в prefs переживает смерть процесса, туннель нет: на MIUI в qs_status оставался connected,
        // и плитка слала стоп в мёртвый сервис. liveStatus после перезапуска disconnected, расхождение значит запись протухла
        val live = KeqdisVpnService.liveStatus.lowercase()
        if (status in ACTIVE_STATUSES && live !in ACTIVE_STATUSES) {
            NativeLog.w(
                "KEQDIS_QS",
                "onClick: stale persisted status '$status' (live='$live') → healing and connecting",
            )
            getSharedPreferences(KeqdisVpnService.PREFS_QS, MODE_PRIVATE)
                .edit()
                .putString(KeqdisVpnService.KEY_QS_STATUS, "disconnected")
                .apply()
        } else if (status in ACTIVE_STATUSES) {
            // работает или залип на connecting: глушим напрямую, без toggle
            startService(Intent(this, KeqdisVpnService::class.java).apply {
                action = KeqdisVpnService.ACTION_STOP
            })
            return
        }

        val start = KeqdisVpnService.snapshotStartIntent(this)
        if (start == null) {
            NativeLog.i("KEQDIS_QS", "onClick: no usable server snapshot → opening app")
            openAppForConnect()
            return
        }

        // согласие спрашивает только окно, невидимое окно спросит и само подключит
        if (KeqdisVpnService.startsTunnel(start) && VpnService.prepare(this) != null) {
            NativeLog.i("KEQDIS_QS", "onClick: no VPN consent → quick connect window")
            openQuickConnect()
            return
        }
        if (directStartBlocked()) {
            NativeLog.i("KEQDIS_QS", "onClick: this firmware blocks the tile → quick connect window")
            openQuickConnect()
            return
        }

        try {
            if (Build.VERSION.SDK_INT >= 26) startForegroundService(start) else startService(start)
        } catch (e: Exception) {
            // Android 12+: фоновый старт отняли (ограничение фоновой активности, выключенный автозапуск). из окна старт разрешён всегда
            NativeLog.e("KEQDIS_QS", "onClick: service start refused by system: $e")
            rememberDirectStartBlocked()
            openQuickConnect()
            return
        }
        verifyStarted()
    }

    // отказ бывает без исключения: прошивки с Автозапуском старт молча глотают. сверяемся с liveStatus, его ставят прямо в onStartCommand,
    // а рабочий статус за opMutex путал бы застрявший стоп с запретом системы.
    // меньше секунды не хватает здоровому старту, больше рискует закрытой шторкой
    private fun verifyStarted() {
        android.os.Handler(mainLooper).postDelayed({
            val live = KeqdisVpnService.liveStatus.lowercase()
            if (live !in ACTIVE_STATUSES) {
                NativeLog.e(
                    "KEQDIS_QS",
                    "onClick: service did not come up (live='$live') — likely blocked by the OEM",
                )
                rememberDirectStartBlocked()
                openQuickConnect(retryHelps = true)
            }
        }, 2500)
    }

    // запомненный отказ ведёт сразу в окно, без 2,5 с ожидания. помним до обновления системы
    private fun directStartBlocked(): Boolean =
        getSharedPreferences(KeqdisVpnService.PREFS_QS, MODE_PRIVATE)
            .getString(KeqdisVpnService.KEY_QS_DIRECT_START_BLOCKED_ON, null) == Build.FINGERPRINT

    private fun rememberDirectStartBlocked() {
        getSharedPreferences(KeqdisVpnService.PREFS_QS, MODE_PRIVATE)
            .edit()
            .putString(KeqdisVpnService.KEY_QS_DIRECT_START_BLOCKED_ON, Build.FINGERPRINT)
            .apply()
    }

    // окно из шторки открывается, только пока она открыта: на Android 14+ SystemUI без жетона нажатия пропускает запуск молча
    private fun openQuickConnect(retryHelps: Boolean = false) {
        val intent = Intent(this, QuickConnectActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION)
        launchActivity(intent) { launchedAt ->
            android.os.Handler(mainLooper).postDelayed({
                if (QuickConnectActivity.openedAt >= launchedAt) return@postDelayed
                if (KeqdisVpnService.liveStatus.lowercase() in ACTIVE_STATUSES) return@postDelayed
                NativeLog.w("KEQDIS_QS", "quick connect window did not open")
                toast(if (retryHelps) R.string.tile_error_blocked else R.string.tile_error_open_app)
            }, 2000)
        }
    }

    private fun openAppForConnect() {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ?.putExtra("action", "connect_from_notification")
            ?: Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                putExtra("action", "connect_from_notification")
            }
        launchActivity(launchIntent)
    }

    private fun launchActivity(launchIntent: Intent, onLaunched: ((Long) -> Unit)? = null) {
        val open = Runnable {
            val launchedAt = android.os.SystemClock.elapsedRealtime()
            try {
                if (Build.VERSION.SDK_INT >= 34) {
                    // Android 14+: startActivityAndCollapse(Intent) запрещён, только PendingIntent
                    val pendingIntent = PendingIntent.getActivity(
                        this,
                        0,
                        launchIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    startActivityAndCollapse(pendingIntent)
                } else {
                    @Suppress("DEPRECATION", "StartActivityAndCollapseDeprecated")
                    startActivityAndCollapse(launchIntent)
                }
            } catch (e: Exception) {
                // MIUI и родня режут запуск из шторки: пробуем напрямую, иначе говорим вслух
                NativeLog.e("KEQDIS_QS", "startActivityAndCollapse failed: $e")
                runCatching { startActivity(launchIntent) }.onFailure {
                    NativeLog.e("KEQDIS_QS", "startActivity fallback failed: $it")
                    toast(R.string.tile_error_open_app)
                    return@Runnable
                }
            }
            onLaunched?.invoke(launchedAt)
        }

        // на заблокированном экране активность не покажется, сперва снять блокировку
        if (isLocked) unlockAndRun(open) else open.run()
    }

    private fun toast(resId: Int) {
        runCatching { Toast.makeText(this, resId, Toast.LENGTH_LONG).show() }
    }

    private fun updateTileFromPrefs() {
        val persisted = getSharedPreferences(KeqdisVpnService.PREFS_QS, MODE_PRIVATE)
            .getString(KeqdisVpnService.KEY_QS_STATUS, "disconnected")
            ?.lowercase()
            ?: "disconnected"

        // та же сверка, что в handleClick, иначе плитка горит включённой при выключенном VPN
        val live = KeqdisVpnService.liveStatus.lowercase()
        val status = if (persisted in ACTIVE_STATUSES && live !in ACTIVE_STATUSES) {
            "disconnected"
        } else {
            persisted
        }

        NativeLog.d(
            "KEQDIS_QS",
            "updateTileFromPrefs: status=$status (persisted=$persisted, live=$live)",
        )

        val tileObj = qsTile
        if (tileObj == null) {
            if (retryCount < MAX_RETRIES) {
                NativeLog.d("KEQDIS_QS", "updateTileFromPrefs: qsTile is null, scheduling retry (${retryCount + 1}/$MAX_RETRIES)")
                retryHandler?.removeCallbacks(retryRunnable)
                retryHandler = Handler(Looper.getMainLooper())
                retryHandler?.postDelayed(retryRunnable, RETRY_DELAY_MS)
                retryCount++
            } else {
                NativeLog.w("KEQDIS_QS", "updateTileFromPrefs: max retries reached, giving up")
                retryCount = 0
            }
            return
        }

        retryCount = 0
        retryHandler?.removeCallbacks(retryRunnable)

        tileObj.label = "Keqdis"
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tileObj.icon = android.graphics.drawable.Icon.createWithResource(this, TILE_ICON_RES)
        }
        
        // нажатие по STATE_UNAVAILABLE система не доставляет, и умерший посреди коннекта процесс оставлял плитку мёртвой.
        // клик на connecting останавливает
        val connecting = status == "connecting" || status == "starting"
        tileObj.state = when {
            status == "connected" || status == "running" || connecting -> Tile.STATE_ACTIVE
            else -> Tile.STATE_INACTIVE
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tileObj.subtitle = if (connecting) getString(R.string.tile_connecting) else null
        }
        NativeLog.d("KEQDIS_QS", "updateTileFromPrefs: new tile.state=${tileObj.state}")
        tileObj.updateTile()
    }
}
