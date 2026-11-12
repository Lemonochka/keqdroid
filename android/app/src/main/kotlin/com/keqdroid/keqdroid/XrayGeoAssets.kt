package com.keqdroid.keqdroid

import android.content.Context
import androidx.core.content.pm.PackageInfoCompat
import java.io.File

// распаковка повторяется при каждой смене вшитой базы: прежняя проверка есть файл оставляла первую копию навсегда,
// и новые коды (geoip:telegram, geosite:refilter) молча выпадали. в штампе отпечаток того, что распаковано,
// поэтому неожиданный отпечаток не зациклит распаковку 25 МБ на каждом старте
object XrayGeoAssets {
    // geoip вшит урезанным (0.6 МБ из 23.5), остальное докачивается по правилам. geosite целиком
    private val geoFiles = mapOf(
        "geoip.dat" to "assets/geo/geoip-lite.dat",
        "geosite.dat" to "assets/bin/windows/geosite.dat",
    )
    private const val stampName = "geo_assets.stamp"

    // путь сами, не через FlutterLoader.getLookupKeyForAsset: без поднятого Flutter он падает NPE,
    // а сервис стартует и без Flutter (плитка после убийства, подъём системой)
    private const val flutterAssetsDir = "flutter_assets"

    fun ensure(context: Context, targetDir: File) {
        val assetManager = context.assets
        val stampFile = File(targetDir, stampName)
        val previous = readStamp(stampFile)
        val current = mutableMapOf<String, String>()

        for ((name, asset) in geoFiles) {
            val out = File(targetDir, name)
            val assetKey = "$flutterAssetsDir/$asset"
            val fingerprint = fingerprint(context, assetKey)
            current[name] = fingerprint

            if (geoUpToDate(out.lengthIfExists(), previous[name], fingerprint)) {
                continue
            }

            val assetSize = assetSize(context, assetKey)
            if (keepsRicherBase(out.lengthIfExists(), assetSize)) {
                NativeLog.i(
                    "KEQDIS",
                    "Keeping richer geo base $name (${out.length()} bytes on disk " +
                        "vs $assetSize bundled)",
                )
                // в штамп отпечаток вшитого, иначе заходили бы сюда на каждом старте
                continue
            }

            try {
                assetManager.open(assetKey).use { input ->
                    out.outputStream().use { output -> input.copyTo(output) }
                }
                NativeLog.i(
                    "KEQDIS",
                    "Extracted xray geo asset $name (${out.length()} bytes, $fingerprint)",
                )
            } catch (e: Exception) {
                NativeLog.w(
                    "KEQDIS",
                    "Xray geo asset $name not bundled - geoip:/geosite: routing may fail",
                )
                // не отмечаем, попробуем на следующем старте
                current.remove(name)
            }
        }

        writeStamp(stampFile, current)
    }

    private fun File.lengthIfExists(): Long? = if (exists()) length() else null

    internal fun geoUpToDate(outLength: Long?, previous: String?, fingerprint: String): Boolean =
        outLength != null && outLength > 0L && previous == fingerprint

    // базу богаче вшитой не затираем: полная (скачанная или от старой версии) иначе откатилась бы на урезанную.
    // файл больше ассета значит кодов в нём больше
    internal fun keepsRicherBase(outLength: Long?, assetSize: Long): Boolean =
        outLength != null && assetSize > 0L && outLength > assetSize

    private fun fingerprint(context: Context, assetKey: String): String =
        fingerprintOf(assetSize(context, assetKey)) { appVersionCode(context) }

    // размер распакованного ассета, иначе versionCode: пересобранная база всегда едет с новой версией
    internal fun fingerprintOf(assetSize: Long, versionCode: () -> Long): String =
        if (assetSize > 0L) "size:$assetSize" else "app:${versionCode()}"

    // available() у нетронутого потока это весь файл
    private fun assetSize(context: Context, assetKey: String): Long =
        runCatching {
            context.assets.open(assetKey).use { it.available().toLong() }
        }.getOrDefault(-1L)

    private fun readStamp(stampFile: File): Map<String, String> =
        runCatching { parseStamp(stampFile.readLines()) }.getOrDefault(emptyMap())

    private fun writeStamp(stampFile: File, entries: Map<String, String>) {
        runCatching { stampFile.writeText(formatStamp(entries)) }
    }

    internal fun parseStamp(lines: List<String>): Map<String, String> =
        lines.mapNotNull { line ->
            val idx = line.indexOf('=')
            if (idx <= 0) null else line.substring(0, idx) to line.substring(idx + 1)
        }.toMap()

    internal fun formatStamp(entries: Map<String, String>): String =
        entries.entries.joinToString("\n") { "${it.key}=${it.value}" }

    private fun appVersionCode(context: Context): Long =
        runCatching {
            PackageInfoCompat.getLongVersionCode(
                context.packageManager.getPackageInfo(context.packageName, 0)
            )
        }.getOrDefault(0L)
}
