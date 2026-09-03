<h1 id="english">Building keqdroid: environment, run, tests</h1>

<strong>English</strong> · <a href="#русский">Русский</a>

The only developer document: how to get the project running locally, build it for every
platform, run the tests and cut a release. Everything else lives in the code and its
comments.

## 1. Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| **Flutter SDK** | stable, 3.44+ (Dart `^3.11.3` — see `pubspec.yaml`) | the main toolchain |
| **Android Studio** + Android SDK | compileSdk 36 | minSdk = 24 (the Flutter default; `android/app/build.gradle.kts` does not override it) |
| **JDK** | 17+ | Gradle's jvmTarget is 17; the JDK shipped with Android Studio (21) works too |
| **Visual Studio** + "Desktop development with C++" | 2022 or newer | VS 2026 (18.x) builds fine: `windows/CMakeLists.txt` already sets `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS` for the newer STL |
| **WSL + Ubuntu** | — | to build the Linux target (the Windows SDK cannot do it) |
| **gh CLI** | — | only for publishing releases |

`flutter doctor` tells you what is missing. Complaints about a GitHub handshake while an
HTTP proxy is active are a known quirk of the environment and do not affect the build.

## 2. First run

```bash
flutter pub get
```

`pub get` also generates the localizations (`flutter: generate: true` in pubspec) —
`lib/l10n/app_localizations*.dart` appear on their own.

## 3. Build and run

### Android

```bash
flutter run                       # debug on a device/emulator
flutter build apk --release
```

- On the first connection the system asks for VPN permission.
- The native cores ship as `jniLibs` (`android/app/src/main/jniLibs/<abi>/*.so`), not as
  Flutter assets — otherwise the desktop binaries bloated the APK.
- Crashlytics only works on Android and only in release. Without `google-services.json`
  the app still builds and runs, just without crash reporting.
- After a Kotlin version bump in `android/settings.gradle.kts` the first build may fail
  with a nonsensical "Unresolved reference" inside somebody else's plugin — that is a
  stale incremental cache, cured by `flutter clean`.

### Windows

```bash
flutter build windows --release
# output: build\windows\x64\runner\Release\keqdroid.exe + DLLs + cores
```

- The Windows plugin list (`windows/flutter/app_plugins.cmake` +
  `app_plugin_registrant.cc`) is committed with Firebase already removed (it is
  Android-only and breaks linking). A normal build works out of the box; re-run
  `tool/sync_windows_plugins.ps1` **only after adding or removing plugins** in pubspec.
- CMake copies the cores from `assets/bin/windows/` next to the exe: `keqrnel.exe`,
  `wireproxy.exe`, `wintun.dll`, `geoip.dat`, `geosite.dat`
  ([`assets/bin/windows/README.md`](../assets/bin/windows/README.md)). Separate
  `xray.exe` / `sing-box.exe` are not needed — keqrnel carries both engines inside.
- TUN mode requires running as administrator (keqrnel creates the wintun adapter);
  Proxy mode works without elevation.

### Linux (Debian/Arch, x86_64)

Native Linux or WSL only. There are two scripts with different jobs:

```bash
# build: installs the GTK toolchain and a native Linux Flutter (idempotent), then
# flutter build linux --release
wsl -e bash /mnt/c/Users/<you>/StudioProjects/keqdroid/tool/build_linux_wsl.sh

# package a finished bundle: tar.gz + deb + AppImage + PKGBUILD + sidecars
wsl -e bash /mnt/c/Users/<you>/StudioProjects/keqdroid/tool/package_linux.sh
```

- Do not launch these from Git Bash: it rewrites `/mnt/c/...` into a Windows path before
  `wsl` ever sees it, and the script is not found. Use PowerShell (or set
  `MSYS_NO_PATHCONV=1`).
- Both scripts work directly in the repository on `/mnt/c` and make no copies on the Linux
  filesystem — so a Linux build cannot run in parallel with a Windows or Android one.
- The cores live in `assets/bin/linux/`: `keqrnel`, `wireproxy` and the geo databases.
  CMake puts them next to the bundle binary, not into `flutter_assets`.
- Proxy mode works without root; TUN asks for root through `pkexec` on connect.

## 4. Tests and analysis

```bash
flutter analyze                                # must print "No issues found!"
flutter test                                   # the whole suite
flutter test test/utils/config_gen_test.dart   # a single file
```

The tests mirror `lib/`: `test/utils/` — config generators and parsers, `test/services/` —
storage/subscriptions/updater/ping, plus `test/models/`, `test/tunnel/`, `test/widgets/`,
`test/providers/`. Fixtures are in `test/helpers/` (`pump_app.dart`, `test_storage.dart`).

A clean analyze and green tests are a hard requirement for any PR: both catch real
regressions rather than ticking a box.

## 5. Rebuilding the native cores

Usually unnecessary — the prebuilt cores are already in `assets/bin/` and `jniLibs/`. When
you bump a core version:

| Script | What it builds |
|--------|----------------|
| `tool/build_amneziawg.ps1` | the AmneziaWG cores: `wireproxy` (Windows + Linux) and `libwg-go.so` (Android) |
| `tool/build_mihomo.ps1` | `libmihomo.so` (the second Android proxy core), with the patches from `tool/patches/` |
| `tool/build_linux_native.sh` | the Linux bundle + cores on native Linux |
| `tool/fetch_xray_geo.ps1` | fresh `geoip.dat` / `geosite.dat` |

`keqrnel` has no script — it is built from [its own
repository](https://github.com/Lemonochka/keqrnel) with a plain `go build`, one binary per
platform, into `assets/bin/windows/` and `assets/bin/linux/`:

```bash
go build -trimpath -buildvcs=false -tags with_gvisor -o keqrnel.exe ./cmd/keqrnel
GOOS=linux GOARCH=amd64 go build -trimpath -buildvcs=false -tags with_gvisor -o keqrnel ./cmd/keqrnel
```

**`with_gvisor` is mandatory.** The TUN stack is a user setting, and without this tag the
core has neither `gvisor` nor `mixed` — and with them goes full-cone NAT. A forgotten tag
shows up in the size: the binary loses roughly 3 MB.

`libxray.so` on Android is the official xray for `android/arm64`, renamed. Rebuilt from the
same xray-core repository, but with the NDK:

```bash
CGO_ENABLED=1 GOOS=android GOARCH=arm64 GOARM64=v8.0 \
  CC=$NDK/toolchains/llvm/prebuilt/windows-x86_64/bin/aarch64-linux-android21-clang.cmd \
  go build -trimpath -buildvcs=false -gcflags=all=-l=4 \
  -ldflags="-s -w -checklinkname=0" -o libxray.so github.com/xtls/xray-core/main
```

`-checklinkname=0` is not optional: the `anet` dependency (which fixes the broken
`net.Interfaces()` on Android) reaches into stdlib's `net.zoneCache`, and go1.26 forbids
such `go:linkname` — without the flag linking fails.

Build `keqrnel.exe`/`wireproxy.exe` for Windows **unstripped** and never run them from
`%TEMP%` — otherwise Defender treats them as a threat. The Android binary, on the contrary,
is stripped (`-s -w`), the way upstream does it.

`libmihomo.so` is the second proxy core for Android; the user picks between it and
`libxray.so` on the "About" screen. It is built by a script, not by hand:

```powershell
powershell -File tool/build_mihomo.ps1
```

**This is not stock upstream.** The script applies `tool/patches/mihomo-*.patch` and fails
if a patch does not land — a silently unpatched core looks healthy and only falls apart on
certain servers. What each patch fixes, and what has to stay in sync when updating, is
written in the patch header. There is one right now: mihomo hardcodes REALITY client
version `1.8.2` into the ClientHello, and a server with `minClient` set answers with the
real certificate of the masquerade domain instead of its own — the client sees
`REALITY authentication failed` even though the keys are correct.

AmneziaWG is built by a single script for all three platforms:

```powershell
powershell -File tool/build_amneziawg.ps1                       # wireproxy (win+linux) + libwg-go.so
powershell -File tool/build_amneziawg.ps1 -WireproxyVersion v1.0.19
```

The wireproxy version is **pinned by tag** inside the script, and both desktop binaries come
from one checkout: Windows used to be built from source while Linux was downloaded as a
release, and the two silently drifted a protocol generation apart. The Android half pulls
`amneziawg-android` (which holds the `go.mod` + `jni.c` that produce `libwg-go.so`) and
builds `arm64-v8a` only: `abiFilters` in `app/build.gradle.kts` would not let anything else
through anyway, and an `x86_64` built along the way is just litter in the tree.

Both halves install the same amneziawg-go version, and that is a requirement, not a
coincidence: a `.conf` is executed by wireproxy on the desktop and by `libwg-go.so` through
UAPI on Android, and a profile that comes up on one platform must come up on the other.

## 6. Localization (en / ru / de / zh)

The source of truth is ARB: `lib/l10n/app_en.arb` (the base) plus `app_ru/de/zh.arb`. Added
a string — add it to **all four** files, otherwise the "forgotten" language gets an empty
key. Generation runs on its own during `flutter pub get` / `flutter run` (or manually via
`flutter gen-l10n`). `app_localizations*.dart` are never edited by hand.

## 7. Release

```powershell
# APK + Windows zip + SHA-256 → release\<version>\
powershell -ExecutionPolicy Bypass -File tool\make_release.ps1

# the same plus publishing a GitHub release (needs the gh CLI)
powershell -ExecutionPolicy Bypass -File tool\make_release.ps1 -Publish -NotesFile notes.md
```

Rules that must not be broken:

- the version and the `vX.Y.Z` tag come from `version:` in `pubspec.yaml` — that is the
  single source;
- **every** asset carries a `<name>.sha256` sidecar (ASCII, no BOM): the updater is
  fail-closed and installs nothing without a matching hash. `tool/make_release.ps1` and
  `tool/package_linux.sh` generate the sidecars themselves; when uploading by hand, do not
  forget them;
- asset names are fixed: `keqdroid-<version>-android.apk`,
  `keqdroid-windows-x64-<version>.zip` (exactly that word order),
  `keqdroid-<version>-linux-x64.tar.gz`, `keqdroid_<version>_amd64.deb`,
  `keqdroid-<version>-x86_64.AppImage`;
- check the APK with `aapt dump badging | grep versionName` before copying it — after a
  failed build the **old** APK from the previous success is still sitting in `build/`.

---

<h2 id="русский">Русский</h2>

<a href="#english">English</a> · <strong>Русский</strong>

Единственный документ для разработчика: как поднять проект локально, собрать под
каждую платформу, прогнать тесты и выпустить релиз. Всё остальное — в коде и его
комментариях.

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
  Flutter-ассеты — иначе десктопные бинарники раздували APK.
- Crashlytics работает только на Android и только в release. Без `google-services.json`
  приложение собирается и работает, просто без репортинга крэшей.
- После обновления версии Kotlin в `android/settings.gradle.kts` первая сборка может упасть
  с бессмысленным «Unresolved reference» внутри чужого плагина — это протухший
  инкрементальный кэш, лечится `flutter clean`.

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
flutter test                                   # весь набор
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
`%TEMP%` — иначе Defender считает их угрозой.
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
`REALITY authentication failed`, хотя ключи верные.

AmneziaWG собирается одним скриптом на все три платформы:

```powershell
powershell -File tool/build_amneziawg.ps1                       # wireproxy (win+linux) + libwg-go.so
powershell -File tool/build_amneziawg.ps1 -WireproxyVersion v1.0.19
```

Версия wireproxy **закреплена тегом** в самом скрипте, и оба десктопных бинаря идут
из одного чекаута: раньше Windows собирался из исходников, а Linux качался
релизом, и они молча разъехались на поколение протокола.
Android-часть тянет `amneziawg-android` (там лежат
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
