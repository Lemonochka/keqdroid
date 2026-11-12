package com.keqdroid.keqdroid

import org.json.JSONObject

// JSONStringer экранирует слэш, а такого escape go-yaml не знает (scannerc.go): yaml: found unknown escape character.
// слэши есть в любом конфиге, поэтому ломался любой. \\ копируем парой, чтобы следующий слэш не сошёл за экранированный
internal fun yamlSafeJson(json: String): String {
    if (!json.contains("\\/")) return json
    val out = StringBuilder(json.length)
    var i = 0
    while (i < json.length) {
        val c = json[i]
        if (c == '\\' && i + 1 < json.length) {
            val next = json[i + 1]
            if (next == '/') out.append('/') else out.append(c).append(next)
            i += 2
            continue
        }
        out.append(c)
        i++
    }
    return out.toString()
}

internal class SessionLogLevel(val config: String, val floor: Int)

// mihomo строку TUN поднялся пишет на info, и при warning подключение ждало её четыре секунды. без поля он и так на info
internal fun mihomoSessionLogLevel(text: String): SessionLogLevel? {
    val levels = listOf("debug", "info", "warning", "error", "silent")
    val value = (Regex(""""log-level"\s*:\s*"(\w+)"""").find(text)
        ?: Regex("""(?m)^log-level:\s*['"]?(\w+)""").find(text))
        ?.groups?.get(1)
        ?: return null
    val chosen = levels.indexOf(value.value.lowercase())
    if (chosen <= levels.indexOf("info")) return null
    return SessionLogLevel(text.replaceRange(value.range, "info"), chosen)
}

internal fun xrayLogFloor(loglevel: String): Int? {
    val levels = listOf("debug", "info", "warning", "error", "none")
    val chosen = levels.indexOf(loglevel.lowercase())
        .let { if (it < 0) levels.indexOf("warning") else it }
    return chosen.takeIf { it > levels.indexOf("info") }
}

internal fun xraySessionLogLevel(text: String): SessionLogLevel? {
    val json = JSONObject(text)
    val log = json.optJSONObject("log") ?: JSONObject().also { json.put("log", it) }
    // без поля xray пишет с warning
    val chosen = xrayLogFloor(log.optString("loglevel", "warning")) ?: return null
    log.put("loglevel", "info")
    return SessionLogLevel(json.toString(), chosen)
}

internal fun xrayHasTunInbound(text: String): Boolean {
    val inbounds = JSONObject(text).optJSONArray("inbounds") ?: return false
    for (i in 0 until inbounds.length()) {
        if (inbounds.optJSONObject(i)?.optString("protocol") == "tun") return true
    }
    return false
}

// MTU fd-устройства ядру спросить неоткуда, а расхождение с интерфейсом это пакеты, которые ядро ОС отбросит при записи в tun
internal fun xrayConfigWithTunMtu(text: String): String {
    val root = JSONObject(text)
    val inbounds = root.optJSONArray("inbounds")
        ?: throw IllegalStateException("xray config has no inbounds")
    for (i in 0 until inbounds.length()) {
        val inbound = inbounds.optJSONObject(i) ?: continue
        if (inbound.optString("protocol") != "tun") continue
        val settings = inbound.optJSONObject("settings") ?: JSONObject()
        settings.put("mtu", KeqdisVpnService.TUN_MTU)
        inbound.put("settings", settings)
        return root.toString()
    }
    throw IllegalStateException("xray config has no tun inbound")
}

internal fun mihomoConfigWithTunFd(text: String, tunFd: Int): String {
    val root = JSONObject(text)
    val tun = root.optJSONObject("tun")
        ?: throw IllegalStateException(
            "mihomo config has no `tun` section — the core cannot take over " +
                "the tunnel without it"
        )
    tun.put("file-descriptor", tunFd)
    tun.put("mtu", KeqdisVpnService.TUN_MTU)
    root.put("tun", tun)
    return yamlSafeJson(root.toString())
}

// файл обнуляется по размеру: если он стал короче метки, новое в нём всё
internal fun textSince(bytes: ByteArray, from: Long): String {
    val start = if (from in 0..bytes.size.toLong()) from.toInt() else 0
    return String(bytes, start, bytes.size - start, Charsets.UTF_8)
}

internal fun logTail(lines: List<String>, maxLines: Int, maxChars: Int): String {
    val tail = lines
        .filter { it.isNotBlank() }
        .takeLast(maxLines)
        .joinToString("\n")
        .takeLast(maxChars)
    return if (tail.isBlank()) "" else "\n$tail"
}

internal fun mihomoTunFailure(log: String): String? =
    log.lineSequence()
        .lastOrNull { it.contains(KeqdisVpnService.MIHOMO_TUN_FAILED) }
        ?.substringAfter(KeqdisVpnService.MIHOMO_TUN_FAILED)
        ?.trim()
        ?.take(300)

internal fun mihomoApiOf(controller: String, secret: String): Pair<Int, String>? {
    val port = controller.substringAfterLast(':', "").toIntOrNull() ?: 0
    return if (port <= 0 || secret.isEmpty()) null else port to secret
}
