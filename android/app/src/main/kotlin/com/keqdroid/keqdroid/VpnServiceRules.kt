package com.keqdroid.keqdroid

internal fun statusName(status: VpnRunStatus): String = when (status) {
    VpnRunStatus.STOPPED -> "disconnected"
    VpnRunStatus.STARTING -> "connecting"
    VpnRunStatus.RUNNING -> "connected"
    VpnRunStatus.ERROR -> "error"
}

internal fun statusNeedsHealing(persisted: String?): Boolean =
    persisted != "disconnected" && persisted != "error"

internal fun sessionTunnelMode(extra: String?): String =
    if (extra == KeqdisVpnService.TUNNEL_MODE_PROXY) {
        KeqdisVpnService.TUNNEL_MODE_PROXY
    } else {
        KeqdisVpnService.TUNNEL_MODE_VPN
    }

// startsTunnel null: снапшота нет
internal fun restoreRefusal(
    startsTunnel: Boolean?,
    alwaysOn: Boolean,
    consentMissing: () -> Boolean,
): String? = when {
    startsTunnel == null -> "there is no server to reconnect to, connect from the app once"
    // Постоянный VPN ждёт интерфейс, и система висела бы в подключается
    alwaysOn && !startsTunnel -> "the last session was a local proxy, and always-on VPN needs a tunnel"
    startsTunnel && consentMissing() -> "the VPN permission was taken away"
    else -> null
}

// ядро, прожившее дольше 30 с, поднимаем всегда. трижды подряд умершее сразу сломано само,
// круг перезапусков прятал бы это за подключено
internal const val CORE_QUICK_DEATH_MS = 30_000L
internal const val CORE_MAX_QUICK_DEATHS = 3

internal fun quickDeathsAfter(previous: Int, livedMs: Long): Int =
    if (livedMs < CORE_QUICK_DEATH_MS) previous + 1 else 0

internal fun hyperOsVersionOf(
    name: String,
    code: String,
    build: String,
    manufacturer: String?,
    brand: String?,
): String? {
    val xiaomi = listOf(manufacturer, brand).any { it.orEmpty().lowercase() in setOf("xiaomi", "redmi", "poco") }
    return when {
        name.isNotEmpty() -> "$name (name)"
        code.isNotEmpty() -> "code $code"
        xiaomi && Regex("^OS\\d").containsMatchIn(build) -> "$build (build)"
        else -> null
    }
}

internal fun needsExplicitUnderlying(manufacturer: String): Boolean {
    val upper = manufacturer.uppercase()
    return upper == "HUAWEI" || upper == "HONOR"
}

internal class MemoryWatch {
    private var last = 0L
    private var threshold = 1024L * 1024 * 1024

    fun alarms(total: Long): List<String> {
        val alarms = ArrayList<String>(2)
        if (total >= threshold) {
            while (total >= threshold) threshold *= 2
            alarms.add("now above ${megabytes(threshold / 2)}")
        }
        if (last > 0 && total - last >= GROWTH_ALARM) {
            alarms.add("grew by ${megabytes(total - last)} since last time")
        }
        last = total
        return alarms
    }

    private companion object {
        const val GROWTH_ALARM = 256L * 1024 * 1024
    }
}

// у VmRSS килобайты, у Threads штуки
internal fun statusField(lines: Sequence<String>, key: String): Long? =
    lines.firstOrNull { it.startsWith("$key:") }
        ?.substringAfter(':')?.trim()?.substringBefore(' ')?.toLongOrNull()

internal fun megabytes(bytes: Long): String = "${bytes / (1024 * 1024)} MB"

internal fun formatSpeed(bytesPerSec: Long): String = when {
    bytesPerSec >= 1024 * 1024 ->
        String.format(java.util.Locale.US, "%.1f MB/s", bytesPerSec / (1024.0 * 1024.0))
    bytesPerSec >= 1024 ->
        String.format(java.util.Locale.US, "%.1f KB/s", bytesPerSec / 1024.0)
    else -> "$bytesPerSec B/s"
}

internal fun formatUptime(ms: Long): String {
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

internal fun notificationBody(
    showUptime: Boolean,
    showSpeed: Boolean,
    uptimeMs: Long,
    downloadSpeed: Long,
    uploadSpeed: Long,
): String {
    val parts = ArrayList<String>(3)
    if (showUptime) parts.add(formatUptime(uptimeMs))
    if (showSpeed) {
        parts.add("↓ ${formatSpeed(downloadSpeed)}")
        parts.add("↑ ${formatSpeed(uploadSpeed)}")
    }
    return if (parts.isEmpty()) "Connected" else parts.joinToString("  ·  ")
}
