# Onboarding: окружение, сборка, запуск, тесты

## 1. Что нужно установить

| Инструмент | Версия | Заметки |
|------------|--------|---------|
| **Flutter SDK** | stable, 3.44+ (Dart `^3.11.3` — см. `pubspec.yaml`) | основной тулчейн |
| **Android Studio** + Android SDK | compileSdk 36 | minSdk = 24 (дефолт Flutter, `android/app/build.gradle.kts` его не переопределяет) |
| **JDK** | 17+ | jvmTarget в Gradle — 17; JDK из Android Studio (21) тоже подходит |
| **Visual Studio** + «Desktop development with C++» | 2022 или новее | на VS 2026 (18.x) собирается: для новых STL в `windows/CMakeLists.txt` уже стоит `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS` |
| **WSL + Ubuntu** | — | сборка Linux-таргета (из Windows-SDK её не сделать) |
| **gh CLI** | — | только для публикации релизов |

`flutter doctor` покажет, чего не хватает. Ругань на github handshake при активном
HTTP-прокси — известная особенность окружения, сборке не мешает.

## 2. Первый запуск

```bash
flutter pub get
```

`pub get` заодно генерирует локализации (`flutter: generate: true` в pubspec) —
`lib/l10n/app_localizations*.dart` появятся сами.

## 3. Сборка и запуск

### Android

```bash
flutter run                       # debug на устройстве/эмуляторе
flutter build apk --release
```

- При первом подключении система спросит разрешение VPN.
- Нативные ядра лежат как `jniLibs` (`android/app/src/main/jniLibs/<abi>/*.so`), а не как
  Flutter-ассеты — иначе десктопные бинарники раздували APK (см. [PITFALLS.md](PITFALLS.md)).
- Crashlytics работает только на Android и только в release. Без `google-services.json`
  приложение собирается и работает, просто без репортинга крэшей.
- После обновления версии Kotlin в `android/settings.gradle.kts` первая сборка может упасть
  с бессмысленным «Unresolved reference» внутри чужого плагина — это протухший
  инкрементальный кэш, лечится `flutter clean` (подробнее в [PITFALLS.md](PITFALLS.md)).

### Windows

```bash
flutter build windows --release
# результат: build\windows\x64\runner\Release\keqdroid.exe + DLL + ядра
```

- Список Windows-плагинов (`windows/flutter/app_plugins.cmake` +
  `app_plugin_registrant.cc`) закоммичен уже без Firebase (он Android-only и ломает
  линковку). Обычная сборка работает сразу; `tool/sync_windows_plugins.ps1` перезапускай
  **только после добавления/удаления плагинов** в pubspec.
- Ядра из `assets/bin/windows/` CMake кладёт рядом с exe. В поставке — `keqrnel.exe`,
  `wireproxy.exe`, `wintun.dll`, `geoip.dat`, `geosite.dat`. Отдельных `xray.exe` /
  `sing-box.exe` в бандле **нет**: дефолтное ядро — keqrnel, режим `chain` на Windows
  заработает только если докинуть эти бинарники самостоятельно
  ([`assets/bin/windows/README.md`](../assets/bin/windows/README.md)).
- TUN-режим требует запуска от администратора (sing-box/keqrnel создаёт wintun-адаптер),
  Proxy работает без прав.

### Linux (Debian/Arch, x86_64)

Только на нативном Linux или в WSL. Скриптов два, роли разные:

```bash
# первый раз: ставит GTK-тулчейн и нативный Linux-Flutter, потом собирает
wsl -e bash /mnt/c/Users/<ты>/StudioProjects/keqdroid/tool/build_linux_wsl.sh

# повторные сборки/релиз (когда /opt/flutter в WSL уже есть): rsync проекта
# на Linux-ФС + сборка + упаковка + копирование артефактов в release/
wsl -d Ubuntu -u root bash /mnt/c/Users/<ты>/StudioProjects/keqdroid/release/wsl_build_linux.sh
```

- Сборка на `/mnt/c` (drvfs) не работает: медленно и ломаются симлинки Flutter — поэтому
  релизный скрипт сначала копирует проект в `/root/keqdroid`.
- Ядра — в `assets/bin/linux/` (там лежит полный набор: keqrnel, xray, sing-box, wireproxy).
- Proxy работает без root; TUN запрашивает root через `pkexec` при подключении.
- Упаковка: `release/build_linux.sh` делает tar.gz + deb + AppImage;
  `tool/package_linux.sh` — то же + `PKGBUILD` для Arch.

## 4. Тесты и анализ

```bash
flutter analyze                                # должно быть «No issues found!»
flutter test                                   # весь набор (~24 файла)
flutter test test/utils/config_gen_test.dart   # один файл
```

Тесты зеркалят `lib/`: `test/utils/` — генераторы конфигов и парсеры, `test/services/` —
storage/подписки/апдейтер/пинг, `test/models/`, `test/tunnel/`, `test/widgets/`,
`test/providers/`. Фикстуры — в `test/helpers/` (`pump_app.dart`, `test_storage.dart`).

Чистый analyze и зелёные тесты — обязательное условие любого PR: и то и другое ловит
реальные регрессии, а не для галочки.

## 5. Пересборка нативных ядер

Обычно не нужна — собранные ядра уже лежат в `assets/bin/` и `jniLibs/`. Когда обновляешь
версию ядра:

| Скрипт | Что собирает |
|--------|--------------|
| `tool/build_amneziawg.ps1` | AmneziaWG-ядро (`wireproxy-awg`) для Windows |
| `tool/build_linux_native.sh` | Linux-бандл + ядра на нативном Linux |
| `tool/fetch_xray_geo.ps1` | свежие `geoip.dat` / `geosite.dat` |
| `tools/amneziawg_android/` | AmneziaWG `.so` под Android |

`xray.exe`/`wireproxy.exe` под Windows собирай **unstripped** и не запускай из `%TEMP%` —
иначе Defender считает их угрозой (см. [PITFALLS.md](PITFALLS.md)).

## 6. Локализация (en / ru / de / zh)

Источник истины — ARB: `lib/l10n/app_en.arb` (база) и `app_ru/de/zh.arb`. Добавил строку —
добавь её **во все четыре** файла, иначе на «забытом» языке будет пустой ключ. Генерация
подтягивается сама при `flutter pub get` / `flutter run` (или вручную `flutter gen-l10n`).
`app_localizations*.dart` руками не редактируются.

## 7. Релиз

```powershell
# APK + Windows-zip + SHA-256 → release\<версия>\
powershell -ExecutionPolicy Bypass -File tool\make_release.ps1

# то же + публикация GitHub-релиза (нужен gh CLI)
powershell -ExecutionPolicy Bypass -File tool\make_release.ps1 -Publish -NotesFile notes.md
```

Правила, которые нельзя нарушать:

- версия и тег `vX.Y.Z` берутся из `version:` в `pubspec.yaml` — это единственный источник;
- **каждый** ассет несёт сайдкар `<имя>.sha256` (ASCII без BOM): апдейтер fail-closed и без
  совпавшего хеша обновление не поставит. `make_release.ps1` и `release/gen_sha256.ps1`
  генерируют сайдкары сами; при ручной заливке — не забудь;
- имена ассетов фиксированные: `keqdroid-<версия>-android.apk`,
  `keqdroid-windows-x64-<версия>.zip` (именно такой порядок слов),
  `keqdroid-<версия>-linux-x64.tar.gz`, `keqdroid_<версия>_amd64.deb`,
  `keqdroid-<версия>-x86_64.AppImage`;
- APK перед копированием проверяй через `aapt dump badging | grep versionName` — после
  упавшей сборки в `build/` остаётся **старый** APK от прошлого успеха.
