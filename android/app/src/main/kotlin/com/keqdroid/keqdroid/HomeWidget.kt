package com.keqdroid.keqdroid

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.ColorStateList
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import java.util.concurrent.ConcurrentHashMap

class HomeWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        HomeWidget.render(context, ids)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        options: Bundle,
    ) {
        HomeWidget.render(context, intArrayOf(id))
    }

    override fun onDeleted(context: Context, ids: IntArray) {
        HomeWidget.forget(context, ids)
    }
}

// провайдер виджета обязан быть exported, и через него кто угодно включал бы VPN. нажатие идёт сюда, наружу закрыто
class HomeWidgetToggleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        HomeWidget.toggle(context, goAsync())
    }
}

internal object HomeWidget {
    private const val TAG = "KEQDIS_WIDGET"
    private const val PREFS = "keqdis_widget"

    private const val REQ_TOGGLE = 1
    private const val REQ_WINDOW = 2
    private const val REQ_CONNECT = 3
    private const val REQ_OPEN = 4

    // налив идёт 2,4 с с появления слоя, и только после него налив и доворот меняются на стоячие картинки.
    // анимация, оставленная на виду, повторялась бы при каждом возврате на рабочий стол
    private const val SETTLE_MS = 2700L

    internal enum class Look { OFF, CONNECTING, ON, ERROR }

    // стоячая вода: задний и передний слой на каждый уровень
    internal enum class Kind(val layout: Int, val idle: IntArray, val busy: IntArray, val on: IntArray) {
        DROP(
            R.layout.widget_drop,
            intArrayOf(R.drawable.widget_water_drop_idle_back, R.drawable.widget_water_drop_idle_front),
            intArrayOf(R.drawable.widget_water_drop_busy_back, R.drawable.widget_water_drop_busy_front),
            intArrayOf(R.drawable.widget_water_drop_on_back, R.drawable.widget_water_drop_on_front),
        ),
        GLASS(
            R.layout.widget_glass,
            intArrayOf(R.drawable.widget_water_glass_idle_back, R.drawable.widget_water_glass_idle_front),
            intArrayOf(R.drawable.widget_water_glass_busy_back, R.drawable.widget_water_glass_busy_front),
            intArrayOf(R.drawable.widget_water_glass_on_back, R.drawable.widget_water_glass_on_front),
        ),
        PLAQUE(
            R.layout.widget_plaque,
            intArrayOf(R.drawable.widget_water_plaque_idle_back, R.drawable.widget_water_plaque_idle_front),
            intArrayOf(R.drawable.widget_water_plaque_busy_back, R.drawable.widget_water_plaque_busy_front),
            intArrayOf(R.drawable.widget_water_plaque_on_back, R.drawable.widget_water_plaque_on_front),
        ),
    }

    private class Slot(
        val fade: Int, val slot: Int, val bg: Int,
        val stillB: Int, val stillF: Int,
        val pourBusyB: Int, val pourBusyF: Int, val pourOnB: Int, val pourOnF: Int,
        val btn: Int, val btnBg: Int, val logo: Int, val load: Int, val settle: Int,
        val name: Int, val status: Int, val clock: Int, val onRow: Int, val ping: Int,
    )

    private val SLOTS = arrayOf(
        Slot(
            R.id.w_a_fade, R.id.w_a_slot, R.id.w_a_bg,
            R.id.w_a_still_b, R.id.w_a_still_f,
            R.id.w_a_pour_busy_b, R.id.w_a_pour_busy_f, R.id.w_a_pour_on_b, R.id.w_a_pour_on_f,
            R.id.w_a_btn, R.id.w_a_btn_bg, R.id.w_a_logo, R.id.w_a_load, R.id.w_a_settle,
            R.id.w_a_name, R.id.w_a_status, R.id.w_a_clock, R.id.w_a_on_row, R.id.w_a_ping,
        ),
        Slot(
            R.id.w_b_fade, R.id.w_b_slot, R.id.w_b_bg,
            R.id.w_b_still_b, R.id.w_b_still_f,
            R.id.w_b_pour_busy_b, R.id.w_b_pour_busy_f, R.id.w_b_pour_on_b, R.id.w_b_pour_on_f,
            R.id.w_b_btn, R.id.w_b_btn_bg, R.id.w_b_logo, R.id.w_b_load, R.id.w_b_settle,
            R.id.w_b_name, R.id.w_b_status, R.id.w_b_clock, R.id.w_b_on_row, R.id.w_b_ping,
        ),
    )

    // до первого запуска приложения цвета из ресурсов, потом те, что прислал Dart
    private val DEFAULT_COLORS = mapOf(
        "surfaceContainer" to R.color.widget_surface_container,
        "surfaceContainerHighest" to R.color.widget_surface_container_highest,
        "onSurface" to R.color.widget_on_surface,
        "onSurfaceVariant" to R.color.widget_on_surface_variant,
        "primary" to R.color.widget_primary,
        "onPrimary" to R.color.widget_on_primary,
        "primaryContainer" to R.color.widget_primary_container,
        "onPrimaryContainer" to R.color.widget_on_primary_container,
        "secondaryContainer" to R.color.widget_secondary_container,
        "onSecondaryContainer" to R.color.widget_on_secondary_container,
        "error" to R.color.widget_error,
        "errorContainer" to R.color.widget_error_container,
        "onErrorContainer" to R.color.widget_on_error_container,
    )

    private class Data(
        val colors: Map<String, Int>,
        val name: String,
        val ping: String?,
        val since: Long,
        val tap: PendingIntent,
        val open: PendingIntent,
    ) {
        fun color(role: String) = colors.getValue(role)
    }

    private class Frame(
        val look: Look,
        val prev: Look?,
        val front: Int,
        val below: Boolean,
        val fadeIn: Boolean,
        val underPour: Boolean,
    )

    private val handler by lazy { Handler(Looper.getMainLooper()) }
    private val settling = ConcurrentHashMap.newKeySet<Int>()
    // старый слой ещё наливался, когда пришёл новый вид: под новым он должен остаться ровно таким,
    // иначе налив сменится стоячей картинкой посреди проявления
    private val underPouring = ConcurrentHashMap.newKeySet<Int>()
    private val tokens = ConcurrentHashMap<Int, Any>()

    fun refresh(context: Context) {
        val app = context.applicationContext
        val ids = runCatching {
            AppWidgetManager.getInstance(app)
                .getAppWidgetIds(ComponentName(app, HomeWidgetProvider::class.java))
        }.getOrNull() ?: return
        if (ids.isNotEmpty()) render(app, ids)
    }

    @Synchronized
    fun render(context: Context, ids: IntArray) {
        val app = context.applicationContext
        runCatching {
            val manager = AppWidgetManager.getInstance(app)
            val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val look = lookOf(QuickConnect.effectiveStatus(app))
            val data = data(app, prefs, look)
            for (id in ids) {
                runCatching { renderOne(app, manager, prefs, id, look, data) }
                    .onFailure { NativeLog.e(TAG, "render $id failed: $it", it) }
            }
        }.onFailure { NativeLog.e(TAG, "render failed: $it", it) }
    }

    fun forget(context: Context, ids: IntArray) {
        val edit = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
        for (id in ids) {
            settling.remove(id)
            underPouring.remove(id)
            tokens.remove(id)?.let { handler.removeCallbacksAndMessages(it) }
            edit.remove("w${id}_look").remove("w${id}_prev").remove("w${id}_front")
        }
        edit.apply()
    }

    fun store(context: Context, colors: Map<*, *>?, server: Map<*, *>?) {
        val edit = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
        colors?.forEach { (role, argb) ->
            if (role is String && argb is Number) edit.putInt("color_$role", argb.toInt())
        }
        if (server != null) {
            edit.putString("server_key", server["key"] as? String)
                .putString("server_name", server["name"] as? String)
                .putString("server_flag", server["flag"] as? String)
                .putString("server_ping", server["ping"] as? String)
        }
        edit.apply()
        refresh(context)
    }

    fun toggle(context: Context, pending: BroadcastReceiver.PendingResult) {
        val app = context.applicationContext
        var waiting = false
        try {
            NativeLog.i(TAG, "tap: status=${QuickConnect.persistedStatus(app)}")
            when (val tap = QuickConnect.decide(app, TAG)) {
                QuickConnect.Tap.Stop -> app.startService(QuickConnect.stopIntent(app))
                QuickConnect.Tap.OpenApp -> open(app, QuickConnect.openAppIntent(app, connect = true))
                QuickConnect.Tap.Window -> open(app, QuickConnect.quickConnectIntent(app))
                is QuickConnect.Tap.Start -> {
                    try {
                        if (Build.VERSION.SDK_INT >= 26) app.startForegroundService(tap.intent) else app.startService(tap.intent)
                    } catch (e: Exception) {
                        NativeLog.e(TAG, "tap: service start refused by system: $e")
                        QuickConnect.rememberDirectStartBlocked(app)
                        open(app, QuickConnect.quickConnectIntent(app))
                        refresh(app)
                        return
                    }
                    // прошивка глотает старт и без исключения. запомненный отказ перерисует кнопку на окно,
                    // окно из приёмника система откроет не всегда, а из нажатия на виджет откроет
                    waiting = true
                    handler.postDelayed({
                        runCatching {
                            if (!QuickConnect.liveActive()) {
                                NativeLog.e(TAG, "tap: service did not come up, likely blocked by the OEM")
                                QuickConnect.rememberDirectStartBlocked(app)
                                refresh(app)
                            }
                        }
                        pending.finish()
                    }, 2500)
                }
            }
        } catch (t: Throwable) {
            NativeLog.e(TAG, "tap failed: $t", t)
        } finally {
            if (!waiting) pending.finish()
        }
    }

    private fun open(app: Context, intent: Intent) {
        runCatching { app.startActivity(intent) }
            .onFailure { NativeLog.w(TAG, "tap: could not open ${intent.component}: $it") }
    }

    internal fun lookOf(status: String) = when (status) {
        "connected", "running" -> Look.ON
        "connecting", "starting" -> Look.CONNECTING
        "error" -> Look.ERROR
        else -> Look.OFF
    }

    private fun renderOne(
        app: Context,
        manager: AppWidgetManager,
        prefs: SharedPreferences,
        id: Int,
        look: Look,
        data: Data,
    ) {
        val last = prefs.getString("w${id}_look", null)
            ?.let { runCatching { Look.valueOf(it) }.getOrNull() }
        var front = prefs.getInt("w${id}_front", 0)
        // слои меняются местами через translationZ, а он доступен RemoteViews с Android 12. раньше вид меняется сразу
        val transition = Build.VERSION.SDK_INT >= 31 && last != null && last != look
        if (transition) {
            front = 1 - front
            prefs.edit()
                .putString("w${id}_look", look.name)
                .putString("w${id}_prev", last!!.name)
                .putInt("w${id}_front", front)
                .apply()
            if (id in settling) underPouring.add(id) else underPouring.remove(id)
            settling.add(id)
            val token = tokens.getOrPut(id) { Any() }
            handler.removeCallbacksAndMessages(token)
            handler.postAtTime({
                settling.remove(id)
                underPouring.remove(id)
                render(app, intArrayOf(id))
            }, token, SystemClock.uptimeMillis() + SETTLE_MS)
        } else if (last != look) {
            prefs.edit().putString("w${id}_look", look.name).apply()
        }
        val prev = prefs.getString("w${id}_prev", null)
            ?.let { runCatching { Look.valueOf(it) }.getOrNull() }
        val frame = Frame(
            look = look,
            prev = prev,
            front = front,
            below = id in settling && prev != null,
            fadeIn = transition,
            underPour = id in underPouring,
        )
        manager.updateAppWidget(id, views(app, manager, id, frame, data))
    }

    private fun data(app: Context, prefs: SharedPreferences, look: Look): Data {
        val colors = DEFAULT_COLORS.mapValues { (role, res) ->
            if (prefs.contains("color_$role")) prefs.getInt("color_$role", 0) else app.getColor(res)
        }
        val server = widgetServer(
            last = app.getSharedPreferences(KeqdisVpnService.PREFS_QS, Context.MODE_PRIVATE)
                .getString(KeqdisVpnService.KEY_QS_LAST_SERVER_NAME, null),
            key = prefs.getString("server_key", null),
            flag = prefs.getString("server_flag", null),
            name = prefs.getString("server_name", null),
            ping = prefs.getString("server_ping", null),
        )
        val since = KeqdisVpnService.connectedSince
        val tap = when (QuickConnect.decide(app, TAG, click = false)) {
            QuickConnect.Tap.OpenApp ->
                activity(app, REQ_CONNECT, QuickConnect.openAppIntent(app, connect = true))
            QuickConnect.Tap.Window -> activity(app, REQ_WINDOW, QuickConnect.quickConnectIntent(app))
            else -> PendingIntent.getBroadcast(
                app,
                REQ_TOGGLE,
                Intent(app, HomeWidgetToggleReceiver::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        return Data(
            colors = colors,
            name = server.name,
            ping = server.ping,
            since = if (look == Look.ON && since > 0) since else SystemClock.elapsedRealtime(),
            tap = tap,
            open = activity(app, REQ_OPEN, QuickConnect.openAppIntent(app, connect = false)),
        )
    }

    private fun activity(app: Context, request: Int, intent: Intent): PendingIntent =
        PendingIntent.getActivity(
            app,
            request,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    internal fun flagEmoji(code: String): String? {
        if (code.length != 2 || !code.all { it in 'A'..'Z' }) return null
        return code.map { String(Character.toChars(0x1F1E6 + (it - 'A'))) }.joinToString("")
    }

    internal class WidgetServer(val name: String, val ping: String?)

    // виджет, как плитка, подключает сервер последней сессии. имя без флага и пинг от приложения берём, только если это он
    internal fun widgetServer(last: String?, key: String?, flag: String?, name: String?, ping: String?): WidgetServer {
        val known = last == null || last == key
        if (!known) return WidgetServer(last ?: "", null)
        return WidgetServer(listOfNotNull(flag?.let(::flagEmoji), name ?: last).joinToString(" "), ping)
    }

    private fun views(app: Context, manager: AppWidgetManager, id: Int, frame: Frame, data: Data): RemoteViews {
        if (Build.VERSION.SDK_INT >= 31) {
            // лаунчер сам берёт вид под размер: 1x1 капля, 2x2 стакан, 4x1 плашка
            return RemoteViews(
                mapOf(
                    SizeF(40f, 40f) to kindViews(app, Kind.DROP, frame, data),
                    SizeF(110f, 110f) to kindViews(app, Kind.GLASS, frame, data),
                    SizeF(220f, 40f) to kindViews(app, Kind.PLAQUE, frame, data),
                ),
            )
        }
        return kindViews(app, kindFor(manager.getAppWidgetOptions(id)), frame, data)
    }

    private fun kindFor(options: Bundle): Kind = kindFor(
        options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH),
        options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT),
    )

    // то же правило, что у RemoteViews с размерами: из влезающих ближайший
    internal fun kindFor(w: Int, h: Int): Kind {
        if (w == 0 || h == 0) return Kind.GLASS
        return listOf(Kind.DROP to (40 to 40), Kind.GLASS to (110 to 110), Kind.PLAQUE to (220 to 40))
            .filter { (_, s) -> w + 1 >= s.first && h + 1 >= s.second }
            .minByOrNull { (_, s) -> (w - s.first) * (w - s.first) + (h - s.second) * (h - s.second) }
            ?.first ?: Kind.DROP
    }

    private fun kindViews(app: Context, kind: Kind, frame: Frame, data: Data): RemoteViews {
        val rv = RemoteViews(app.packageName, kind.layout)
        val top = SLOTS[frame.front]
        val under = SLOTS[1 - frame.front]
        if (frame.below && frame.prev != null) {
            // старый вид остаётся под новым, пока тот проявляется
            fill(rv, app, kind, under, frame.prev, data, pour = frame.underPour)
            rv.setViewVisibility(under.fade, View.VISIBLE)
            rv.setViewVisibility(under.slot, View.VISIBLE)
        } else {
            // держатель прячется первым, и исчезновение слоя внутри него уже никто не видит
            rv.setViewVisibility(under.fade, View.GONE)
            rv.setViewVisibility(under.slot, View.GONE)
        }
        fill(rv, app, kind, top, frame.look, data, pour = frame.below)
        if (Build.VERSION.SDK_INT >= 31) {
            rv.setFloat(under.fade, "setTranslationZ", 0f)
            rv.setFloat(top.fade, "setTranslationZ", 1f)
        }
        rv.setViewVisibility(top.fade, View.VISIBLE)
        // LayoutTransition держателя срабатывает только на смену видимости, GONE и сразу VISIBLE перезапускают проявление
        if (frame.fadeIn) rv.setViewVisibility(top.slot, View.GONE)
        rv.setViewVisibility(top.slot, View.VISIBLE)
        return rv
    }

    private fun shown(on: Boolean) = if (on) View.VISIBLE else View.GONE

    private fun tint(rv: RemoteViews, id: Int, color: Int) {
        if (Build.VERSION.SDK_INT >= 31) {
            rv.setColorStateList(id, "setIndeterminateTintList", ColorStateList.valueOf(color))
        }
    }

    // pour: слой только что появился, вода наливается и логотип доворачивается. без него всё стоит
    private fun fill(rv: RemoteViews, app: Context, kind: Kind, s: Slot, look: Look, d: Data, pour: Boolean) {
        rv.setInt(s.bg, "setColorFilter", d.color("surfaceContainer"))

        val error = look == Look.ERROR
        val idle = look == Look.OFF || error
        val front = d.color(if (error) "errorContainer" else "primaryContainer")
        val back = d.color(if (error) "error" else "primary")
        val pouring = pour && !idle
        val still = when (look) {
            Look.CONNECTING -> kind.busy
            Look.ON -> kind.on
            else -> kind.idle
        }
        rv.setImageViewResource(s.stillB, still[0])
        rv.setImageViewResource(s.stillF, still[1])
        rv.setViewVisibility(s.stillB, shown(!pouring))
        rv.setViewVisibility(s.stillF, shown(!pouring))
        rv.setViewVisibility(s.pourBusyB, shown(pouring && look == Look.CONNECTING))
        rv.setViewVisibility(s.pourBusyF, shown(pouring && look == Look.CONNECTING))
        rv.setViewVisibility(s.pourOnB, shown(pouring && look == Look.ON))
        rv.setViewVisibility(s.pourOnF, shown(pouring && look == Look.ON))
        rv.setInt(s.stillB, "setColorFilter", back)
        rv.setInt(s.stillF, "setColorFilter", front)
        tint(rv, s.pourBusyB, back)
        tint(rv, s.pourBusyF, front)
        tint(rv, s.pourOnB, back)
        tint(rv, s.pourOnF, front)

        val (fill, glyph) = when (look) {
            Look.OFF -> d.color("surfaceContainerHighest") to d.color("onSurfaceVariant")
            Look.CONNECTING -> d.color("primaryContainer") to d.color("onPrimaryContainer")
            Look.ON -> d.color("primary") to d.color("onPrimary")
            Look.ERROR -> d.color("errorContainer") to d.color("onErrorContainer")
        }
        // у капли кнопки нет, логотип стоит прямо на воде
        val logo = if (kind != Kind.DROP) glyph else when (look) {
            Look.OFF -> d.color("onSurfaceVariant")
            Look.CONNECTING, Look.ON -> d.color("primary")
            Look.ERROR -> d.color("onErrorContainer")
        }
        rv.setViewVisibility(s.logo, shown(idle || (look == Look.ON && !pour)))
        rv.setViewVisibility(s.load, shown(look == Look.CONNECTING))
        rv.setViewVisibility(s.settle, shown(look == Look.ON && pour))
        rv.setInt(s.logo, "setColorFilter", logo)
        tint(rv, s.load, logo)
        tint(rv, s.settle, logo)
        rv.setOnClickPendingIntent(s.btn, d.tap)
        rv.setContentDescription(
            s.btn,
            app.getString(
                if (look == Look.CONNECTING || look == Look.ON) R.string.shortcut_disconnect_short
                else R.string.shortcut_connect_short,
            ),
        )
        if (kind == Kind.DROP) return

        rv.setInt(s.btnBg, "setColorFilter", fill)
        rv.setOnClickPendingIntent(s.slot, d.open)
        rv.setTextViewText(s.name, d.name)
        rv.setTextColor(s.name, d.color("onSurface"))
        val on = look == Look.ON
        rv.setViewVisibility(s.status, shown(!on))
        rv.setTextViewText(
            s.status,
            app.getString(
                when (look) {
                    Look.CONNECTING -> R.string.widget_status_connecting
                    Look.ERROR -> R.string.widget_status_error
                    else -> R.string.widget_status_off
                },
            ),
        )
        rv.setTextColor(s.status, d.color(if (error) "error" else "onSurfaceVariant"))
        if (kind == Kind.PLAQUE) {
            rv.setViewVisibility(s.clock, shown(on))
            rv.setTextColor(s.clock, d.color("onSurfaceVariant"))
            rv.setChronometer(s.clock, d.since, app.getString(R.string.widget_clock_format), on)
        } else {
            rv.setViewVisibility(s.onRow, shown(on))
            rv.setTextColor(s.clock, d.color("onSurface"))
            rv.setChronometer(s.clock, d.since, null, on)
            rv.setViewVisibility(s.ping, shown(on && d.ping != null))
            rv.setTextViewText(s.ping, d.ping ?: "")
            rv.setTextColor(s.ping, d.color("onSecondaryContainer"))
            if (Build.VERSION.SDK_INT >= 31) {
                rv.setColorStateList(
                    s.ping,
                    "setBackgroundTintList",
                    ColorStateList.valueOf(d.color("secondaryContainer")),
                )
            }
        }
    }
}
