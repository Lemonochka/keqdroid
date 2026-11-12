package com.keqdroid.keqdroid

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings

// разрешения Автозапуск в Android нет: состояние снаружи не прочитать, экран каждая прошивка прячет по-своему.
// экраны из библиотеки AutoStarter, realme она не знает, хотя у него та же ColorOS
object OemAutostart {

    // пакет и класс экрана
    private class Vendor(val brands: Set<String>, val screens: List<Pair<String, String>>)

    private val vendors = listOf(
        Vendor(
            setOf("xiaomi", "redmi", "poco"),
            listOf(
                "com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity",
            ),
        ),
        // на свежих ColorOS автозапуск переехал в батарею приложения (dontkillmyapp), старые экраны чужим закрыты
        Vendor(
            setOf("oppo", "realme", "oneplus"),
            listOf(
                "com.coloros.safecenter" to "com.coloros.safecenter.permission.startup.StartupAppListActivity",
                "com.coloros.safecenter" to "com.coloros.safecenter.startupapp.StartupAppListActivity",
                "com.oppo.safe" to "com.oppo.safe.permission.startup.StartupAppListActivity",
                "com.oneplus.security" to "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity",
            ),
        ),
        Vendor(
            setOf("vivo", "iqoo"),
            listOf(
                "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
                "com.vivo.permissionmanager" to "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
                "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager",
            ),
        ),
        Vendor(
            setOf("huawei", "honor"),
            listOf(
                "com.huawei.systemmanager" to "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
                "com.huawei.systemmanager" to "com.huawei.systemmanager.optimize.process.ProtectActivity",
            ),
        ),
        Vendor(
            setOf("asus"),
            listOf(
                "com.asus.mobilemanager" to "com.asus.mobilemanager.autostart.AutoStartActivity",
            ),
        ),
    )

    const val KIND_NONE = "none"
    const val KIND_SCREEN = "screen"
    const val KIND_APP_DETAILS = "appDetails"

    // null: прошивка без своего Автозапуска
    internal fun screensFor(brand: String, manufacturer: String): List<Pair<String, String>>? {
        val names = setOf(brand.lowercase(), manufacturer.lowercase())
        return vendors.firstOrNull { v -> v.brands.any { it in names } }?.screens
    }

    private fun vendorScreens() = screensFor(Build.BRAND, Build.MANUFACTURER)

    // неэкспортированный экран резолвится, но открывается SecurityException
    private fun screens(context: Context): List<Intent> =
        vendorScreens().orEmpty().mapNotNull { (pkg, cls) ->
            val intent = Intent().setComponent(ComponentName(pkg, cls)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            val info = runCatching { context.packageManager.resolveActivity(intent, 0) }.getOrNull()
            intent.takeIf { info?.activityInfo?.exported == true }
        }

    // в карточке приложения искать придётся самому, и сказать это надо до перехода
    fun kind(context: Context): String = when {
        vendorScreens() == null -> KIND_NONE
        screens(context).isNotEmpty() -> KIND_SCREEN
        else -> KIND_APP_DETAILS
    }

    fun open(context: Context) {
        for (intent in screens(context)) {
            if (runCatching { context.startActivity(intent) }.isSuccess) return
        }
        context.startActivity(
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", context.packageName, null),
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }
}
