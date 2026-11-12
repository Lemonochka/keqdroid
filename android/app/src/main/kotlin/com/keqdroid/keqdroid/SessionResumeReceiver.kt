package com.keqdroid.keqdroid

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build

// перезагрузка и обновление убивают процесс без штатного выключения, и KEY_QS_SESSION_WANTED остаётся прежним.
// без этого после обновления из приложения VPN оказывался выключенным
class SessionResumeReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val note = resumeNote(intent.action) ?: return
        val prefs = context.getSharedPreferences(KeqdisVpnService.PREFS_QS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(KeqdisVpnService.KEY_QS_SESSION_WANTED, false)) return

        val start = KeqdisVpnService.snapshotStartIntent(context)
        if (start == null) {
            NativeLog.w(TAG, "${intent.action}: the VPN was on, but there is no snapshot to reconnect with")
            return
        }
        // согласие спрашивает только окно, из фона его не открыть
        if (KeqdisVpnService.startsTunnel(start) && VpnService.prepare(context) != null) {
            NativeLog.w(TAG, "${intent.action}: the VPN permission was taken away, staying down")
            return
        }
        start.putExtra(KeqdisVpnService.EXTRA_LOG_NOTE, note)
        try {
            // из этих рассылок старт разрешён явно, отказать может только прошивка
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(start) else context.startService(start)
            NativeLog.i(TAG, "${intent.action}: reconnecting to the last server")
        } catch (e: Exception) {
            NativeLog.e(TAG, "${intent.action}: service start refused by system: $e")
        }
    }

    private companion object {
        const val TAG = "KEQDIS_RESUME"
    }
}

internal fun resumeNote(action: String?): String? = when (action) {
    Intent.ACTION_MY_PACKAGE_REPLACED -> "the app was updated while the VPN was on, reconnecting"
    Intent.ACTION_BOOT_COMPLETED -> "the phone restarted while the VPN was on, reconnecting"
    else -> null
}
