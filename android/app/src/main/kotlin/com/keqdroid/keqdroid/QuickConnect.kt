package com.keqdroid.keqdroid

import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build

// одно решение по нажатию для плитки и виджета: окно им нужно открывать по-разному, а выбор общий
internal object QuickConnect {

    // connecting не случайно: на нём нажатие останавливает
    val ACTIVE_STATUSES = setOf("connected", "running", "connecting", "starting")

    sealed interface Tap {
        object Stop : Tap
        object OpenApp : Tap
        object Window : Tap
        class Start(val intent: Intent) : Tap
    }

    fun persistedStatus(context: Context): String =
        (context.getSharedPreferences(KeqdisVpnService.PREFS_QS, Context.MODE_PRIVATE)
            .getString(KeqdisVpnService.KEY_QS_STATUS, "disconnected")
            ?: "disconnected").lowercase()

    fun liveActive(): Boolean = KeqdisVpnService.liveStatus.lowercase() in ACTIVE_STATUSES

    // запись в prefs переживает смерть процесса, туннель нет. liveStatus после перезапуска disconnected,
    // расхождение значит запись протухла
    fun effectiveStatus(context: Context): String {
        val persisted = persistedStatus(context)
        return if (persisted in ACTIVE_STATUSES && !liveActive()) "disconnected" else persisted
    }

    // click = false для отрисовки: виджет только выбирает, куда вести кнопку, prefs не трогает и не пишет в журнал
    fun decide(context: Context, tag: String, click: Boolean = true): Tap {
        val status = persistedStatus(context)
        if (status in ACTIVE_STATUSES && !liveActive()) {
            if (click) {
                NativeLog.w(
                    tag,
                    "onClick: stale persisted status '$status' " +
                        "(live='${KeqdisVpnService.liveStatus.lowercase()}') → healing and connecting",
                )
                context.getSharedPreferences(KeqdisVpnService.PREFS_QS, Context.MODE_PRIVATE)
                    .edit()
                    .putString(KeqdisVpnService.KEY_QS_STATUS, "disconnected")
                    .apply()
            }
        } else if (status in ACTIVE_STATUSES) {
            return Tap.Stop
        }

        val start = KeqdisVpnService.snapshotStartIntent(context)
        if (start == null) {
            if (click) NativeLog.i(tag, "onClick: no usable server snapshot → opening app")
            return Tap.OpenApp
        }
        // согласие спрашивает только окно, невидимое окно спросит и само подключит
        if (KeqdisVpnService.startsTunnel(start) && VpnService.prepare(context) != null) {
            if (click) NativeLog.i(tag, "onClick: no VPN consent → quick connect window")
            return Tap.Window
        }
        if (directStartBlocked(context)) {
            if (click) NativeLog.i(tag, "onClick: this firmware blocks direct start → quick connect window")
            return Tap.Window
        }
        return Tap.Start(start)
    }

    fun stopIntent(context: Context): Intent =
        Intent(context, KeqdisVpnService::class.java).apply {
            action = KeqdisVpnService.ACTION_STOP
        }

    // запомненный отказ ведёт сразу в окно, без 2,5 с ожидания. помним до обновления системы
    fun directStartBlocked(context: Context): Boolean =
        context.getSharedPreferences(KeqdisVpnService.PREFS_QS, Context.MODE_PRIVATE)
            .getString(KeqdisVpnService.KEY_QS_DIRECT_START_BLOCKED_ON, null) == Build.FINGERPRINT

    fun rememberDirectStartBlocked(context: Context) {
        context.getSharedPreferences(KeqdisVpnService.PREFS_QS, Context.MODE_PRIVATE)
            .edit()
            .putString(KeqdisVpnService.KEY_QS_DIRECT_START_BLOCKED_ON, Build.FINGERPRINT)
            .apply()
    }

    fun openAppIntent(context: Context, connect: Boolean): Intent {
        if (connect) {
            return MainActivity.launchActionIntent(context, MainActivity.LAUNCH_ACTION_CONNECT)
        }
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(context, MainActivity::class.java)
        return launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    fun quickConnectIntent(context: Context): Intent =
        Intent(context, QuickConnectActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION)
}
