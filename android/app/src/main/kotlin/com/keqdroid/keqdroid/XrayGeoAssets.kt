package com.keqdroid.keqdroid

import android.content.Context
import io.flutter.FlutterInjector
import java.io.File

// Copies bundled xray geo databases into [targetDir] (app filesDir).
// xray reads them via XRAY_LOCATION_ASSET when routing uses geoip:/geosite: rules.
object XrayGeoAssets {
    private val geoFiles = listOf("geoip.dat", "geosite.dat")
    private const val assetDir = "assets/bin/windows"

    fun ensure(context: Context, targetDir: File) {
        val loader = FlutterInjector.instance().flutterLoader()
        val assetManager = context.assets
        for (name in geoFiles) {
            val out = File(targetDir, name)
            if (out.exists() && out.length() > 0L) continue
            val assetKey = loader.getLookupKeyForAsset("$assetDir/$name")
            try {
                assetManager.open(assetKey).use { input ->
                    out.outputStream().use { output -> input.copyTo(output) }
                }
                android.util.Log.i(
                    "KEQDIS",
                    "Extracted xray geo asset $name (${out.length()} bytes)",
                )
            } catch (e: Exception) {
                android.util.Log.w(
                    "KEQDIS",
                    "Xray geo asset $name not bundled — geoip:/geosite: routing may fail",
                )
            }
        }
    }
}
