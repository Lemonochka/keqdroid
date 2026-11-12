package com.keqdroid.keqdroid

import android.content.Context
import android.content.SharedPreferences
import org.robolectric.RuntimeEnvironment
import java.io.File

internal object RoboSession {
    val context: Context get() = RuntimeEnvironment.getApplication()

    fun prefs(): SharedPreferences = context.getSharedPreferences(KeqdisVpnService.PREFS_QS, Context.MODE_PRIVATE)

    fun saveSnapshot(
        tunnelMode: String = KeqdisVpnService.TUNNEL_MODE_VPN,
        backend: String = KeqdisVpnService.VPN_BACKEND_XRAY,
        serverName: String? = "Frankfurt",
        exclude: Set<String> = emptySet(),
    ): File {
        val config = File(context.filesDir, "xray_config.json").apply { writeText("{}") }
        SessionSnapshot(
            backend = backend,
            tunnelMode = tunnelMode,
            config = config.path,
            socksPort = 10808,
            exclude = exclude,
            include = emptySet(),
            username = "user",
            password = "pass",
            serverName = serverName,
        ).writeTo(prefs().edit()).commit()
        return config
    }

    // в процессе liveStatus меняет только сервис, у поля закрытый сеттер
    fun setLiveStatus(status: String) {
        KeqdisVpnService::class.java.getDeclaredField("liveStatus").apply { isAccessible = true }.set(null, status)
    }
}
