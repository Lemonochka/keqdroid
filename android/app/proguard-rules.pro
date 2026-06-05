# ═══════════════════════════════════════════════════════════════════════════════
# FLUTTER & ANDROID FRAMEWORK
# ═══════════════════════════════════════════════════════════════════════════════

# Keep Flutter entry points and plugin registrant.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.** { *; }

# Keep app entry points referenced from AndroidManifest.xml.
-keep class com.keqdroid.keqdroid.MainActivity { *; }
-keep class com.keqdroid.keqdroid.KeqdisVpnService { *; }

# Keep native method signatures.
-keepclasseswithmembernames class * {
    native <methods>;
}

# ═══════════════════════════════════════════════════════════════════════════════
# SUBSCRIPTION PARSING - CRITICAL FOR STACK OVERFLOW FIX
# ═══════════════════════════════════════════════════════════════════════════════

# [FIX-STACK-OVERFLOW-RELEASE] Защищаем критические методы парсинга от R8 оптимизации.
# R8 может встроить (inline) методы парсинга и вызвать stack overflow.

-keep class com.keqdroid.keqdroid.services.SubscriptionService {
    *** _parseBody(...);
    *** _extractConfigsFromHtml(...);
    *** _parseBodyNoRecursion(...);
    *** _extractUrisDirectly(...);
    *** _collectTextVariants(...);
    *** _walkStructured(...);
    *** _tryDecodeBase64Flexible(...);
    *** _extractUriLinks(...);
    *** _tryParseFromErrorResponse(...);
    *** fetchRaw(...);
    *** updateSubscription(...);
    *** updateAll(...);
    *** getDueForUpdate(...);
}

# Отключаем inline оптимизацию для методов со сложной логикой
-optimizations !method/inlining/*

# ═══════════════════════════════════════════════════════════════════════════════
# JSON SERIALIZATION & DATA MODELS
# ═══════════════════════════════════════════════════════════════════════════════

# [FIX-STACKOVERLOW] Keep ALL model classes and their members completely intact.
# R8 StackOverflow на подписках происходит из-за удаления полей/конструкторов.
# Dartные модели (Subscription, ServerItem, AppSettings) требуют полной защиты.
-keep class com.keqdroid.keqdroid.models.** { *; }
-keep class com.keqdroid.keqdroid.Subscription { *; }
-keep class com.keqdroid.keqdroid.ServerItem { *; }
-keep class com.keqdroid.keqdroid.AppSettings { *; }

# Защита всех методов - включая copyWith, toJson, fromJson, toString
-keepclassmembers class ** {
    *** toJson(...);
    *** fromJson(...);
    *** copyWith(...);
    java.lang.String toString();
    boolean equals(java.lang.Object);
    int hashCode();
}

# JSON annotation support
-keep class com.google.gson.** { *; }
-keep class com.fasterxml.jackson.** { *; }
-dontwarn com.google.gson.**
-dontwarn com.fasterxml.jackson.**

# ═══════════════════════════════════════════════════════════════════════════════
# ENUM SUPPORT
# ═══════════════════════════════════════════════════════════════════════════════

-keepclassmembers enum * {
    public static *[] values();
    public static * valueOf(java.lang.String);
    public static * $VALUES;
    public * $ENUM$VALUES;
}

# ═══════════════════════════════════════════════════════════════════════════════
# DISABLE R8 OPTIMIZATIONS THAT CAUSE StackOverflow
# ═══════════════════════════════════════════════════════════════════════════════

# Отключаем аггрессивную оптимизацию, которая может привести к infinite loops
-optimizations !code/simplification/arithmetic,!code/simplification/cast,!field/*,!class/merging/*
-optimizationpasses 3

# ═══════════════════════════════════════════════════════════════════════════════
# FIREBASE & GOOGLE PLAY
# ═══════════════════════════════════════════════════════════════════════════════

-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# ═══════════════════════════════════════════════════════════════════════════════
# PREVENT RECURSIVE OPTIMIZATION ISSUES
# ═══════════════════════════════════════════════════════════════════════════════

# Preserve static methods (workmanager, method channels, etc.)
-keepclasseswithmembernames class * {
    public static <methods>;
}

# Keep constructors for all classes (essential for reflection/deserialization)
-keepclasseswithmembers class * {
    public <init>(...);
}

# ═══════════════════════════════════════════════════════════════════════════════
# ADDITIONAL UTF-8 & BASE64 PROTECTION
# ═══════════════════════════════════════════════════════════════════════════════

# [ADDITIONAL-FIX] Дополнительная защита для UTF-8 и Base64 операций
-keep class java.util.Base64 { *; }
-keep class java.util.Base64$Decoder { *; }
-keep class java.util.Base64$Encoder { *; }
-keep class java.nio.charset.StandardCharsets { *; }

# Максимально сокращаем оптимизацию чтобы избежать Stack Overflow
-optimizationpasses 1
-dontoptimize

