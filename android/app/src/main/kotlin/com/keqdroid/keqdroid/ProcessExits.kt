package com.keqdroid.keqdroid

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// убитый снаружи процесс в свои логи ничего не пишет, а система помнит, кто и почему, и отдаёт это без разрешений
object ProcessExits {

    // без статуса запись не отличит убийство посреди VPN от убийства простаивающего приложения
    fun noteVpnStatus(context: Context, status: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        runCatching {
            context.getSystemService(ActivityManager::class.java)
                ?.setProcessStateSummary(vpnSummary(status))
        }
    }

    fun recent(context: Context, max: Int = 10): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return emptyList()
        return records(context, max).map { info ->
            mapOf(
                "timestamp" to info.timestamp,
                "reason" to info.reason,
                "reasonName" to reasonName(info.reason),
                "status" to info.status,
                "importance" to info.importance,
                "description" to info.description,
                "vpnStatus" to vpnStatusOf(info),
            )
        }
    }

    fun describeLast(context: Context): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        val info = records(context, 1).firstOrNull() ?: return null
        val time = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date(info.timestamp))
        return describe(time, info.reason, info.status, vpnStatusOf(info), info.description)
    }

    internal fun describe(time: String, reason: Int, status: Int, vpn: String?, description: String?): String {
        val vpnPart = vpn?.let { ", VPN $it" } ?: ""
        val descriptionPart = description?.takeIf { it.isNotBlank() }?.let { ", \"$it\"" } ?: ""
        return "$time, ${reasonName(reason)}, status $status$vpnPart$descriptionPart"
    }

    internal fun vpnSummary(status: String): ByteArray = "$SUMMARY_PREFIX$status".toByteArray(Charsets.UTF_8)

    internal fun vpnStatusFromSummary(summary: ByteArray?): String? {
        val raw = summary?.toString(Charsets.UTF_8) ?: return null
        return raw.removePrefix(SUMMARY_PREFIX).takeIf { raw.startsWith(SUMMARY_PREFIX) }
    }

    internal fun reasonName(reason: Int): String = when (reason) {
        ApplicationExitInfo.REASON_EXIT_SELF -> "EXIT_SELF"
        ApplicationExitInfo.REASON_SIGNALED -> "SIGNALED"
        ApplicationExitInfo.REASON_LOW_MEMORY -> "LOW_MEMORY"
        ApplicationExitInfo.REASON_CRASH -> "CRASH"
        ApplicationExitInfo.REASON_CRASH_NATIVE -> "CRASH_NATIVE"
        ApplicationExitInfo.REASON_ANR -> "ANR"
        ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "INITIALIZATION_FAILURE"
        ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "PERMISSION_CHANGE"
        ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "EXCESSIVE_RESOURCE_USAGE"
        ApplicationExitInfo.REASON_USER_REQUESTED -> "USER_REQUESTED"
        ApplicationExitInfo.REASON_USER_STOPPED -> "USER_STOPPED"
        ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "DEPENDENCY_DIED"
        ApplicationExitInfo.REASON_OTHER -> "OTHER"
        ApplicationExitInfo.REASON_FREEZER -> "FREEZER"
        ApplicationExitInfo.REASON_PACKAGE_STATE_CHANGE -> "PACKAGE_STATE_CHANGE"
        ApplicationExitInfo.REASON_PACKAGE_UPDATED -> "PACKAGE_UPDATED"
        else -> "UNKNOWN($reason)"
    }

    private fun records(context: Context, max: Int): List<ApplicationExitInfo> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return emptyList()
        val am = context.getSystemService(ActivityManager::class.java) ?: return emptyList()
        return runCatching {
            am.getHistoricalProcessExitReasons(context.packageName, 0, max)
        }.getOrDefault(emptyList())
    }

    private fun vpnStatusOf(info: ApplicationExitInfo): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        return vpnStatusFromSummary(info.processStateSummary)
    }

    private const val SUMMARY_PREFIX = "vpn="
}
