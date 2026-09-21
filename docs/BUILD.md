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
  `mihomo.exe`, `wintun.dll`, `geoip.dat`, `geosite.dat`
  ([`assets/bin/windows/README.md`](../assets/bin/windows/README.md)). Separate
  `xray.exe` / `sing-box.exe` are not needed — keqrnel carries both engines inside.
- TUN mode requires administrator rights (keqrnel and mihomo both create the wintun
  adapter themselves); the app offers to restart elevated. Proxy mode works without
  elevation.

### Linux (Debian/Fedora/Arch, x86_64)

Native Linux or WSL only. There are two scripts with different jobs:

```bash
# build: installs the GTK toolchain and a native Linux Flutter (idempotent), then
# flutter build linux --release
wsl -e bash /mnt/c/Users/<you>/StudioProjects/keqdroid/tool/build_linux_wsl.sh

# package a finished bundle: tar.gz + deb + rpm + AppImage + PKGBUILD/.SRCINFO + SHA256SUMS
wsl -e bash /mnt/c/Users/<you>/StudioProjects/keqdroid/tool/package_linux.sh
```

- Do not launch these from Git Bash: it rewrites `/mnt/c/...` into a Windows path before
  `wsl` ever sees it, and the script is not found. Use PowerShell (or set
  `MSYS_NO_PATHCONV=1`).
- Both scripts work directly in the repository on `/mnt/c` and make no copies on the Linux
  filesystem — so a Linux build cannot run in parallel with a Windows or Android one.
- The cores live in `assets/bin/linux/`: `keqrnel`, `mihomo` and the geo databases.
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
`test/providers/`. Fixtures are in `test/fixtures/`, helpers in `test/helpers/`
(`pump_app.dart`, `test_storage.dart`).

A clean analyze and green tests are a hard requirement for any PR: both catch real
regressions rather than ticking a box.

## 5. Rebuilding the native cores

Usually unnecessary — the prebuilt cores are already in `assets/bin/` and `jniLibs/`. When
you bump a core version:

| Script | What it builds |
|--------|----------------|
| `tool/build_mihomo.ps1` | mihomo for all three platforms — `libmihomo.so`, `mihomo.exe`, `mihomo` — with the patches from `tool/patches/` |
| `tool/build_linux_native.sh` | the Linux bundle + cores on native Linux |
| `tool/fetch_xray_geo.ps1` | fresh `geoip.dat` / `geosite.dat` |

`keqrnel` has no script — it is built from [its own
repository](https://github.com/Lemonochka/keqrnel) with a plain `go build`, one binary per
platform, into `assets/bin/windows/` and `assets/bin/linux/`:

```bash
go build -trimpath -buildvcs=false -tags with_gvisor -o keqrnel.exe ./cmd/keqrnel
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -buildvcs=false -tags with_gvisor \
  -ldflags="-s -w" -o keqrnel ./cmd/keqrnel
```

**`with_gvisor` is mandatory.** The TUN stack is a user setting, and without this tag the
core has neither `gvisor` nor `mixed` — and with them goes full-cone NAT. A forgotten tag
shows up in the size: the binary loses roughly 3 MB.

`libxray.so` on Android is not an official release: it is built from the same xray-core
revision that keqrnel pins, so every platform runs the same Xray (`go version -m` on both
binaries shows one commit). With the NDK:

```bash
CGO_ENABLED=1 GOOS=android GOARCH=arm64 GOARM64=v8.0 \
  CC=$NDK/toolchains/llvm/prebuilt/windows-x86_64/bin/aarch64-linux-android21-clang.cmd \
  go build -trimpath -buildvcs=false -gcflags=all=-l=4 \
  -ldflags="-s -w -checklinkname=0" -o libxray.so github.com/xtls/xray-core/main
```

`-checklinkname=0` is not optional: the `anet` dependency (which fixes the broken
`net.Interfaces()` on Android) reaches into stdlib's `net.zoneCache`, and go1.26 forbids
such `go:linkname` — without the flag linking fails.

Build `keqrnel.exe`/`mihomo.exe` for **Windows** unstripped and never run them from
`%TEMP%` — otherwise Defender treats them as a threat. That is a Windows rule and nothing
more: the Android and Linux binaries are stripped (`-s -w`), which takes about 20 MB off
each Linux core and 29 MB off what the user downloads, and costs nothing — Go prints
stack traces with function names without the symbol table anyway.

mihomo is the second core on every platform; for links both cores can run, the user picks
one in Settings → About. It is built by a script, not by hand:

```powershell
powershell -File tool/build_mihomo.ps1
```

**This is not stock upstream.** The script applies `tool/patches/mihomo-*.patch` and fails
if a patch does not land — a silently unpatched core looks healthy and only falls apart on
certain servers. What each patch fixes, and what has to stay in sync when updating, is
written in the patch header. Three of them right now, and two share one symptom: mihomo
hardcodes REALITY client version `1.8.2` into the ClientHello, and its firefox fingerprint
stopped at Firefox 120, which sends no X25519MLKEM768 key share. A server with `minClient`
set, and any server on Xray 26.9.9, answers either hello with the real certificate of the
masquerade domain instead of its own — the client sees `REALITY authentication failed`
even though the keys are correct. The third patch is Android-only: mihomo's tun listener
reads `/data/system/packages.xml`, which SELinux does not hand to an app.

AmneziaWG has no core of its own any more: mihomo carries amneziawg-go and runs a `.conf`
profile as `type: wireguard` with `amnezia-wg-option`. There is nothing to build for it
separately.

## 6. Localization (en / ru / de / zh / fa)

The source of truth is ARB: `lib/l10n/app_en.arb` (the base) plus `app_ru/de/zh/fa.arb`.
Added a string — add it to **all five** files, otherwise the "forgotten" language gets an
empty key. Generation runs on its own during `flutter pub get` / `flutter run` (or manually via
`flutter gen-l10n`). `app_localizations*.dart` are never edited by hand.

## 7. Release

```powershell
# Android + Windows + Linux (that part in WSL) + SHA256SUMS → release\<version>\
powershell -ExecutionPolicy Bypass -File tool\make_release.ps1

# the same plus publishing a GitHub release (needs the gh CLI)
powershell -ExecutionPolicy Bypass -File tool\make_release.ps1 -Publish -NotesFile notes.md

# after the release is up: push PKGBUILD + .SRCINFO to the AUR
wsl -e bash /mnt/c/Users/<you>/StudioProjects/keqdroid/tool/publish_aur.sh
```

Rules that must not be broken:

- the version and the `vX.Y.Z` tag come from `version:` in `pubspec.yaml` — that is the
  single source;
- the release carries one `SHA256SUMS` (ASCII, no BOM, LF, `sha256sum` format): the updater
  is fail-closed and installs nothing without a matching hash. Every build since 0.5.0
  reads it, which is why per-asset `.sha256` sidecars are gone; 0.4.x knows only the
  sidecar and has to be updated by hand. An asset name must appear in exactly **one** line
  — the updater takes the first line containing it, so a name that is part of another one
  would be handed the wrong hash. `tool/make_release.ps1` checks that before publishing;
- `geoip.dat.sha256` is the one sidecar that stays: the full geo base download in
  0.15.0 - 0.18.0 asks the latest release for exactly that name;
- asset names are fixed: `keqdroid-<version>-android.apk`,
  `keqdroid-windows-x64-<version>.zip` (exactly that word order),
  `keqdroid-<version>-linux-x64.tar.gz`, `keqdroid_<version>_amd64.deb`,
  `keqdroid-<version>-x86_64.AppImage`, `keqdroid-<version>-1.x86_64.rpm`;
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
  `mihomo.exe`, `wintun.dll`, `geoip.dat`, `geosite.dat`
  ([`assets/bin/windows/README.md`](../assets/bin/windows/README.md)). Отдельные
  `xray.exe` / `sing-box.exe` не нужны — keqrnel несёт оба движка внутри.
- TUN-режим требует прав администратора (wintun-адаптер создают сами keqrnel и
  mihomo); приложение предлагает перезапуститься с ними. Proxy работает без прав.

### Linux (Debian/Fedora/Arch, x86_64)

Только на нативном Linux или в WSL. Скриптов два, роли разные:

```bash
# сборка: ставит GTK-тулчейн и нативный Linux-Flutter (идемпотентно), потом
# flutter build linux --release
wsl -e bash /mnt/c/Users/<ты>/StudioProjects/keqdroid/tool/build_linux_wsl.sh

# упаковка готового бандла: tar.gz + deb + rpm + AppImage + PKGBUILD/.SRCINFO + SHA256SUMS
wsl -e bash /mnt/c/Users/<ты>/StudioProjects/keqdroid/tool/package_linux.sh
```

- Из Git Bash так не запускай: он превратит `/mnt/c/...` в виндовый путь ещё до `wsl`,
  и скрипт не найдётся. Запускай из PowerShell (или ставь `MSYS_NO_PATHCONV=1`).
- Оба скрипта работают прямо в репозитории на `/mnt/c`, копий на Linux-ФС не делают —
  поэтому Linux-сборку нельзя гонять параллельно с Windows или Android.
- Ядра — в `assets/bin/linux/`: `keqrnel`, `mihomo` и geo-базы. CMake кладёт их
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
`test/providers/`. Фикстуры — в `test/fixtures/`, помощники — в `test/helpers/`
(`pump_app.dart`, `test_storage.dart`).

Чистый analyze и зелёные тесты — обязательное условие любого PR: и то и другое ловит
реальные регрессии, а не для галочки.

## 5. Пересборка нативных ядер

Обычно не нужна — собранные ядра уже лежат в `assets/bin/` и `jniLibs/`. Когда обновляешь
версию ядра:

| Скрипт | Что собирает |
|--------|--------------|
| `tool/build_mihomo.ps1` | mihomo под все три платформы — `libmihomo.so`, `mihomo.exe`, `mihomo` — с патчами из `tool/patches/` |
| `tool/build_linux_native.sh` | Linux-бандл + ядра на нативном Linux |
| `tool/fetch_xray_geo.ps1` | свежие `geoip.dat` / `geosite.dat` |

`keqrnel` скрипта не имеет — собирается из [своего
репозитория](https://github.com/Lemonochka/keqrnel) обычным `go build`, по бинарю на
платформу, в `assets/bin/windows/` и `assets/bin/linux/`:

```bash
go build -trimpath -buildvcs=false -tags with_gvisor -o keqrnel.exe ./cmd/keqrnel
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -buildvcs=false -tags with_gvisor \
  -ldflags="-s -w" -o keqrnel ./cmd/keqrnel
```

**`with_gvisor` обязателен.** Стек TUN — пользовательская настройка, и без этого тега
в ядре нет ни `gvisor`, ни `mixed`, а с ними и full-cone NAT. Забытый тег виден по
размеру: бинарь худеет примерно на 3 МБ.

`libxray.so` под Android — не официальный релиз: он собран из той же ревизии xray-core,
что закреплена в keqrnel, и на всех платформах едет один и тот же Xray (`go version -m`
на обоих бинарях показывает один коммит). Собирается с NDK:

```bash
CGO_ENABLED=1 GOOS=android GOARCH=arm64 GOARM64=v8.0 \
  CC=$NDK/toolchains/llvm/prebuilt/windows-x86_64/bin/aarch64-linux-android21-clang.cmd \
  go build -trimpath -buildvcs=false -gcflags=all=-l=4 \
  -ldflags="-s -w -checklinkname=0" -o libxray.so github.com/xtls/xray-core/main
```

`-checklinkname=0` без вариантов: зависимость `anet` (чинит сломанный
`net.Interfaces()` на Android) лезет в `net.zoneCache` из stdlib, а go1.26 такие
`go:linkname` запрещает — без флага падает линковка.

`keqrnel.exe`/`mihomo.exe` под **Windows** собирай unstripped и не запускай из
`%TEMP%` — иначе Defender считает их угрозой. Это правило только про Windows:
android- и linux-бинари стрипаются (`-s -w`), и это снимает около 20 МБ с каждого
linux-ядра и 29 МБ с того, что качает пользователь. Платы нет — стек-трейсы Go
печатает с именами функций и без таблицы символов.

mihomo — второе ядро на всех платформах; для ссылок, которые берут оба ядра, его
выбирают в Настройки → О приложении. Собирается скриптом, а не руками:

```powershell
powershell -File tool/build_mihomo.ps1
```

**Это не сток апстрима.** Скрипт накатывает `tool/patches/mihomo-*.patch` и падает,
если патч не лёг, — молча непропатченное ядро выглядит здоровым и отваливается
только на отдельных серверах. Что чинит каждый патч и что при обновлении держать
в согласии, написано в шапке самого патча. Сейчас их три, и у двух один симптом:
mihomo зашивает в ClientHello версию REALITY-клиента `1.8.2`, а его отпечаток firefox
остановился на Firefox 120, который не шлёт key share `X25519MLKEM768`. И сервер с
поднятым `minClient`, и любой сервер на Xray 26.9.9 отдают такому приветствию настоящий
сертификат маскировочного домена вместо своего — клиент видит
`REALITY authentication failed`, хотя ключи верные. Третий патч нужен только Android:
tun-листенер mihomo читает `/data/system/packages.xml`, который SELinux приложению не
отдаёт.

Своего ядра у AmneziaWG больше нет: amneziawg-go живёт внутри mihomo, и профиль `.conf`
исполняется как `type: wireguard` с `amnezia-wg-option`. Отдельно собирать нечего.

## 6. Локализация (en / ru / de / zh / fa)

Источник истины — ARB: `lib/l10n/app_en.arb` (база) и `app_ru/de/zh/fa.arb`. Добавил
строку — добавь её **во все пять** файлов, иначе на «забытом» языке будет пустой ключ. Генерация
подтягивается сама при `flutter pub get` / `flutter run` (или вручную `flutter gen-l10n`).
`app_localizations*.dart` руками не редактируются.

## 7. Релиз

```powershell
# Android + Windows + Linux (эта часть — в WSL) + SHA256SUMS → release\<версия>\
powershell -ExecutionPolicy Bypass -File tool\make_release.ps1

# то же + публикация GitHub-релиза (нужен gh CLI)
powershell -ExecutionPolicy Bypass -File tool\make_release.ps1 -Publish -NotesFile notes.md

# когда релиз уже опубликован: PKGBUILD + .SRCINFO уезжают на AUR
wsl -e bash /mnt/c/Users/<ты>/StudioProjects/keqdroid/tool/publish_aur.sh
```

Правила, которые нельзя нарушать:

- версия и тег `vX.Y.Z` берутся из `version:` в `pubspec.yaml` — это единственный источник;
- на весь релиз один `SHA256SUMS` (ASCII без BOM, LF, формат `sha256sum`): апдейтер
  fail-closed и без совпавшего хеша обновление не поставит. Его читают все сборки с 0.5.0 —
  поэтому сайдкаров `.sha256` у каждого ассета больше нет; 0.4.x знает только сайдкар,
  оттуда обновляются руками. Имя ассета обязано встречаться ровно в **одной** строке:
  апдейтер берёт первую строку, содержащую имя, и имя, оказавшееся частью чужой строки,
  получило бы чужой хеш. `tool/make_release.ps1` проверяет это перед публикацией;
- `geoip.dat.sha256` — единственный сайдкар, который остаётся: загрузчик полной geo-базы
  в 0.15.0 - 0.18.0 просит у последнего релиза именно это имя;
- имена ассетов фиксированные: `keqdroid-<версия>-android.apk`,
  `keqdroid-windows-x64-<версия>.zip` (именно такой порядок слов),
  `keqdroid-<версия>-linux-x64.tar.gz`, `keqdroid_<версия>_amd64.deb`,
  `keqdroid-<версия>-x86_64.AppImage`, `keqdroid-<версия>-1.x86_64.rpm`;
- APK перед копированием проверяй через `aapt dump badging | grep versionName` — после
  упавшей сборки в `build/` остаётся **старый** APK от прошлого успеха.
