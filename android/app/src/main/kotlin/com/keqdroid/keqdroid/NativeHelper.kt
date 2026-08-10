package com.keqdroid.keqdroid

object NativeHelper {
    init { System.loadLibrary("keqdis_native") }

    // logLevel: уровень логов tun2socks. На `info` он печатает каждое соединение
    // строкой `[TCP] <сокет приложения> <-> <назначение>` — единственное место,
    // где виден исходный сокет; в лог xray попадает уже наш собственный, со
    // стороны SOCKS. logPath: полный путь к файлу логов, пустая строка —
    // логирование в файл выключено и пайп не создаётся вовсе.
    @JvmStatic
    external fun startTun2Socks(
        tunFd: Int,
        binPath: String,
        proxyUrl: String,
        logLevel: String,
        logPath: String,
    ): Int

    // logName: имя файла логов ядра внутри assetDir (filesDir). Пустая строка —
    // файловое логирование выключено (используется ping/спидтестом).
    @JvmStatic
    external fun startXray(binPath: String, configPath: String, assetDir: String, logName: String): Int
}
