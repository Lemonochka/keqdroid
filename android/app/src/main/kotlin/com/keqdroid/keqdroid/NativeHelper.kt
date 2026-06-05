package com.keqdroid.keqdroid

object NativeHelper {
    init { System.loadLibrary("keqdis_native") }

    @JvmStatic
    external fun startTun2Socks(tunFd: Int, binPath: String, proxyUrl: String): Int

    @JvmStatic
    external fun startXray(binPath: String, configPath: String, assetDir: String): Int
}
