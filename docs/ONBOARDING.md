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
- Ядра из `assets/bin/windows/` CMake кладёт рядом с exe: `keqrnel.exe`,
  `wireproxy.exe`, `wintun.dll`, `geoip.dat`, `geosite.dat`
  ([`assets/bin/windows/README.md`](../assets/bin/windows/README.md)). Отдельные
  `xray.exe` / `sing-box.exe` не нужны — keqrnel несёт оба движка внутри.
- TUN-режим требует запуска от администратора (keqrnel создаёт wintun-адаптер),
  Proxy работает без прав.

### Linux (Debian/Arch, x86_64)

Только на нативном Linux или в WSL. Скриптов два, роли разные:

```bash
# сборка: ставит GTK-тулчейн и нативный Linux-Flutter (идемпотентно), потом
# flutter build linux --release
wsl -e bash /mnt/c/Users/<ты>/StudioProjects/keqdroid/tool/build_linux_wsl.sh

# упаковка готового бандла: tar.gz + deb + AppImage + PKGBUILD + сайдкары
wsl -e bash /mnt/c/Users/<ты>/StudioProjects/keqdroid/tool/package_linux.sh
```

- Из Git Bash так не запускай: он превратит `/mnt/c/...` в виндовый путь ещё до `wsl`,
  и скрипт не найдётся. Запускай из PowerShell (или ставь `MSYS_NO_PATHCONV=1`).
- Оба скрипта работают прямо в репозитории на `/mnt/c`, копий на Linux-ФС не делают —
  поэтому Linux-сборку нельзя гонять параллельно с Windows или Android.
- Ядра — в `assets/bin/linux/`: `keqrnel`, `wireproxy` и geo-базы. CMake кладёт их
  рядом с бинарём бандла, не в `flutter_assets`.
- Proxy работает без root; TUN запрашивает root через `pkexec` при подключении.

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
| `tool/build_amneziawg.ps1` | AmneziaWG-ядра: `wireproxy` (Windows + Linux) и `libwg-go.so` (Android) |
| `tool/build_mihomo.ps1` | `libmihomo.so` (второе прокси-ядро Android), с патчами из `tool/patches/` |
| `tool/build_linux_native.sh` | Linux-бандл + ядра на нативном Linux |
| `tool/fetch_xray_geo.ps1` | свежие `geoip.dat` / `geosite.dat` |

`keqrnel` скрипта не имеет — собирается из [своего
репозитория](https://github.com/Lemonochka/keqrnel) обычным `go build`, по бинарю на
платформу, в `assets/bin/windows/` и `assets/bin/linux/`:

```bash
go build -trimpath -buildvcs=false -tags with_gvisor -o keqrnel.exe ./cmd/keqrnel
GOOS=linux GOARCH=amd64 go build -trimpath -buildvcs=false -tags with_gvisor -o keqrnel ./cmd/keqrnel
```

**`with_gvisor` обязателен.** Стек TUN — пользовательская настройка, и без этого тега
в ядре нет ни `gvisor`, ни `mixed`, а с ними и full-cone NAT. Забытый тег виден по
размеру: бинарь худеет примерно на 3 МБ.

`libxray.so` под Android — это официальный xray для `android/arm64`, переименованный.
Пересобирается из того же репозитория xray-ядра, но уже с NDK:

```bash
CGO_ENABLED=1 GOOS=android GOARCH=arm64 GOARM64=v8.0 \
  CC=$NDK/toolchains/llvm/prebuilt/windows-x86_64/bin/aarch64-linux-android21-clang.cmd \
  go build -trimpath -buildvcs=false -gcflags=all=-l=4 \
  -ldflags="-s -w -checklinkname=0" -o libxray.so github.com/xtls/xray-core/main
```

`-checklinkname=0` без вариантов: зависимость `anet` (чинит сломанный
`net.Interfaces()` на Android) лезет в `net.zoneCache` из stdlib, а go1.26 такие
`go:linkname` запрещает — без флага падает линковка.

`keqrnel.exe`/`wireproxy.exe` под Windows собирай **unstripped** и не запускай из
`%TEMP%` — иначе Defender считает их угрозой (см. [PITFALLS.md](PITFALLS.md)).
Android-бинарь, наоборот, стрипается (`-s -w`), как это делает апстрим.

`libmihomo.so` — второе прокси-ядро под Android, между ним и `libxray.so`
пользователь выбирает на экране «О приложении». Собирается скриптом, а не руками:

```powershell
powershell -File tool/build_mihomo.ps1
```

**Это не сток апстрима.** Скрипт накатывает `tool/patches/mihomo-*.patch` и падает,
если патч не лёг, — молча непропатченное ядро выглядит здоровым и отваливается
только на отдельных серверах. Что чинит каждый патч и что при обновлении держать
в согласии, написано в шапке самого патча. Сейчас там один: mihomo зашивает в
ClientHello версию REALITY-клиента `1.8.2`, и сервер с поднятым `minClient`
отдаёт настоящий сертификат маскировочного домена вместо своего — клиент видит
`REALITY authentication failed`, хотя ключи верные (см. [PITFALLS.md](PITFALLS.md)).

AmneziaWG собирается одним скриптом на все три платформы:

```powershell
powershell -File tool/build_amneziawg.ps1                       # wireproxy (win+linux) + libwg-go.so
powershell -File tool/build_amneziawg.ps1 -WireproxyVersion v1.0.19
```

Версия wireproxy **закреплена тегом** в самом скрипте, и оба десктопных бинаря идут
из одного чекаута: раньше Windows собирался из исходников, а Linux качался
релизом, и они молча разъехались на поколение протокола (см.
[PITFALLS.md](PITFALLS.md)). Android-часть тянет `amneziawg-android` (там лежат
`go.mod` + `jni.c`, из которых и получается `libwg-go.so`) и строит только
`arm64-v8a`: `abiFilters` в `app/build.gradle.kts` другого всё равно не пустит,
а собранный заодно `x86_64` — мусор в дереве.

Обе половины ставят одну и ту же версию amneziawg-go, и это условие, а не
совпадение: `.conf` на десктопе исполняет wireproxy, на Android — `libwg-go.so`
через UAPI, и профиль, который поднимется на одной платформе, обязан подняться
на другой.

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
  совпавшего хеша обновление не поставит. `tool/make_release.ps1` и
  `tool/package_linux.sh` генерируют сайдкары сами; при ручной заливке — не забудь;
- имена ассетов фиксированные: `keqdroid-<версия>-android.apk`,
  `keqdroid-windows-x64-<версия>.zip` (именно такой порядок слов),
  `keqdroid-<версия>-linux-x64.tar.gz`, `keqdroid_<версия>_amd64.deb`,
  `keqdroid-<версия>-x86_64.AppImage`;
- APK перед копированием проверяй через `aapt dump badging | grep versionName` — после
  упавшей сборки в `build/` остаётся **старый** APK от прошлого успеха.
