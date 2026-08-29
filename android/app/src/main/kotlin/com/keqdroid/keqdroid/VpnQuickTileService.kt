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

class VpnQuickTileService : TileService() {

    companion object {
        // Монохромный вектор (силуэт на прозрачном фоне): QS-плитки тинтуют иконку,
        // и полноцветный ic_launcher_foreground превращается в белый кружок.
        // Тот же ресурс стоит в android:icon сервиса в манифесте, чтобы и в редакторе
        // плиток (где берётся манифестная иконка) показывался логотип, а не пустой круг.
        private val TILE_ICON_RES = R.drawable.ic_launcher_monochrome

        // Статусы, при которых нажатие означает «выключить». connecting здесь не
        // случайно: см. updateTileFromPrefs — плитка на нём остаётся нажимаемой.
        private val ACTIVE_STATUSES = setOf("connected", "running", "connecting", "starting")
    }

    private val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(selfChange: Boolean) {
            updateTileFromPrefs()
        }
    }

    // Retry mechanism for cases when qsTile is not yet available
    private var retryHandler: Handler? = null
    private val retryRunnable = Runnable { updateTileFromPrefs() }
    private val RETRY_DELAY_MS = 500L
    private var retryCount = 0
    private val MAX_RETRIES = 10

    // BroadcastReceiver for status updates from service
    private val statusReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == KeqdisVpnService.BROADCAST_VPN_STATUS_CHANGED) {
                updateTileFromPrefs()
            }
        }
    }

    // Короткая привязка к KeqdisVpnService, пока пользователь смотрит шторку.
    // Если процесс убили с активным VPN, в prefs остаётся connecting/connected,
    // и тайл висел бы так вечно (connecting → STATE_UNAVAILABLE даже не нажать).
    // BIND_AUTO_CREATE создаёт свежий инстанс сервиса, его onCreate() сверяет
    // prefs с реальным статусом и чинит их → ContentObserver обновит тайл.
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
            android.util.Log.w("KEQDIS_QS", "heal bind failed: ${e.message}")
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
            android.util.Log.e("KEQDIS", "Failed to register content observer: ${e.message}")
        }

        try {
            val filter = IntentFilter(KeqdisVpnService.BROADCAST_VPN_STATUS_CHANGED)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(statusReceiver, filter, RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(statusReceiver, filter)
            }
        } catch (e: Exception) {
            android.util.Log.e("KEQDIS", "Failed to register broadcast receiver: ${e.message}")
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
        // onClick исполняется в фоновом процессе: вылетевшее отсюда исключение
        // система гасит молча, без диалога и без следа на экране — для человека
        // плитка просто «дёргается и не включается». Поэтому ни один шаг ниже не
        // имеет права падать наружу, и каждая ветка пишется в лог.
        runCatching { handleClick() }.onFailure { t ->
            android.util.Log.e("KEQDIS_QS", "onClick failed: $t", t)
            toast(R.string.tile_error_start)
        }
    }

    private fun handleClick() {
        val prefs = getSharedPreferences(KeqdisVpnService.PREFS_QS, MODE_PRIVATE)
        val status = (prefs.getString(KeqdisVpnService.KEY_QS_STATUS, "disconnected")
            ?: "disconnected").lowercase()
        android.util.Log.d("KEQDIS_QS", "onClick: status=$status")

        // Работает (или залип на connecting) — глушим напрямую, без toggle.
        if (status in ACTIVE_STATUSES) {
            startService(Intent(this, KeqdisVpnService::class.java).apply {
                action = KeqdisVpnService.ACTION_STOP
            })
            return
        }

        // Согласие на VPN спрашивает только Activity (VpnService.prepare отдаёт
        // интент, который обязан идти через startActivityForResult) — из шторки
        // подключиться физически нельзя, открываем приложение.
        if (VpnService.prepare(this) != null) {
            android.util.Log.i("KEQDIS_QS", "onClick: no VPN consent → opening app")
            openAppForConnect()
            return
        }

        val backend = prefs.getString(KeqdisVpnService.KEY_QS_LAST_BACKEND, KeqdisVpnService.VPN_BACKEND_XRAY)
            ?: KeqdisVpnService.VPN_BACKEND_XRAY
        // На Android движок всегда chain (libxray) — keqrnel вырезан. Передаём
        // его явно, чтобы и сохранённый из старых версий engine=keqrnel не всплыл.
        val coreEngine = KeqdisVpnService.CORE_ENGINE_CHAIN

        // AmneziaWG не хранит snapshot для быстрого реконнекта из плитки — открываем приложение.
        if (backend == KeqdisVpnService.VPN_BACKEND_AWG) {
            android.util.Log.i("KEQDIS_QS", "onClick: backend=awg has no snapshot → opening app")
            openAppForConnect()
            return
        }
        val xrayPath = prefs.getString(KeqdisVpnService.KEY_QS_LAST_XRAY_CONFIG, null)
        val user = prefs.getString(KeqdisVpnService.KEY_QS_LAST_SOCKS_USERNAME, null)
        val pass = prefs.getString(KeqdisVpnService.KEY_QS_LAST_SOCKS_PASSWORD, null)
        val port = prefs.getInt(KeqdisVpnService.KEY_QS_LAST_SOCKS_PORT, 2080)
        val serverName = prefs.getString(KeqdisVpnService.KEY_QS_LAST_SERVER_NAME, null)
        val exc = prefs.getStringSet(KeqdisVpnService.KEY_QS_LAST_EXCLUDE_PACKAGES, emptySet())?.toList() ?: emptyList()
        val inc = prefs.getStringSet(KeqdisVpnService.KEY_QS_LAST_INCLUDE_PACKAGES, emptySet())?.toList() ?: emptyList()

        // Снапшот пишет только сам сервис при старте: пока человек ни разу не
        // подключился из приложения, плитке нечем подключаться. Сам файл конфига
        // тоже проверяем — после очистки данных путь в prefs переживает файл, и
        // старт был бы обречён (ядро не поднимется, «Connecting…» → ошибка).
        if (xrayPath.isNullOrBlank() || user.isNullOrBlank() || pass.isNullOrBlank() ||
            !java.io.File(xrayPath).exists()
        ) {
            android.util.Log.i("KEQDIS_QS", "onClick: no usable server snapshot → opening app")
            openAppForConnect()
            return
        }

        val intent = Intent(this, KeqdisVpnService::class.java).apply {
            action = KeqdisVpnService.ACTION_START
            putExtra(KeqdisVpnService.EXTRA_VPN_BACKEND, backend)
            putExtra(KeqdisVpnService.EXTRA_CORE_ENGINE, coreEngine)
            // Режим прошлого старта — по той же причине, что движок и ядро: без
            // него плитка поднимала бы полноценный VPN поверх настройки «только
            // прокси», то есть тихо делала бы не то, что человек выбрал. И
            // разрешения на VPN у неё для этого может не оказаться вовсе.
            putExtra(
                KeqdisVpnService.EXTRA_TUNNEL_MODE,
                prefs.getString(
                    KeqdisVpnService.KEY_QS_LAST_TUNNEL_MODE,
                    KeqdisVpnService.TUNNEL_MODE_VPN,
                ) ?: KeqdisVpnService.TUNNEL_MODE_VPN,
            )
            putExtra(KeqdisVpnService.EXTRA_XRAY_CONFIG, xrayPath)
            putExtra("socks_port", port)
            putStringArrayListExtra("exclude_packages", ArrayList(exc))
            putStringArrayListExtra("include_packages", ArrayList(inc))
            putExtra(KeqdisVpnService.EXTRA_SOCKS_USERNAME, user)
            putExtra(KeqdisVpnService.EXTRA_SOCKS_PASSWORD, pass)
            if (!serverName.isNullOrBlank()) putExtra(KeqdisVpnService.EXTRA_SERVER_NAME, serverName)
        }

        try {
            if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
        } catch (e: Exception) {
            // Android 12+ бросает ForegroundServiceStartNotAllowedException, если
            // приложению запрещён фоновый старт сервиса («Ограничить фоновую
            // активность», выключенный автозапуск на OEM-прошивках). Молча
            // проглотить нельзя — уводим человека в приложение, оттуда старт
            // разрешён всегда.
            android.util.Log.e("KEQDIS_QS", "onClick: service start refused by system: $e")
            openAppForConnect()
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

        val open = Runnable {
            try {
                // Collapse QS panel and open the app.
                if (Build.VERSION.SDK_INT >= 34) {
                    // Android 14+ - startActivityAndCollapse(Intent) is forbidden, must use PendingIntent
                    val pendingIntent = PendingIntent.getActivity(
                        this,
                        0,
                        launchIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    startActivityAndCollapse(pendingIntent)
                } else if (Build.VERSION.SDK_INT >= 24) {
                    @Suppress("DEPRECATION")
                    startActivityAndCollapse(launchIntent)
                } else {
                    startActivity(launchIntent)
                }
            } catch (e: Exception) {
                // Прошивки с урезанным фоновым запуском активностей (MIUI/HyperOS
                // и родня) режут запуск из шторки. Пробуем напрямую, а если и это
                // не проходит — говорим вслух, иначе нажатие выглядит как «ничего».
                android.util.Log.e("KEQDIS_QS", "startActivityAndCollapse failed: $e")
                runCatching { startActivity(launchIntent) }.onFailure {
                    android.util.Log.e("KEQDIS_QS", "startActivity fallback failed: $it")
                    toast(R.string.tile_error_open_app)
                }
            }
        }

        // На заблокированном экране активность просто не покажется: система
        // требует сначала снять блокировку и лишь потом выполнять действие.
        if (Build.VERSION.SDK_INT >= 24 && isLocked) unlockAndRun(open) else open.run()
    }

    private fun toast(resId: Int) {
        runCatching { Toast.makeText(this, resId, Toast.LENGTH_LONG).show() }
    }

    private fun updateTileFromPrefs() {
        if (Build.VERSION.SDK_INT < 24) return

        val status = getSharedPreferences(KeqdisVpnService.PREFS_QS, MODE_PRIVATE)
            .getString(KeqdisVpnService.KEY_QS_STATUS, "disconnected")
            ?.lowercase()
            ?: "disconnected"

        android.util.Log.d("KEQDIS_QS", "updateTileFromPrefs: status=$status")

        val tileObj = qsTile
        if (tileObj == null) {
            // Retry mechanism: schedule another attempt if qsTile is not available yet
            if (retryCount < MAX_RETRIES) {
                android.util.Log.d("KEQDIS_QS", "updateTileFromPrefs: qsTile is null, scheduling retry (${retryCount + 1}/$MAX_RETRIES)")
                retryHandler?.removeCallbacks(retryRunnable)
                retryHandler = Handler(Looper.getMainLooper())
                retryHandler?.postDelayed(retryRunnable, RETRY_DELAY_MS)
                retryCount++
            } else {
                android.util.Log.w("KEQDIS_QS", "updateTileFromPrefs: max retries reached, giving up")
                retryCount = 0
            }
            return
        }

        // Reset retry counter if we successfully got the tile
        retryCount = 0
        retryHandler?.removeCallbacks(retryRunnable)

        tileObj.label = "Keqdis"
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tileObj.icon = android.graphics.drawable.Icon.createWithResource(this, TILE_ICON_RES)
        }
        
        // connecting раньше был STATE_UNAVAILABLE — «идёт подключение, не мешай».
        // Беда в том, что нажатие по недоступной плитке система не доставляет
        // вовсе: стоило процессу умереть на середине коннекта (агрессивные OEM-
        // прошивки это делают), и в prefs навсегда оставался connecting — плитка
        // отвечала на палец только анимацией. Держим её нажимаемой: клик на
        // connecting = остановить, и залипшее состояние снимается руками.
        val connecting = status == "connecting" || status == "starting"
        tileObj.state = when {
            status == "connected" || status == "running" || connecting -> Tile.STATE_ACTIVE
            else -> Tile.STATE_INACTIVE
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tileObj.subtitle = if (connecting) getString(R.string.tile_connecting) else null
        }
        android.util.Log.d("KEQDIS_QS", "updateTileFromPrefs: new tile.state=${tileObj.state}")
        tileObj.updateTile()
    }
}
