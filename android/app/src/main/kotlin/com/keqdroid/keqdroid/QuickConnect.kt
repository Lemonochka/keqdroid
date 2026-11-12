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
    fun isStale(persisted: String, liveActive: Boolean): Boolean = persisted in ACTIVE_STATUSES && !liveActive

    fun effectiveStatus(persisted: String, liveActive: Boolean): String =
        if (isStale(persisted, liveActive)) "disconnected" else persisted

    fun effectiveStatus(context: Context): String = effectiveStatus(persistedStatus(context), liveActive())

    enum class Route { STOP, OPEN_APP, CONSENT_WINDOW, BLOCKED_WINDOW, START }

    fun route(
        persisted: String,
        liveActive: Boolean,
        hasSnapshot: () -> Boolean,
        consentMissing: () -> Boolean,
        startBlocked: () -> Boolean,
    ): Route = when {
        persisted in ACTIVE_STATUSES && liveActive -> Route.STOP
        !hasSnapshot() -> Route.OPEN_APP
        // согласие спрашивает только окно, невидимое окно спросит и само подключит
        consentMissing() -> Route.CONSENT_WINDOW
        startBlocked() -> Route.BLOCKED_WINDOW
        else -> Route.START
    }

    // click = false для отрисовки: виджет только выбирает, куда вести кнопку, prefs не трогает и не пишет в журнал
    fun decide(context: Context, tag: String, click: Boolean = true): Tap {
        val status = persistedStatus(context)
        val live = liveActive()
        if (click && isStale(status, live)) {
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

        // consentMissing берёт start, который кладёт hasSnapshot: route зовёт их строго по порядку
        var start: Intent? = null
        val route = route(
            status,
            live,
            hasSnapshot = { KeqdisVpnService.snapshotStartIntent(context).also { start = it } != null },
            consentMissing = { KeqdisVpnService.startsTunnel(start!!) && VpnService.prepare(context) != null },
            startBlocked = { directStartBlocked(context) },
        )
        return when (route) {
            Route.STOP -> Tap.Stop
            Route.OPEN_APP -> {
                if (click) NativeLog.i(tag, "onClick: no usable server snapshot → opening app")
                Tap.OpenApp
            }
            Route.CONSENT_WINDOW -> {
                if (click) NativeLog.i(tag, "onClick: no VPN consent → quick connect window")
                Tap.Window
            }
            Route.BLOCKED_WINDOW -> {
                if (click) NativeLog.i(tag, "onClick: this firmware blocks direct start → quick connect window")
                Tap.Window
            }
            Route.START -> Tap.Start(start!!)
        }
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
