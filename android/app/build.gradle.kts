import java.util.Properties

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.google.gms:google-services:4.4.2")
        classpath("com.google.firebase:firebase-crashlytics-gradle:3.0.7")
    }
}

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

// google-services.json is gitignored — apply plugins only when the file exists locally
val googleServicesJson = file("google-services.json")
if (googleServicesJson.exists()) {
    apply(plugin = "com.google.gms.google-services")
    apply(plugin = "com.google.firebase.crashlytics")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "com.keqdroid.keqdroid"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.keqdroid.keqdroid"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            // Только arm64-v8a: реальные Android-устройства. x86_64 был нерабочим
            // для VPN (в jniLibs не было tun2socks/xray) — убран вместе с keqrnel.
            abiFilters += listOf("arm64-v8a")
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
            // `abiFilters` выше до чужих библиотек не достаёт: ML Kit из
            // mobile_scanner приносит libbarhopper_v3.so в AAR, и в APK
            // приезжали ВСЕ три её сборки — x86_64 на 5.9 МБ и armeabi-v7a на
            // 3.2 МБ поверх нужной arm64. Работать на этих архитектурах
            // приложению всё равно нечем: ядра собраны только под arm64.
            excludes += listOf(
                "**/x86/**",
                "**/x86_64/**",
                "**/armeabi-v7a/**",
            )
        }
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"].toString()
            keyPassword = keystoreProperties["keyPassword"].toString()
            storeFile = file(keystoreProperties["storeFile"].toString())
            storePassword = keystoreProperties["storePassword"].toString()
        }
    }

    buildTypes {
        // Профильная сборка подписывается тем же ключом, что и релизная.
        //
        // Иначе её невозможно поставить поверх установленного релиза
        // (INSTALL_FAILED_UPDATE_INCOMPATIBLE), а единственный выход — удалить
        // приложение вместе со всеми подписками и настройками. Профилировать
        // приходится именно на реальном устройстве с реальными данными, так
        // что цена «чистой» отладочной подписи здесь — потерянный аккаунт.
        maybeCreate("profile").signingConfig = signingConfigs.getByName("release")

        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.profileinstaller:profileinstaller:1.4.1")
    implementation("androidx.activity:activity-ktx:1.9.3")
}
