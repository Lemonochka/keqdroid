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
        val (network, srcIp, srcPort, dstIp, dstPort) = request.trim().split(' ')
        val proto = if (network == "udp") OsConstants.IPPROTO_UDP else OsConstants.IPPROTO_TCP
        val uid = cm.getConnectionOwnerUid(
            proto,
            InetSocketAddress(InetAddresses.parseNumericAddress(srcIp), srcPort.toInt()),
            InetSocketAddress(InetAddresses.parseNumericAddress(dstIp), dstPort.toInt()),
        )
        // так система отвечает и про приложение вне VPN, привязавшее сокет к tun0: это имя ловит правило защиты адреса сервера
        if (uid == Process.INVALID_UID) {
            return if (systemOutsideVpn && isSystemDns(dstIp, dstPort.toInt())) "" else OUTSIDE_VPN
        }
        return packages.getOrPut(uid) {
            context.packageManager.getPackagesForUid(uid)?.firstOrNull() ?: ""
        }
    }

    // сам Android ходит только на наш DNS в туннеле и на сервер строгого Частного DNS, чьих адресов приложению не выдают
    private fun isSystemDns(dstIp: String, dstPort: Int): Boolean = when {
        dstPort != 53 && dstPort != 853 -> false
        dstIp == KeqdisVpnService.TUN_DNS_ADDRESS -> true
        dstPort == 853 -> cm.getLinkProperties(cm.activeNetwork)?.privateDnsServerName != null
        else -> false
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
        NativeLog.i(
            "KEQDIS",
            "owner lookups: $total total, last ${sorted.size}: " +
                "median ${sorted[sorted.size / 2]} us, " +
                "p95 ${sorted[(sorted.size * 95 / 100).coerceAtMost(sorted.size - 1)]} us, " +
                "max ${sorted.last()} us, outside VPN: $outsideTotal",
        )
    }

    companion object {
        // то же имя в lib/utils/owner_guard.dart и tool/patches/mihomo-uid-owner-guard.patch
        const val OUTSIDE_VPN = "keqdroid:outside-vpn"
    }
}
