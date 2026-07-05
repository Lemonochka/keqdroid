pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // AGP 9 пока нельзя: плагины (dynamic_color, mobile_scanner, workmanager и
    // сам flutter_plugin_android_lifecycle) ещё применяют KGP и падают под ним.
    id("com.android.application") version "8.11.1" apply false
    // apply false: сам app KGP НЕ применяет (Built-in Kotlin, Flutter 3.44+).
    // Пин версии нужен, иначе плагины, всё ещё применяющие KGP (dynamic_color,
    // mobile_scanner, workmanager_android), затягивают старый Kotlin 2.0.0.
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
