# Building keqdroid

English | [Русский](BUILD.ru.md)

## Requirements

- Flutter 3.44.4, the version CI uses
- Android: Android Studio with the Android SDK, JDK 17 or newer
- Windows: Visual Studio 2022 or newer with the Desktop development with C++ workload
- Linux: Ubuntu 22.04, on its own or in WSL
- Cores: Go and git, plus the Android NDK for the Android cores
- Windows installer: Inno Setup 7.1.1

## Android

```bash
flutter pub get
flutter run                                                  # debug
flutter build apk --release                                  # arm64-v8a
flutter build apk --release --target-platform android-arm    # armeabi-v7a
```

A release build is signed with the key from `android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`) and fails without it. Crashlytics is added only when `android/app/google-services.json` exists.

After changing the Kotlin version in `android/settings.gradle.kts`, run `flutter clean`, otherwise plugins fail with "Unresolved reference".

## Windows

```powershell
flutter pub get
powershell -File tool/sync_windows_plugins.ps1
flutter build windows --release
```

The build lands in `build\windows\x64\runner\Release\`. `sync_windows_plugins.ps1` rewrites the committed plugin list (`windows/flutter/app_plugins.cmake`, `app_plugin_registrant.cc`) without Firebase, which is Android only and breaks the Windows link.

If the build stops with MSB3073 on `INSTALL.vcxproj`, Defender may have removed a core from `assets/bin/windows/`. Restore it with `git restore` and build again.

## Linux

Release packages are built on Ubuntu 22.04. A build made on a newer GLib does not start on Ubuntu 22.04 or Debian 12, and `tool/package_linux.sh` refuses to package it.

On Ubuntu:

```bash
bash tool/build_linux_wsl.sh   # installs the toolchain and Flutter if missing, then builds
bash tool/package_linux.sh     # .deb, .rpm, .AppImage, .tar.gz and PKGBUILD in release/<version>/
```

Flutter comes from `$FLUTTER_HOME` (`~/flutter` by default); if it is not there, the script clones the stable branch. Both scripts work in the repository itself, so they cannot run at the same time as a Windows or Android build.

From Windows, in WSL. Run it from PowerShell: Git Bash rewrites `/mnt/c/...` paths unless `MSYS_NO_PATHCONV=1` is set.

```powershell
wsl -d Ubuntu-22.04 -e bash /mnt/c/<path>/keqdroid/tool/build_linux_native.sh
```

`build_linux_native.sh` copies the project to the WSL disk, runs both scripts there and copies the packages back to `release/<version>/`. This is how `make_release.ps1` builds Linux.

## Checks

```bash
flutter analyze   # must print "No issues found!"
flutter test
```

CI runs both on every push to master and on every pull request.

## Translations

Strings live in `lib/l10n/app_en.arb` and in `app_ru`, `app_de`, `app_zh`, `app_fa`. A new string goes into all five. `flutter pub get` generates `app_localizations*.dart` from them; those files are not edited by hand.

## Cores

The built cores are in the repository: `assets/bin/windows/`, `assets/bin/linux/` and `android/app/src/main/jniLibs/<abi>/`. They only need rebuilding to update a core or a patch.

```powershell
powershell -File tool/build_xray_cores.ps1   # xray for Android, Windows, Linux
powershell -File tool/build_mihomo.ps1       # mihomo for Android, Windows, Linux
powershell -File tool/fetch_xray_geo.ps1     # geoip.dat and geosite.dat
dart run tool/geo_lite.dart                  # the trimmed geoip for the APK
```

Both build scripts take `-Target android|windows|linux`. The mihomo version is `-Version` in its script. xray is built from the revision pinned in the `go.mod` of a [keqrnel](https://github.com/Lemonochka/keqrnel) checkout next to this repository (`-Keqrnel <path>` for another location). The scripts pin the Go toolchain themselves.

mihomo gets `tool/patches/mihomo-*.patch` and `sing-tun-*.patch`. xray gets keqrnel's `patches/xray-*.patch`, then `tool/patches/xray-*.patch`. A patch that does not apply stops the build. What each patch fixes and what to check on an update is written in its header.

Windows cores are not fully stripped (`-w`, not `-s -w`) and must not be started from `%TEMP%`: Defender blocks an unsigned exe in either case.

## Release

Releases are built on GitHub: Actions → release → Run workflow. `.github/workflows/release.yml` builds every file, writes and signs `SHA256SUMS`, attests the files and leaves a draft release. Write the notes in the draft and publish it. With draft unticked, the run only builds and keeps the files in its `release-files` artifact. The secrets it needs are listed at the top of the workflow.

Locally, the same files go to `release\<version>\`:

```powershell
powershell -ExecutionPolicy Bypass -File tool\make_release.ps1
powershell -ExecutionPolicy Bypass -File tool\make_release.ps1 -SigningKey key.pem -Publish -NotesFile notes.md
```

`-Publish` creates the GitHub release through `gh` and requires `-SigningKey`. `-SkipAndroid`, `-SkipWindows`, `-SkipInstaller` and `-SkipLinux` leave parts out. Once the release is public, `tool/publish_aur.sh` pushes the PKGBUILD to the AUR package `keqdroid-bin`; this needs an AUR account with the machine's SSH key.

What the app expects from a release:

- The version and the `vX.Y.Z` tag come from `version:` in `pubspec.yaml`.
- `SHA256SUMS.sig` is an Ed25519 signature of `SHA256SUMS`. Without it, versions after 0.35.0 install no update and no full geo base. The key is the `UPDATE_SIGNING_KEY` secret; the app also accepts a reserve key kept off GitHub (`lib/services/release_signature.dart`).
- `SHA256SUMS` names each file in exactly one line: the updater takes the first line that contains the name.
- The APKs and the Windows zip go through `tool/repack_zip.dart`: the same deflate, at 7-Zip's maximum, every file inside unchanged. The APK is then signed again with the same key and only the v2 scheme, like AGP signs it. The Android updater builds the new APK from the installed one and downloads only the entries whose compressed bytes changed, so an unchanged core costs nothing as long as every release is packed the same way.
- File names never change. Installed versions look for exactly these:

```
keqdroid-<version>-android.apk
keqdroid-<version>-armeabi-v7a-android.apk
keqdroid-windows-x64-<version>.zip
keqdroid-windows-x64-<version>-setup.exe
keqdroid-<version>-linux-x64.tar.gz
keqdroid_<version>_amd64.deb
keqdroid-<version>-1.x86_64.rpm
keqdroid-<version>-x86_64.AppImage
geoip.dat
geoip.dat.sha256
```

`geoip.dat.sha256` is for versions 0.15.0 to 0.18.0, which download the geo base by that name. A portable Windows copy updates from the zip and an installed one from `setup.exe`, so every release carries both.

Checking a downloaded file:

```bash
gh attestation verify <file> --repo Lemonochka/keqdroid
sha256sum -c --ignore-missing SHA256SUMS
```

### Windows code signing

Signing through SignPath Foundation is part of the workflow and stays off until the repository has the variables `SIGNPATH_ORGANIZATION_ID`, `SIGNPATH_PROJECT_SLUG`, `SIGNPATH_SIGNING_POLICY_SLUG` and the secret `SIGNPATH_API_TOKEN`. Without them the same files are built unsigned. With them, a release makes two signing requests, and under the release policy each waits to be approved on signpath.io:

1. `sign-windows` sends the release zip together with the Inno Setup uninstaller. Only `keqdroid.exe` and the uninstaller are signed: `xray.exe` and `mihomo.exe` are upstream builds.
2. `installer` builds `setup.exe` from these signed files, and `sign-installer` sends it.

Inno Setup signs its uninstaller only while compiling, so `tool/build_windows_installer.ps1` takes it out of one compile (`-ExportUninstaller`) and puts the signed copy into the next (`-SignedUninstaller`). Inno refuses a signed file that differs from its own in anything but the signature.

The `test-signing` policy signs with a test certificate that Windows does not trust. Such a run is only a check: untick draft and do not publish its files.

Artifact configurations in the SignPath project:

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

Inno pads the product name in its version resource with spaces to 60 characters, so the uninstaller and `setup.exe` are matched by file name only.
