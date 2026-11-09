package com.keqdroid.keqdroid

import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts

// прошивки с Автозапуском отнимают у плитки старт сервиса, но окно открыть дают, а из окна на переднем плане сервис стартует всегда.
// образец TunnelToggleActivity в WireGuard
class QuickConnectActivity : ComponentActivity() {

    companion object {
        // по нему плитка узнаёт, что запуск из шторки не прошёл: сам запуск об этом молчит
        @JvmStatic
        @Volatile
        var openedAt: Long = 0L
            private set

        private const val STATE_ASKING_CONSENT = "asking_consent"
    }

    private var pending: Intent? = null
    private var askingConsent = false

    private val consent =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            askingConsent = false
            // отказ в согласии это ответ, закрываемся молча
            if (result.resultCode != RESULT_OK) {
                pending = null
                finish()
            }
            // иначе стартует onResume
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        openedAt = SystemClock.elapsedRealtime()

        val start = KeqdisVpnService.snapshotStartIntent(this)
        if (start == null) {
            // снапшот пропал, подключит приложение
            openApp()
            finish()
            return
        }
        pending = start

        // пересоздание посреди системного диалога: ответ ещё придёт, второй диалог не нужен
        askingConsent = savedInstanceState?.getBoolean(STATE_ASKING_CONSENT) ?: false
        if (!askingConsent && KeqdisVpnService.startsTunnel(start)) {
            VpnService.prepare(this)?.let {
                askingConsent = true
                consent.launch(it)
            }
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putBoolean(STATE_ASKING_CONSENT, askingConsent)
    }

    // старт в onResume: окно на переднем плане только с этого момента
    override fun onResume() {
        super.onResume()
        if (askingConsent) return
        val start = pending ?: return
        pending = null
        try {
            if (Build.VERSION.SDK_INT >= 26) startForegroundService(start) else startService(start)
        } catch (e: Exception) {
            NativeLog.e("KEQDIS_QS", "quick connect: service start refused: $e")
            runCatching { Toast.makeText(this, R.string.tile_error_start, Toast.LENGTH_LONG).show() }
            openApp()
        }
        finish()
    }

    private fun openApp() {
        runCatching {
            startActivity(MainActivity.launchActionIntent(this, MainActivity.LAUNCH_ACTION_CONNECT))
        }
    }
}
