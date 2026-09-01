package com.keqdroid.keqdroid

import android.content.Context
import io.flutter.FlutterInjector
import java.io.File

// Copies bundled xray geo databases into [targetDir] (app filesDir).
// xray reads them via XRAY_LOCATION_ASSET when routing uses geoip:/geosite: rules.
//
// Extraction repeats whenever the bundled database changes. The old "skip if the
// file exists" check made every geo update dead on arrival: a device that had
// extracted geoip.dat once kept that copy forever, so codes added to the bundled
// base (geoip:telegram, geosite:refilter, ...) never appeared on device and the
// rules using them were silently dropped before connecting.
//
// Freshness is tracked by a stamp file holding a fingerprint per database rather
// than by comparing sizes directly: the stamp is what we actually extracted, so
// an unexpected fingerprint can never put us in a re-extract-every-start loop
// (that would mean copying ~25 MB on each VPN start).
object XrayGeoAssets {
    // Target file name -> Flutter asset it is extracted from. They differ:
    // geoip ships trimmed to the codes the app can emit on its own (0.6 MB out
    // of 23.5), and anything else a user's rule needs is downloaded on top of
    // it at runtime. geosite ships whole. See the pubspec asset list.
    private val geoFiles = mapOf(
        "geoip.dat" to "assets/geo/geoip-lite.dat",
        "geosite.dat" to "assets/bin/windows/geosite.dat",
    )
    private const val stampName = "geo_assets.stamp"

    fun ensure(context: Context, targetDir: File) {
        val loader = FlutterInjector.instance().flutterLoader()
        val assetManager = context.assets
        val stampFile = File(targetDir, stampName)
        val previous = readStamp(stampFile)
        val current = mutableMapOf<String, String>()

        for ((name, asset) in geoFiles) {
            val out = File(targetDir, name)
            val assetKey = loader.getLookupKeyForAsset(asset)
            val fingerprint = fingerprint(context, assetKey)
            current[name] = fingerprint

            if (out.exists() && out.length() > 0L && previous[name] == fingerprint) {
                continue
            }

            // Не затирать базу БОГАЧЕ вшитой.
            //
            // geoip мы теперь поставляем урезанным, а поверх него ложится
            // полная база — либо скачанная пользователем, либо оставшаяся от
            // версии, которая возила полную в APK. Отпечаток у неё не совпадёт
            // ни с чем, и обычная логика «не совпало — перезаписать» откатила
            // бы человека с полной базы на урезанную при первом же запуске.
            //
            // Сравниваем размеры: файл больше ассета — значит в нём заведомо
            // больше кодов, и трогать его нельзя.
            val assetSize = assetSize(context, assetKey)
            if (out.exists() && assetSize > 0L && out.length() > assetSize) {
                android.util.Log.i(
                    "KEQDIS",
                    "Keeping richer geo base $name (${out.length()} bytes on disk " +
                        "vs $assetSize bundled)",
                )
                // В штамп кладём отпечаток вшитого ассета: иначе на каждом
                // старте сюда будет заходить заново.
                continue
            }

            try {
                assetManager.open(assetKey).use { input ->
                    out.outputStream().use { output -> input.copyTo(output) }
                }
                android.util.Log.i(
                    "KEQDIS",
                    "Extracted xray geo asset $name (${out.length()} bytes, $fingerprint)",
                )
            } catch (e: Exception) {
                android.util.Log.w(
                    "KEQDIS",
                    "Xray geo asset $name not bundled - geoip:/geosite: routing may fail",
                )
                // Не помечаем как извлечённый: на следующем старте попробуем снова.
                current.remove(name)
            }
        }

        writeStamp(stampFile, current)
    }

    // Identity of the bundled database: its uncompressed size when the asset can
    // report it (AssetInputStream.available() gives the remaining uncompressed
    // bytes), otherwise the app version code - a rebuilt database always ships
    // with a new version, so that is a safe fallback.
    private fun fingerprint(context: Context, assetKey: String): String {
        val size = assetSize(context, assetKey)
        if (size > 0L) return "size:$size"
        return "app:${appVersionCode(context)}"
    }

    // Распакованный размер ассета: AssetInputStream.available() отдаёт остаток
    // в байтах, то есть для нетронутого потока — весь файл.
    private fun assetSize(context: Context, assetKey: String): Long =
        runCatching {
            context.assets.open(assetKey).use { it.available().toLong() }
        }.getOrDefault(-1L)

    private fun readStamp(stampFile: File): Map<String, String> =
        runCatching {
            stampFile.readLines()
                .mapNotNull { line ->
                    val idx = line.indexOf('=')
                    if (idx <= 0) null else line.substring(0, idx) to line.substring(idx + 1)
                }
                .toMap()
        }.getOrDefault(emptyMap())

    private fun writeStamp(stampFile: File, entries: Map<String, String>) {
        runCatching {
            stampFile.writeText(entries.entries.joinToString("\n") { "${it.key}=${it.value}" })
        }
    }

    private fun appVersionCode(context: Context): Long =
        runCatching {
            context.packageManager
                .getPackageInfo(context.packageName, 0)
                .longVersionCode
        }.getOrDefault(0L)
}
