package com.keqdroid.keqdroid

object NativeHelper {
    init { System.loadLibrary("keqdis_native") }

    @JvmStatic
    external fun startTun2Socks(tunFd: Int, binPath: String, proxyUrl: String): Int

    // logName: имя файла логов ядра внутри assetDir (filesDir). Пустая строка —
    // файловое логирование выключено (используется ping/спидтестом).
    @JvmStatic
    external fun startXray(binPath: String, configPath: String, assetDir: String, logName: String): Int
}
