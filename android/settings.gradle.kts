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
    // AGP 9 работает (проверено debug и release), но пока в режиме
    // совместимости: `android.builtInKotlin=false` в gradle.properties.
    // Снять флаг мешает ровно один плагин — dynamic_color 1.9.0: он тащит в
    // свой подпроект собственный buildscript-classpath с AGP 8.13.1 и KGP, и
    // при включённом Built-in Kotlin падает на применении com.android.library.
    // Требует Gradle 9.1+, см. gradle-wrapper.properties.
    id("com.android.application") version "9.0.0" apply false
    // apply false: сам app KGP НЕ применяет (Built-in Kotlin, Flutter 3.44+).
    // Пин версии нужен, пока живы плагины на легаси-пути (mobile_scanner и
    // workmanager_android применяют KGP условно, только при AGP < 9 или
    // выключенном Built-in Kotlin) — иначе они затягивают старый Kotlin.
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
