# Правила R8 для релизной сборки.
#
# Здесь только то, чего не знают остальные источники правил. Их четыре:
# proguard-android-optimize.txt (native-методы, enum), flutter_proguard_rules.pro
# (его добавляет плагин Flutter), правила внутри самих библиотек (WorkManager,
# Room, CameraX, ML Kit носят их в своих AAR) и AAPT, который
# сохраняет всё, что названо в AndroidManifest.xml.
#
# Раньше файл держал почти весь код: сохранял любой класс с публичным
# конструктором, Firebase и сервисы Google целиком, методы с именами вроде
# toJson/fromJson во всех классах и отключал оптимизацию. Обоснованием был
# «StackOverflow при разборе подписок», но разбор подписок написан на Dart, а
# R8 видит только Java/Kotlin — правила на имена Dart-методов не делали ничего.
# Итог был 16 000 классов в APK.
#
# Нативный код (src/main/cpp) в Java не ходит: FindClass/GetMethodID там нет,
# связь только через native-методы, а их имена сохраняет стандартное правило.
# Рефлексии в нашем Kotlin тоже нет.

# Имена классов не переименовываются: WorkManager хранит имя класса фоновой
# задачи в своей базе, и уже запланированная задача после переименования не
# нашла бы его. Одинаковый код R8 при этом всё равно склеивает, и в сырой трассе
# бывают чужие кадры.
-dontobfuscate
-keepattributes SourceFile,LineNumberTable

# Отложенные компоненты Flutter ссылаются на Play Core, которого в приложении
# нет; без этого R8 останавливает сборку на отсутствующих классах.
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
