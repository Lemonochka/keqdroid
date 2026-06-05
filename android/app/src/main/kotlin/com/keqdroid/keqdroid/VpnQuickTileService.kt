package com.keqdroid.keqdroid

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.database.ContentObserver
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.net.VpnService
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

class VpnQuickTileService : TileService() {

    companion object {
        private val TILE_ICON_RES = R.drawable.ic_launcher_foreground
    }

    private val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(selfChange: Boolean) {
            updateTileFromPrefs()
        }
    }

    // Retry mechanism for cases when qsTile is not yet available
    private var retryHandler: Handler? = null
    private val retryRunnable = Runnable { updateTileFromPrefs() }
    private val RETRY_DELAY_MS = 500L
    private var retryCount = 0
    private val MAX_RETRIES = 10

    // BroadcastReceiver for status updates from service
    private val statusReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == KeqdisVpnService.BROADCAST_VPN_STATUS_CHANGED) {
                updateTileFromPrefs()
            }
        }
    }

    override fun onStartListening() {
        super.onStartListening()
        try {
            contentResolver.registerContentObserver(
                VpnStatusProvider.STATUS_URI,
                false,
                observer
            )
        } catch (e: Exception) {
            android.util.Log.e("KEQDIS", "Failed to register content observer: ${e.message}")
        }

        // Register broadcast receiver for status updates
        try {
            val filter = IntentFilter(KeqdisVpnService.BROADCAST_VPN_STATUS_CHANGED)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(statusReceiver, filter, RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(statusReceiver, filter)
            }
        } catch (e: Exception) {
            android.util.Log.e("KEQDIS", "Failed to register broadcast receiver: ${e.message}")
        }

        retryCount = 0
        updateTileFromPrefs()
    }

    override fun onStopListening() {
        super.onStopListening()
        retryHandler?.removeCallbacks(retryRunnable)
        retryHandler = null
        retryCount = 0
        try {
            contentResolver.unregisterContentObserver(observer)
        } catch (_: Exception) {}
        try {
            unregisterReceiver(statusReceiver)
        } catch (_: Exception) {}
    }

    override fun onClick() {
        super.onClick()

        val prefs = getSharedPreferences(KeqdisVpnService.PREFS_QS, MODE_PRIVATE)
        val status = prefs.getString(KeqdisVpnService.KEY_QS_STATUS, "disconnected") ?: "disconnected"

        // If VPN is running - stop it directly instead of toggle for reliability.
        if (status.equals("connected", ignoreCase = true) || status.equals("running", ignoreCase = true)) {
            startService(Intent(this, KeqdisVpnService::class.java).apply {
                action = KeqdisVpnService.ACTION_STOP
            })
            return
        }

        // If VPN permission is not granted - we must open the app (user consent screen).
        if (VpnService.prepare(this) != null) {
            openAppForConnect()
            return
        }

        val backend = prefs.getString(KeqdisVpnService.KEY_QS_LAST_BACKEND, KeqdisVpnService.VPN_BACKEND_XRAY)
            ?: KeqdisVpnService.VPN_BACKEND_XRAY
        val xrayPath = prefs.getString(KeqdisVpnService.KEY_QS_LAST_XRAY_CONFIG, null)
        val user = prefs.getString(KeqdisVpnService.KEY_QS_LAST_SOCKS_USERNAME, null)
        val pass = prefs.getString(KeqdisVpnService.KEY_QS_LAST_SOCKS_PASSWORD, null)
        val port = prefs.getInt(KeqdisVpnService.KEY_QS_LAST_SOCKS_PORT, 2080)
        val serverName = prefs.getString(KeqdisVpnService.KEY_QS_LAST_SERVER_NAME, null)
        val exc = prefs.getStringSet(KeqdisVpnService.KEY_QS_LAST_EXCLUDE_PACKAGES, emptySet())?.toList() ?: emptyList()
        val inc = prefs.getStringSet(KeqdisVpnService.KEY_QS_LAST_INCLUDE_PACKAGES, emptySet())?.toList() ?: emptyList()

        // If we do not have a valid "selected server snapshot" yet - fall back to the app.
        if (xrayPath.isNullOrBlank() || user.isNullOrBlank() || pass.isNullOrBlank()) {
            openAppForConnect()
            return
        }

        val intent = Intent(this, KeqdisVpnService::class.java).apply {
            action = KeqdisVpnService.ACTION_START
            putExtra(KeqdisVpnService.EXTRA_VPN_BACKEND, backend)
            putExtra(KeqdisVpnService.EXTRA_XRAY_CONFIG, xrayPath)
            putExtra("socks_port", port)
            putStringArrayListExtra("exclude_packages", ArrayList(exc))
            putStringArrayListExtra("include_packages", ArrayList(inc))
            putExtra(KeqdisVpnService.EXTRA_SOCKS_USERNAME, user)
            putExtra(KeqdisVpnService.EXTRA_SOCKS_PASSWORD, pass)
            if (!serverName.isNullOrBlank()) putExtra(KeqdisVpnService.EXTRA_SERVER_NAME, serverName)
        }

        if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
    }

    private fun openAppForConnect() {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ?.putExtra("action", "connect_from_notification")
            ?: Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                putExtra("action", "connect_from_notification")
            }

        // Collapse QS panel and open the app.
        if (Build.VERSION.SDK_INT >= 34) {
            // Android 14+ - startActivityAndCollapse(Intent) is forbidden, must use PendingIntent
            val pendingIntent = PendingIntent.getActivity(
                this,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            startActivityAndCollapse(pendingIntent)
        } else if (Build.VERSION.SDK_INT >= 24) {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(launchIntent)
        } else {
            startActivity(launchIntent)
        }
    }

    private fun updateTileFromPrefs() {
        if (Build.VERSION.SDK_INT < 24) return

        val status = getSharedPreferences(KeqdisVpnService.PREFS_QS, MODE_PRIVATE)
            .getString(KeqdisVpnService.KEY_QS_STATUS, "disconnected")
            ?.lowercase()
            ?: "disconnected"

        android.util.Log.d("KEQDIS_QS", "updateTileFromPrefs: status=$status")

        val tileObj = qsTile
        if (tileObj == null) {
            // Retry mechanism: schedule another attempt if qsTile is not available yet
            if (retryCount < MAX_RETRIES) {
                android.util.Log.d("KEQDIS_QS", "updateTileFromPrefs: qsTile is null, scheduling retry (${retryCount + 1}/$MAX_RETRIES)")
                retryHandler?.removeCallbacks(retryRunnable)
                retryHandler = Handler(Looper.getMainLooper())
                retryHandler?.postDelayed(retryRunnable, RETRY_DELAY_MS)
                retryCount++
            } else {
                android.util.Log.w("KEQDIS_QS", "updateTileFromPrefs: max retries reached, giving up")
                retryCount = 0
            }
            return
        }

        // Reset retry counter if we successfully got the tile
        retryCount = 0
        retryHandler?.removeCallbacks(retryRunnable)

        tileObj.label = "Keqdis"
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tileObj.icon = android.graphics.drawable.Icon.createWithResource(this, TILE_ICON_RES)
        }
        
        tileObj.state = when (status) {
            "connected", "running" -> Tile.STATE_ACTIVE
            "connecting", "starting" -> Tile.STATE_UNAVAILABLE
            else -> Tile.STATE_INACTIVE
        }
        android.util.Log.d("KEQDIS_QS", "updateTileFromPrefs: new tile.state=${tileObj.state}")
        tileObj.updateTile()
    }
}
