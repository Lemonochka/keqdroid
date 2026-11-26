# Сборка keqdroid

[English](BUILD.md) | Русский

## Что нужно

- Flutter 3.44.4, та же версия, что в CI
- Android: Android Studio с Android SDK, JDK 17 или новее
- Windows: Visual Studio 2022 или новее с нагрузкой Desktop development with C++
- Linux: Ubuntu 22.04, отдельно или в WSL
- macOS: macOS 13 или новее с Xcode Command Line Tools
- ядра: Go и git, для ядер Android ещё Android NDK
- установщик Windows: Inno Setup 7.1.1

## Android

```bash
flutter pub get
flutter run                                                  # отладка
flutter build apk --release                                  # arm64-v8a
flutter build apk --release --target-platform android-arm    # armeabi-v7a
```

Релизная сборка подписывается ключом из `android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`) и без него падает.

После смены версии Kotlin в `android/settings.gradle.kts` нужен `flutter clean`, иначе плагины падают с "Unresolved reference".

## Windows

```powershell
flutter pub get
flutter build windows --release
```

Готовая сборка лежит в `build\windows\x64\runner\Release\`.

Если сборка встала с MSB3073 на `INSTALL.vcxproj`, возможно, Defender унёс ядро из `assets/bin/windows/`. Его возвращают через `git restore` и собирают заново.

## Linux

Релизные пакеты собираются на Ubuntu 22.04. Сборка на более новой GLib не запускается на Ubuntu 22.04 и Debian 12, и `tool/package_linux.sh` её не пакует.

На Ubuntu:

```bash
bash tool/build_linux_wsl.sh   # ставит тулчейн и Flutter, если их нет, и собирает
bash tool/package_linux.sh     # .deb, .rpm, .AppImage, .tar.gz и PKGBUILD в release/<версия>/
```

Flutter берётся из `$FLUTTER_HOME` (по умолчанию `~/flutter`), а если его там нет, скрипт клонирует ветку stable. Оба скрипта работают прямо в репозитории, поэтому одновременно со сборкой под Windows или Android их не запускают.

Из Windows через WSL. Запускать из PowerShell: Git Bash переделывает пути `/mnt/c/...`, если не задать `MSYS_NO_PATHCONV=1`.

```powershell
wsl -d Ubuntu-22.04 -e bash /mnt/c/<путь>/keqdroid/tool/build_linux_native.sh
```

`build_linux_native.sh` копирует проект на диск WSL, запускает там оба скрипта и возвращает пакеты в `release/<версия>/`. Так Linux собирает `make_release.ps1`.

## macOS

Поддерживаются отдельные сборки для Apple Silicon (`arm64`) и Intel (`x86_64`). Собранные ядра для macOS не хранятся в git — их нужно собрать локально перед сборкой приложения:

```bash
bash tool/build_macos_cores.sh          # собирает отдельно ядра для arm64 и x86_64
bash tool/build_macos_cores.sh native   # только под текущую архитектуру (arm64 или x86_64)
flutter pub get
flutter build macos --release
```

Сборка и упаковка отдельных `.dmg` в `release/<версия>/`:

```bash
bash tool/package_macos.sh all          # оба DMG: arm64 и x86_64
bash tool/package_macos.sh arm64        # только Apple Silicon
bash tool/package_macos.sh x86_64       # только Intel
```

Фаза сборки Xcode копирует `assets/bin/macos/<arch>/{xray,mihomo,keqdroid-tun}` и `assets/bin/macos/{geoip.dat,geosite.dat}` в `keqdroid.app/Contents/Resources/bin/`, а `tool/package_macos.sh` вырезает лишний срез из `.app` через `lipo -thin`. Для подписи сертификатом Developer ID вместо ad-hoc задайте переменную `MACOS_SIGN_IDENTITY`.

## Проверки

```bash
flutter analyze   # должно напечатать "No issues found!"
flutter test
```

CI запускает обе команды на каждый пуш в master и на каждый pull request.

## Переводы

Строки лежат в `lib/l10n/app_en.arb` и в `app_ru`, `app_de`, `app_zh`, `app_fa`. Новая строка добавляется во все пять. Из них `flutter pub get` генерирует `app_localizations*.dart`, эти файлы руками не правят.

## Ядра

Собранные ядра лежат в репозитории: `assets/bin/windows/`, `assets/bin/linux/` и `android/app/src/main/jniLibs/<abi>/`. Пересобирать их нужно, только чтобы обновить ядро или патч.

```powershell
powershell -File tool/build_xray_cores.ps1   # xray под Android, Windows, Linux
powershell -File tool/build_mihomo.ps1       # mihomo под Android, Windows, Linux
powershell -File tool/fetch_xray_geo.ps1     # geoip.dat и geosite.dat
dart run tool/geo_lite.dart                  # урезанный geoip для APK
```

Оба скрипта сборки принимают `-Target android|windows|linux`. Версия mihomo задаётся параметром `-Version` в его скрипте. xray собирается из ревизии, закреплённой в `go.mod` клона [keqrnel](https://github.com/Lemonochka/keqrnel) рядом с этим репозиторием (другое место: `-Keqrnel <путь>`). Версию Go скрипты закрепляют сами.

На mihomo ложатся `tool/patches/mihomo-*.patch` и `sing-tun-*.patch`. На xray сначала `patches/xray-*.patch` из keqrnel, потом `tool/patches/xray-*.patch`. Если патч не лёг, сборка останавливается. Что чинит патч и что сверить при обновлении, написано в его шапке.

Ядра для Windows стрипаются не полностью (`-w`, а не `-s -w`), и запускать их из `%TEMP%` нельзя: в обоих случаях Defender блокирует неподписанный exe.

## Выпуск

Релизы собирает GitHub: Actions → release → Run workflow. `.github/workflows/release.yml` собирает все файлы, пишет и подписывает `SHA256SUMS`, прикладывает к файлам аттестацию сборки и оставляет черновик релиза. Заметки пишутся в черновике, публикуется он вручную; публикация запускает `.github/workflows/nix.yml`, который обновляет Nix flake в ветке `nix` по подписанному `SHA256SUMS`. Если снять галочку draft, прогон только соберёт файлы и оставит их в артефакте `release-files`. Нужные секреты перечислены в начале workflow.

Локально те же файлы собираются в `release\<версия>\`:

```powershell
powershell -ExecutionPolicy Bypass -File tool\make_release.ps1
powershell -ExecutionPolicy Bypass -File tool\make_release.ps1 -SigningKey key.pem -Publish -NotesFile notes.md
```

`-Publish` выкладывает релиз на GitHub через `gh` и без `-SigningKey` не работает. `-SkipAndroid`, `-SkipWindows`, `-SkipInstaller` и `-SkipLinux` пропускают части. Когда релиз опубликован, `tool/publish_aur.sh` отправляет PKGBUILD в пакет `keqdroid-bin` на AUR. Для этого нужен аккаунт AUR с SSH-ключом этой машины.

Что приложение ждёт от релиза:

- Версия и тег `vX.Y.Z` берутся из `version:` в `pubspec.yaml`.
- `SHA256SUMS.sig` это подпись Ed25519 над `SHA256SUMS`. Без неё версии после 0.35.0 не ставят ни обновление, ни полную geo-базу. Ключ лежит в секрете `UPDATE_SIGNING_KEY`, кроме него приложение принимает запасной, который хранится не на GitHub (`lib/services/release_signature.dart`).
- В `SHA256SUMS` каждое имя файла встречается ровно в одной строке: апдейтер берёт первую строку с этим именем.
- APK и архив Windows проходят через `tool/repack_zip.dart`: тот же deflate, только 7-Zip на максимуме, все файлы внутри прежние. Потом APK заново подписывается тем же ключом и только схемой v2, как его подписывает AGP. Апдейтер на Android собирает новый APK из установленного и докачивает только записи, у которых поменялись сжатые байты, поэтому неизменное ядро ничего не стоит, пока каждый релиз упакован одинаково.
- Имена файлов не меняются. Установленные версии ищут именно их:

```
keqdroid-<версия>-android.apk
keqdroid-<версия>-armeabi-v7a-android.apk
keqdroid-windows-x64-<версия>.zip
keqdroid-windows-x64-<версия>-setup.exe
keqdroid-<версия>-linux-x64.tar.gz
keqdroid_<версия>_amd64.deb
keqdroid-<версия>-1.x86_64.rpm
keqdroid-<версия>-x86_64.AppImage
keqdroid-<версия>-macos-arm64.dmg
keqdroid-<версия>-macos-x86_64.dmg
geoip.dat
geoip.dat.sha256
```

`geoip.dat.sha256` нужен версиям с 0.15.0 по 0.18.0, они качают geo-базу по этому имени. Портабельная копия для Windows обновляется из zip, установленная из `setup.exe`, поэтому в каждом релизе есть оба файла.

Проверить скачанный файл:

```bash
gh attestation verify <файл> --repo Lemonochka/keqdroid
sha256sum -c --ignore-missing SHA256SUMS
```

### Подпись для Windows

Подпись через SignPath Foundation встроена в workflow и выключена, пока в репозитории нет переменных `SIGNPATH_ORGANIZATION_ID`, `SIGNPATH_PROJECT_SLUG`, `SIGNPATH_SIGNING_POLICY_SLUG` и секрета `SIGNPATH_API_TOKEN`. Без них те же файлы собираются неподписанными. С ними релиз делает два запроса на подпись, и на боевой политике каждый ждёт одобрения на signpath.io:

1. `sign-windows` отправляет релизный zip вместе с деинсталлятором Inno Setup. Подписываются только `keqdroid.exe` и деинсталлятор: `xray.exe` и `mihomo.exe` собраны из чужих исходников.
2. `installer` собирает `setup.exe` из этих подписанных файлов, `sign-installer` отправляет его.

Inno Setup подписывает свой деинсталлятор только во время компиляции, поэтому `tool/build_windows_installer.ps1` достаёт его из одной компиляции (`-ExportUninstaller`) и вкладывает подписанную копию в следующую (`-SignedUninstaller`). Inno отвергает подписанный файл, если он отличается от его собственного чем-то кроме подписи.

Политика `test-signing` подписывает тестовым сертификатом, которому Windows не доверяет. Такой прогон годится только для проверки: галочку draft снять, файлы не публиковать.

Конфигурации артефактов в проекте SignPath:

`win-files`

```xml
<artifact-configuration xmlns="http://signpath.io/artifact-configuration/v1">
  <zip-file>
    <zip-file path="keqdroid-windows-x64.zip">
      <pe-file path="keqdroid.exe" product-name="keqdroid">
        <authenticode-sign/>
      </pe-file>
    </zip-file>
    <pe-file path="keqdroid-uninstaller.exe">
      <authenticode-sign/>
    </pe-file>
  </zip-file>
</artifact-configuration>
```

`win-setup`

```xml
<artifact-configuration xmlns="http://signpath.io/artifact-configuration/v1">
  <pe-file path="keqdroid-windows-x64-*-setup.exe">
    <authenticode-sign/>
  </pe-file>
</artifact-configuration>
```

Inno дописывает название продукта в версии файла пробелами до 60 знаков, поэтому деинсталлятор и `setup.exe` узнаются только по имени файла.
