package com.keqdroid.keqdroid

import android.content.Context
import android.net.ConnectivityManager
import android.net.InetAddresses
import android.net.LocalServerSocket
import android.net.LocalSocket
import android.net.LocalSocketAddress
import android.os.Build
import android.os.Process
import android.os.SystemClock
import android.system.OsConstants
import java.net.InetSocketAddress
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

// ядро на Android владельца соединения само не узнает (SELinux), а getConnectionOwnerUid отвечает только владельцу VPN.
// протокол в tool/patches/mihomo-android-uid-owner.patch и xray-android-uid-owner.patch
class ConnectionOwnerServer(private val context: Context) {

    val name = "${context.packageName}.owner.${Process.myPid()}.${SystemClock.elapsedRealtimeNanos()}"

    private val server = LocalServerSocket(name)
    private val pool = Executors.newFixedThreadPool(4)
    private val packages = ConcurrentHashMap<Int, String>()
    private val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    @Volatile private var closed = false

    // режим только выбранные: сам Android тут вне VPN, и его DNS приходит в туннель без владельца
    @Volatile var systemOutsideVpn = false

    // время ответа в микросекундах, для замера цены поиска на телефоне
    private val timings = ArrayList<Long>()
    private var answered = 0L
    private var outside = 0L

    init {
        Thread({ acceptLoop() }, "keqdroid-owner").apply { isDaemon = true }.start()
    }

    fun close() {
        if (closed) return
        closed = true
        // accept() не просыпается от close() сервера, будим подключением
        runCatching { LocalSocket().use { it.connect(LocalSocketAddress(name)) } }
        runCatching { server.close() }
        pool.shutdownNow()
        logTimings()
    }

    private fun acceptLoop() {
        while (!closed) {
            val socket = runCatching { server.accept() }.getOrNull() ?: break
            if (closed) {
                runCatching { socket.close() }
                break
            }
            pool.execute { runCatching { serve(socket) } }
        }
    }

    private fun serve(socket: LocalSocket) {
        socket.use {
            if (it.peerCredentials.uid != Process.myUid()) return
            it.soTimeout = 1000
            val line = it.inputStream.bufferedReader().readLine() ?: return
            val started = SystemClock.elapsedRealtimeNanos()
            val pkg = runCatching { ownerOf(line) }.getOrDefault("")
            it.outputStream.write("$pkg\n".toByteArray())
            it.outputStream.flush()
            record((SystemClock.elapsedRealtimeNanos() - started) / 1000, pkg == OUTSIDE_VPN)
        }
    }

    private fun ownerOf(request: String): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return ""
        val query = parseOwnerQuery(request) ?: return ""
        val proto = if (query.udp) OsConstants.IPPROTO_UDP else OsConstants.IPPROTO_TCP
        val uid = cm.getConnectionOwnerUid(
            proto,
            InetSocketAddress(InetAddresses.parseNumericAddress(query.srcIp), query.srcPort),
            InetSocketAddress(InetAddresses.parseNumericAddress(query.dstIp), query.dstPort),
        )
        if (uid == Process.INVALID_UID) {
            return unownedAnswer(systemOutsideVpn, query.dstIp, query.dstPort) {
                cm.getLinkProperties(cm.activeNetwork)?.privateDnsServerName != null
            }
        }
        return packages.getOrPut(uid) {
            context.packageManager.getPackagesForUid(uid)?.firstOrNull() ?: ""
        }
    }

    private fun record(micros: Long, outsideVpn: Boolean) {
        val report = synchronized(timings) {
            timings.add(micros)
            answered++
            if (outsideVpn) outside++
            answered % 500 == 0L
        }
        if (report) logTimings()
    }

    private fun logTimings() {
        val (sorted, total, outsideTotal) = synchronized(timings) {
            val copy = timings.sorted()
            timings.clear()
            Triple(copy, answered, outside)
        }
        if (sorted.isEmpty()) return
        NativeLog.i("KEQDIS", ownerTimingLine(sorted, total, outsideTotal))
    }

    companion object {
        // то же имя в lib/utils/owner_guard.dart и tool/patches/mihomo-uid-owner-guard.patch
        const val OUTSIDE_VPN = "keqdroid:outside-vpn"
    }
}

internal class OwnerQuery(val udp: Boolean, val srcIp: String, val srcPort: Int, val dstIp: String, val dstPort: Int)

// строка от ядра: network srcIp srcPort dstIp dstPort
internal fun parseOwnerQuery(line: String): OwnerQuery? {
    val parts = line.trim().split(' ')
    if (parts.size < 5) return null
    val srcPort = parts[2].toIntOrNull() ?: return null
    val dstPort = parts[4].toIntOrNull() ?: return null
    return OwnerQuery(parts[0] == "udp", parts[1], srcPort, parts[3], dstPort)
}

// без владельца система отвечает и про приложение вне VPN, привязавшее сокет к tun0: это имя ловит правило защиты адреса сервера.
// сам Android ходит только на наш DNS в туннеле и на сервер строгого Частного DNS, чьих адресов приложению не выдают
internal fun unownedAnswer(
    systemOutsideVpn: Boolean,
    dstIp: String,
    dstPort: Int,
    privateDnsOn: () -> Boolean,
): String {
    val systemDns = systemOutsideVpn && when {
        dstPort != 53 && dstPort != 853 -> false
        dstIp == KeqdisVpnService.TUN_DNS_ADDRESS -> true
        dstPort == 853 -> privateDnsOn()
        else -> false
    }
    return if (systemDns) "" else ConnectionOwnerServer.OUTSIDE_VPN
}

internal fun ownerTimingLine(sorted: List<Long>, total: Long, outside: Long): String =
    "owner lookups: $total total, last ${sorted.size}: " +
        "median ${sorted[sorted.size / 2]} us, " +
        "p95 ${sorted[(sorted.size * 95 / 100).coerceAtMost(sorted.size - 1)]} us, " +
        "max ${sorted.last()} us, outside VPN: $outside"
