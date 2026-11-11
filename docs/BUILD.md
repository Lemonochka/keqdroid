<h1 id="english">Building keqdroid: environment, run, tests</h1>

<strong>English</strong> · <a href="#русский">Русский</a>

How to set up the project, build it for every platform, run the tests and make a release.

## 1. Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| **Flutter SDK** | stable, 3.44+ (Dart `^3.11.3`, see `pubspec.yaml`) | the main toolchain |
| **Android Studio** + Android SDK | compileSdk 36 | minSdk = 24 (the Flutter default; `android/app/build.gradle.kts` does not override it) |
| **JDK** | 17+ | Gradle's jvmTarget is 17; the JDK shipped with Android Studio (21) works too |
| **Visual Studio** + "Desktop development with C++" | 2022 or newer | VS 2026 (18.x) builds fine: `windows/CMakeLists.txt` already sets `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS` for the newer STL |
| **WSL + Ubuntu** | — | to build the Linux target (the Windows SDK cannot do it) |
| **Inno Setup** | 7.1.1 | the Windows installer (`windows/installer/keqdroid.iss`); `release.yml` installs the same version |
| **gh CLI** | — | only for publishing releases |

`flutter doctor` shows what is missing.

## 2. First run

```bash
flutter pub get
```

`pub get` also generates the localizations into `lib/l10n/app_localizations*.dart`
(`flutter: generate: true` in pubspec).

## 3. Build and run

### Android

```bash
flutter run                       # debug on a device/emulator
flutter build apk --release
```

- On the first connection the system asks for VPN permission.
- Without a flag the APK is arm64-v8a; `--target-platform android-arm` builds the 32-bit
  one (armeabi-v7a).
- The native cores ship as `jniLibs` (`android/app/src/main/jniLibs/<abi>/*.so`), not as
  Flutter assets, which go into every platform's bundle.
- Crashlytics works only on Android and only in release builds. Without
  `google-services.json` the app builds and runs without crash reporting.
- After changing the Kotlin version in `android/settings.gradle.kts`, run `flutter clean`:
  the stale incremental cache otherwise causes "Unresolved reference" errors in plugins.

### Windows

```bash
flutter build windows --release
# output: build\windows\x64\runner\Release\keqdroid.exe + DLLs + cores
```

- The Windows plugin list (`windows/flutter/app_plugins.cmake` +
  `app_plugin_registrant.cc`) is committed without Firebase, which is Android-only and
  breaks linking. After adding or removing plugins in pubspec, run
  `tool/sync_windows_plugins.ps1`.
- CMake copies the cores from `assets/bin/windows/` next to the exe: `xray.exe`,
  `mihomo.exe`, `wintun.dll`, `geoip.dat`, `geosite.dat`
  ([`assets/bin/windows/README.md`](../assets/bin/windows/README.md)).
- TUN mode needs administrator rights, since xray and mihomo create the wintun adapter
  themselves; the app offers to restart elevated. Proxy mode works without them.

### Linux (Debian/Fedora/Arch, x86_64)

Native Linux or WSL only. Two scripts:

```bash
# build: installs the GTK toolchain and a native Linux Flutter (idempotent), then
# flutter build linux --release
wsl -d Ubuntu-22.04 -e bash /mnt/c/Users/<you>/StudioProjects/keqdroid/tool/build_linux_wsl.sh

# package a finished bundle: tar.gz + deb + rpm + AppImage + PKGBUILD/.SRCINFO + SHA256SUMS
wsl -d Ubuntu-22.04 -e bash /mnt/c/Users/<you>/StudioProjects/keqdroid/tool/package_linux.sh
```

- Release packages are built on Ubuntu 22.04. A build made on a newer system needs its newer
  GLib and does not start on Ubuntu 22.04 or Debian 12, so `package_linux.sh` refuses one.
- Run them from PowerShell, not Git Bash: Git Bash turns `/mnt/c/...` into a Windows
  path (or set `MSYS_NO_PATHCONV=1`).
- Both scripts work in the repository on `/mnt/c` directly, so a Linux build cannot run in
  parallel with a Windows or Android one.
- The cores live in `assets/bin/linux/`: `xray`, `mihomo` and the geo databases.
  CMake puts them next to the bundle binary, not into `flutter_assets`.
- Proxy mode works without root; TUN asks for root through `pkexec` on connect. Without
  polkit, run the app as root (`sudo -E keqdroid`): it then starts the core directly.

## 4. Tests and analysis

```bash
flutter analyze                                # must print "No issues found!"
flutter test                                   # the whole suite
flutter test test/utils/config_gen_test.dart   # a single file
```

The tests mirror `lib/`: `test/utils/` (config generators and parsers), `test/services/`
(storage, subscriptions, updater, ping), plus `test/models/`, `test/tunnel/`,
`test/widgets/`, `test/providers/`. Fixtures are in `test/fixtures/`, helpers in `test/helpers/`
(`pump_app.dart`, `test_storage.dart`).

A clean analyze and green tests are required for every PR.

## 5. Rebuilding the native cores

The prebuilt cores are already in `assets/bin/` and `jniLibs/`. To update a core:

| Script | What it builds |
|--------|----------------|
| `tool/build_mihomo.ps1` | mihomo with the patches from `tool/patches/`: `libmihomo.so` (arm64-v8a and armeabi-v7a), `mihomo.exe`, `mihomo` |
| `tool/build_xray_cores.ps1` | patched xray from keqrnel's `tools/patchxray`: `xray.exe`, `xray`, `libxray.so` (arm64-v8a and armeabi-v7a) |
| `tool/build_linux_native.sh` | the Linux bundle + cores on native Linux |
| `tool/fetch_xray_geo.ps1` | fresh `geoip.dat` / `geosite.dat` |

xray for the desktop (`assets/bin/windows/xray.exe`, `assets/bin/linux/xray`) and
`libxray.so` for Android (arm64-v8a and armeabi-v7a) are built with one script, from a
checkout of [keqrnel](https://github.com/Lemonochka/keqrnel) next to this repository:

```powershell
powershell -File tool/build_xray_cores.ps1                   # all three
powershell -File tool/build_xray_cores.ps1 -Target windows   # or android, linux
```

The xray-core revision and every dependency come from keqrnel's `go.mod`, so every
platform runs the same Xray. The patched xray belongs to keqrnel: its `tools/patchxray`
applies keqrnel's `patches/xray-*.patch` and writes a module file pointing the build at
that tree, and stops if a patch does not apply. keqrnel's
`patches/xray-udp-dial-queue.patch` keeps a burst of incoming UDP that `core.DialUDP`
dropped past 16 packets: without it calls, screen shares and games lost up to 39% of
incoming packets on PC.

This repository's `tool/patches/xray-*.patch` go on top, in the same tree for every
platform. `xray-android-*` are for Android: the VPN service names the app behind a
connection, and UDP takes the route of each address. `xray-desktop-*` are for the PC TUN:
process rules, the program in the access log, counters, a clean stop through stdin, a UDP
timeout of its own, ping and traceroute past the tunnel. On the other platform each of them stays idle; the patch headers say
why.

`-checklinkname=0` is required for `libxray.so`: the
`anet` dependency links into `net.zoneCache` in the standard library, which Go 1.26+
rejects without the flag.

Windows binaries (`xray.exe`, `mihomo.exe`) are built unstripped and must not be run
from `%TEMP%`, otherwise Defender flags them. Android and Linux binaries are stripped with
`-s -w`.

mihomo, for all platforms and both Android ABIs, is built with a script:

```powershell
powershell -File tool/build_mihomo.ps1
```

The script applies `tool/patches/mihomo-*.patch` and stops if a patch does not apply. Each
patch header says what it fixes and what to keep in sync on update:

- `mihomo-reality-client-version.patch`: a current REALITY client version instead of the
  hardcoded `1.8.2`, for servers with `minClient`;
- `mihomo-firefox-148-hello.patch`: the Firefox ClientHello with the X25519MLKEM768 key
  share that servers on Xray 26.9.9+ require;
- `mihomo-android-package-manager.patch`: the Android TUN listener reads
  `/data/system/packages.xml`, which SELinux blocks for apps, only when something needs it.
- `mihomo-android-uid-owner.patch`: on Android mihomo asks the VPN service which app
  opened a connection, since SELinux hides other apps' sockets from it.

AmneziaWG runs on mihomo: amneziawg-go is built in, and a `.conf` profile runs as
`type: wireguard` with `amnezia-wg-option`. There is nothing separate to build.

## 6. Localization (en / ru / de / zh / fa)

The source of truth is ARB: `lib/l10n/app_en.arb` (the base) plus `app_ru/de/zh/fa.arb`.
A new string goes into **all five** files; a language without it gets an empty key.
Generation runs during `flutter pub get` / `flutter run` (or `flutter gen-l10n`).
`app_localizations*.dart` are not edited by hand.

## 7. Release

Releases are built on GitHub: Actions → **release** → Run workflow.
`.github/workflows/release.yml` builds the APKs, the Windows zip and installer on a Windows runner
(`tool/make_release.ps1 -SkipLinux`), the Linux packages in an Ubuntu 22.04 container
(`tool/build_linux_wsl.sh`, `tool/package_linux.sh`), writes `SHA256SUMS`
(`tool/write_sha256sums.ps1`), signs it (`tool/sign_sums.sh` → `SHA256SUMS.sig`), attests
every file and leaves a **draft** release. Write the notes into the draft and publish it.
With "draft" unticked the run only builds, and the files stay in its `release-files`
artifact. The secrets it needs are listed at the top of the workflow.

The same packages locally, for comparison or when GitHub is not an option:

```powershell
# Android + Windows + Linux (that part in WSL) + SHA256SUMS → release\<version>\
powershell -ExecutionPolicy Bypass -File tool\make_release.ps1

# the same, signed, plus publishing a GitHub release (needs the gh CLI)
powershell -ExecutionPolicy Bypass -File tool\make_release.ps1 -SigningKey <key.pem> -Publish -NotesFile notes.md

# after the release is up: push PKGBUILD + .SRCINFO to the AUR
wsl -e bash /mnt/c/Users/<you>/StudioProjects/keqdroid/tool/publish_aur.sh
```

Checking a downloaded file by hand:

```bash
gh attestation verify <file> --repo Lemonochka/keqdroid   # built by this repository's workflow
sha256sum -c --ignore-missing SHA256SUMS
```

Rules:

- `SHA256SUMS.sig` is base64 of an Ed25519 signature over `SHA256SUMS` byte for byte. The
  app (`lib/services/release_signature.dart`) knows two public keys: the main one, whose
  private half is the `UPDATE_SIGNING_KEY` secret, and a reserve one kept off GitHub.
  Versions after 0.35.0 install no update and no full geo base without a valid signature,
  so a release published without `SHA256SUMS.sig` breaks updates for all of them;

- the version and the `vX.Y.Z` tag come from `version:` in `pubspec.yaml`;
- the release has one `SHA256SUMS` (ASCII, no BOM, LF, `sha256sum` format), and the updater
  installs nothing without a matching hash. Versions since 0.5.0 read it; 0.4.x reads only
  per-file `.sha256` and is updated by hand. Each asset name must appear in exactly
  **one** line, since the updater takes the first line containing the name;
  `tool/make_release.ps1` checks this;
- `geoip.dat.sha256` stays: the geo base download in 0.15.0 - 0.18.0 requests exactly that
  file from the latest release;
- asset names are fixed: `keqdroid-<version>-android.apk`,
  `keqdroid-<version>-armeabi-v7a-android.apk` (must sort after the main APK: older
  updaters take the first `.apk` in GitHub's name-sorted list),
  `keqdroid-windows-x64-<version>.zip` (exactly that word order),
  `keqdroid-windows-x64-<version>-setup.exe` (the updater of an installed copy looks for
  the `-setup.exe` ending; the portable one keeps taking the zip, so the zip stays in
  every release),
  `keqdroid-<version>-linux-x64.tar.gz`, `keqdroid_<version>_amd64.deb`,
  `keqdroid-<version>-x86_64.AppImage`, `keqdroid-<version>-1.x86_64.rpm`;
- when building by hand, check the APK version with `aapt dump badging | grep versionName`
  before uploading: a failed build leaves the previous APK in `build/`.

Windows code signing through SignPath Foundation is wired in but off. Once the project is
accepted, give it this artifact configuration on signpath.io (the workflow sends the
release zip itself, so the zip is the root):

```xml
<artifact-configuration xmlns="http://signpath.io/artifact-configuration/v1">
  <zip-file>
    <pe-file path="keqdroid.exe" product-name="keqdroid">
      <authenticode-sign/>
    </pe-file>
  </zip-file>
</artifact-configuration>
```

then add the repository variables `SIGNPATH_ORGANIZATION_ID`, `SIGNPATH_PROJECT_SLUG`,
`SIGNPATH_SIGNING_POLICY_SLUG` and the secret `SIGNPATH_API_TOKEN`. From then on the
`sign-windows` job sends the zip for signing and waits until the request is approved on
signpath.io. Only `keqdroid.exe` is signed: `xray.exe` and `mihomo.exe` are upstream
builds, which SignPath Foundation does not sign.

The installer is built before that job from the same unsigned files, so it carries an
unsigned `keqdroid.exe` and is not signed itself. Before turning SignPath on, the workflow
has to build the installer from the signed files and send `setup.exe` for signing too.

---

<h2 id="русский">Русский</h2>

<a href="#english">English</a> · <strong>Русский</strong>

Как поднять проект, собрать его под каждую платформу, прогнать тесты и выпустить релиз.

## 1. Что нужно установить

| Инструмент | Версия | Заметки |
|------------|--------|---------|
| **Flutter SDK** | stable, 3.44+ (Dart `^3.11.3` — см. `pubspec.yaml`) | основной тулчейн |
| **Android Studio** + Android SDK | compileSdk 36 | minSdk = 24 (дефолт Flutter, `android/app/build.gradle.kts` его не переопределяет) |
| **JDK** | 17+ | jvmTarget в Gradle — 17; JDK из Android Studio (21) тоже подходит |
| **Visual Studio** + «Desktop development with C++» | 2022 или новее | на VS 2026 (18.x) собирается: для новых STL в `windows/CMakeLists.txt` уже стоит `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS` |
| **WSL + Ubuntu** | — | сборка Linux-таргета (из Windows-SDK её не сделать) |
| **Inno Setup** | 7.1.1 | установщик для Windows (`windows/installer/keqdroid.iss`); `release.yml` ставит ту же версию |
| **gh CLI** | — | только для публикации релизов |

`flutter doctor` покажет, чего не хватает.

## 2. Первый запуск

```bash
flutter pub get
```

`pub get` заодно генерирует локализации в `lib/l10n/app_localizations*.dart`
(`flutter: generate: true` в pubspec).

## 3. Сборка и запуск

### Android

```bash
flutter run                       # debug на устройстве/эмуляторе
flutter build apk --release
```

- При первом подключении система спросит разрешение VPN.
- Без флага APK собирается под arm64-v8a; `--target-platform android-arm` собирает
  32-битный (armeabi-v7a).
- Нативные ядра лежат как `jniLibs` (`android/app/src/main/jniLibs/<abi>/*.so`), а не как
  Flutter-ассеты, которые попадают в сборку каждой платформы.
- Crashlytics работает только на Android и только в release. Без `google-services.json`
  приложение собирается и работает, но без отчётов о падениях.
- После смены версии Kotlin в `android/settings.gradle.kts` выполни `flutter clean`:
  иначе устаревший инкрементальный кэш даёт ошибки «Unresolved reference» в плагинах.

### Windows

```bash
flutter build windows --release
# результат: build\windows\x64\runner\Release\keqdroid.exe + DLL + ядра
```

- Список Windows-плагинов (`windows/flutter/app_plugins.cmake` +
  `app_plugin_registrant.cc`) закоммичен без Firebase: он нужен только на Android и ломает
  линковку. После добавления или удаления плагинов в pubspec запусти
  `tool/sync_windows_plugins.ps1`.
- Ядра из `assets/bin/windows/` CMake кладёт рядом с exe: `xray.exe`,
  `mihomo.exe`, `wintun.dll`, `geoip.dat`, `geosite.dat`
  ([`assets/bin/windows/README.md`](../assets/bin/windows/README.md)).
- Для TUN нужны права администратора: wintun-адаптер создают сами xray и mihomo.
  Приложение предлагает перезапуститься с ними. Proxy работает без прав.

### Linux (Debian/Fedora/Arch, x86_64)

Только на нативном Linux или в WSL. Скриптов два:

```bash
# сборка: ставит GTK-тулчейн и нативный Linux-Flutter (идемпотентно), потом
# flutter build linux --release
wsl -d Ubuntu-22.04 -e bash /mnt/c/Users/<ты>/StudioProjects/keqdroid/tool/build_linux_wsl.sh

# упаковка готового бандла: tar.gz + deb + rpm + AppImage + PKGBUILD/.SRCINFO + SHA256SUMS
wsl -d Ubuntu-22.04 -e bash /mnt/c/Users/<ты>/StudioProjects/keqdroid/tool/package_linux.sh
```

- Релизные пакеты собираются на Ubuntu 22.04. Собранное на системе новее требует её новую
  GLib и не запускается на Ubuntu 22.04 и Debian 12, поэтому `package_linux.sh` такую сборку
  не пакует.
- Запускай из PowerShell, не из Git Bash: Git Bash превращает `/mnt/c/...` в виндовый путь
  (или поставь `MSYS_NO_PATHCONV=1`).
- Оба скрипта работают прямо в репозитории на `/mnt/c`, поэтому Linux-сборку нельзя
  запускать параллельно с Windows или Android.
- Ядра — в `assets/bin/linux/`: `xray`, `mihomo` и geo-базы. CMake кладёт их
  рядом с бинарём бандла, не в `flutter_assets`.
- Proxy работает без root; TUN запрашивает root через `pkexec` при подключении. Без
  polkit запусти приложение от root (`sudo -E keqdroid`): тогда ядро стартует напрямую.

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

Чистый analyze и зелёные тесты обязательны для любого PR.

## 5. Пересборка нативных ядер

Собранные ядра уже лежат в `assets/bin/` и `jniLibs/`. Чтобы обновить ядро:

| Скрипт | Что собирает |
|--------|--------------|
| `tool/build_mihomo.ps1` | mihomo с патчами из `tool/patches/`: `libmihomo.so` (arm64-v8a и armeabi-v7a), `mihomo.exe`, `mihomo` |
| `tool/build_xray_cores.ps1` | пропатченный xray из `tools/patchxray` keqrnel: `xray.exe`, `xray`, `libxray.so` (arm64-v8a и armeabi-v7a) |
| `tool/build_linux_native.sh` | Linux-бандл + ядра на нативном Linux |
| `tool/fetch_xray_geo.ps1` | свежие `geoip.dat` / `geosite.dat` |

xray для ПК (`assets/bin/windows/xray.exe`, `assets/bin/linux/xray`) и `libxray.so`
для Android (arm64-v8a и armeabi-v7a) собираются одним скриптом из checkout'а
[keqrnel](https://github.com/Lemonochka/keqrnel), лежащего рядом с этим репозиторием:

```powershell
powershell -File tool/build_xray_cores.ps1                   # все три
powershell -File tool/build_xray_cores.ps1 -Target windows   # или android, linux
```

Ревизия xray-core и все зависимости берутся из `go.mod` keqrnel, поэтому на всех
платформах один и тот же Xray. Пропатченный xray принадлежит keqrnel: его
`tools/patchxray` накатывает `patches/xray-*.patch` keqrnel, пишет файл модуля, который
направляет сборку на это дерево, и останавливается, если патч не лёг. Патч keqrnel
`patches/xray-udp-dial-queue.patch` держит всплеск входящего UDP, который `core.DialUDP`
выбрасывал сверх 16 пакетов: без него звонки, демонстрация экрана и игры на ПК теряли до
39% входящих пакетов.

Сверху ложатся `tool/patches/xray-*.patch` этого репозитория, в одном дереве для всех
платформ. `xray-android-*` для Android: VPN-сервис называет приложение за соединением,
а UDP идёт маршрутом каждого адреса. `xray-desktop-*` для TUN на ПК: правила по
программам, программа в журнале, счётчики, мягкая остановка через stdin, свой таймаут
UDP, ping и tracert мимо туннеля. На другой платформе каждый из них спит, почему, написано в шапке патча.

`-checklinkname=0` обязателен для `libxray.so`:
зависимость `anet` ссылается на `net.zoneCache` из стандартной библиотеки, а Go 1.26+ без
флага такое не линкует.

Windows-бинари (`xray.exe`, `mihomo.exe`) собираются без стрипа, и запускать их из
`%TEMP%` нельзя: иначе их блокирует Defender. Android- и Linux-бинари стрипаются
(`-s -w`).

mihomo под все платформы и обе Android-ABI собирается скриптом:

```powershell
powershell -File tool/build_mihomo.ps1
```

Скрипт накатывает `tool/patches/mihomo-*.patch` и останавливается, если патч не лёг. Что
чинит патч и что держать в согласии при обновлении, написано в его шапке:

- `mihomo-reality-client-version.patch`: актуальная версия REALITY-клиента вместо
  зашитой `1.8.2`, для серверов с `minClient`;
- `mihomo-firefox-148-hello.patch`: ClientHello Firefox с key share `X25519MLKEM768`,
  которого требуют серверы на Xray 26.9.9+;
- `mihomo-android-package-manager.patch`: TUN-листенер на Android читает
  `/data/system/packages.xml`, который SELinux закрывает от приложений, только когда он
  действительно нужен.
- `mihomo-android-uid-owner.patch`: на Android mihomo спрашивает у VPN-сервиса, какое
  приложение открыло соединение: чужие сокеты SELinux от него прячет.

AmneziaWG работает на mihomo: amneziawg-go встроен, профиль `.conf` исполняется как
`type: wireguard` с `amnezia-wg-option`. Отдельно собирать нечего.

## 6. Локализация (en / ru / de / zh / fa)

Источник строк — ARB: `lib/l10n/app_en.arb` (база) и `app_ru/de/zh/fa.arb`. Новая строка
добавляется **во все пять** файлов, иначе в пропущенном языке будет пустой ключ. Генерация
идёт при `flutter pub get` / `flutter run` (или `flutter gen-l10n`).
`app_localizations*.dart` руками не редактируются.

## 7. Релиз

Релизы собирает GitHub: Actions → **release** → Run workflow.
`.github/workflows/release.yml` собирает APK, архив и установщик для Windows на Windows-раннере
(`tool/make_release.ps1 -SkipLinux`), пакеты Linux в контейнере Ubuntu 22.04
(`tool/build_linux_wsl.sh`, `tool/package_linux.sh`), пишет `SHA256SUMS`
(`tool/write_sha256sums.ps1`), подписывает его (`tool/sign_sums.sh` → `SHA256SUMS.sig`),
прикладывает к каждому файлу подтверждение сборки и оставляет **черновик** релиза. Заметки
пишутся в черновике, публикуется он вручную. Со снятой галочкой «draft» прогон только
собирает, файлы остаются в его артефакте `release-files`. Нужные секреты перечислены в
начале workflow.

Те же пакеты локально, для сравнения или когда GitHub не вариант:

```powershell
# Android + Windows + Linux (эта часть в WSL) + SHA256SUMS → release\<версия>\
powershell -ExecutionPolicy Bypass -File tool\make_release.ps1

# то же с подписью + публикация GitHub-релиза (нужен gh CLI)
powershell -ExecutionPolicy Bypass -File tool\make_release.ps1 -SigningKey <key.pem> -Publish -NotesFile notes.md

# когда релиз уже опубликован: PKGBUILD + .SRCINFO уезжают на AUR
wsl -e bash /mnt/c/Users/<ты>/StudioProjects/keqdroid/tool/publish_aur.sh
```

Проверить скачанный файл вручную:

```bash
gh attestation verify <файл> --repo Lemonochka/keqdroid   # собран workflow этого репозитория
sha256sum -c --ignore-missing SHA256SUMS
```

Правила:

- `SHA256SUMS.sig` это base64 подписи Ed25519 над `SHA256SUMS` байт в байт. Приложение
  (`lib/services/release_signature.dart`) знает два открытых ключа: основной, закрытая
  половина которого лежит в секрете `UPDATE_SIGNING_KEY`, и запасной, который хранится не
  на GitHub. Версии после 0.35.0 без верной подписи не ставят ни обновление, ни полную
  geo-базу, поэтому релиз без `SHA256SUMS.sig` ломает обновления им всем;

- версия и тег `vX.Y.Z` берутся из `version:` в `pubspec.yaml`;
- на весь релиз один `SHA256SUMS` (ASCII без BOM, LF, формат `sha256sum`), и без
  совпавшего хеша апдейтер ничего не установит. Его читают версии с 0.5.0; 0.4.x читает
  только `.sha256` рядом с файлом и обновляется вручную. Имя ассета должно встречаться
  ровно в **одной** строке, потому что апдейтер берёт первую строку, где есть имя;
  `tool/make_release.ps1` это проверяет;
- `geoip.dat.sha256` остаётся: загрузчик geo-базы в 0.15.0 - 0.18.0 просит у последнего
  релиза именно этот файл;
- имена ассетов фиксированные: `keqdroid-<версия>-android.apk`,
  `keqdroid-<версия>-armeabi-v7a-android.apk` (обязан стоять после основного: старые
  апдейтеры берут первый `.apk` в списке GitHub, отсортированном по имени),
  `keqdroid-windows-x64-<версия>.zip` (именно такой порядок слов),
  `keqdroid-windows-x64-<версия>-setup.exe` (апдейтер установленной копии ищет окончание
  `-setup.exe`; портабельная по-прежнему берёт zip, поэтому zip нужен в каждом релизе),
  `keqdroid-<версия>-linux-x64.tar.gz`, `keqdroid_<версия>_amd64.deb`,
  `keqdroid-<версия>-x86_64.AppImage`, `keqdroid-<версия>-1.x86_64.rpm`;
- при ручной сборке проверяй версию APK через `aapt dump badging | grep versionName`
  перед загрузкой: после упавшей сборки в `build/` остаётся прошлый APK.

Подпись exe для Windows через SignPath Foundation встроена, но выключена. Когда проект
примут, на signpath.io ему задаётся такая конфигурация артефакта (workflow отправляет сам
архив релиза, поэтому корень у неё архив):

```xml
<artifact-configuration xmlns="http://signpath.io/artifact-configuration/v1">
  <zip-file>
    <pe-file path="keqdroid.exe" product-name="keqdroid">
      <authenticode-sign/>
    </pe-file>
  </zip-file>
</artifact-configuration>
```

потом в репозитории заводятся переменные `SIGNPATH_ORGANIZATION_ID`,
`SIGNPATH_PROJECT_SLUG`, `SIGNPATH_SIGNING_POLICY_SLUG` и секрет `SIGNPATH_API_TOKEN`.
С этого момента задача `sign-windows` отправляет архив на подпись и ждёт, пока запрос
одобрят на signpath.io. Подписывается только `keqdroid.exe`: `xray.exe` и `mihomo.exe`
собраны из чужих исходников, их SignPath Foundation не подписывает.

Установщик собирается раньше этой задачи из тех же неподписанных файлов, поэтому внутри
него неподписанный `keqdroid.exe`, и сам он тоже не подписан. Прежде чем включать SignPath,
workflow надо научить собирать установщик из подписанных файлов и отправлять на подпись
и `setup.exe`.
