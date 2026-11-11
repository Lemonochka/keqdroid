<#
.SYNOPSIS
  Build keqdroid for every platform, package the release assets and write one
  SHA256SUMS that covers all of them.

.DESCRIPTION
  Produces, under release\<version>\:
    keqdroid-<version>-android.apk              (Android, arm64-v8a)
    keqdroid-<version>-armeabi-v7a-android.apk  (Android on a 32-bit firmware)
    keqdroid-windows-x64-<version>.zip          (Windows portable)
    keqdroid-windows-x64-<version>-setup.exe    (Windows installer)
    keqdroid-<version>-x86_64.AppImage          (Linux)
    keqdroid_<version>_amd64.deb                (Debian / Ubuntu)
    keqdroid-<version>-1.x86_64.rpm             (Fedora / openSUSE)
    keqdroid-<version>-linux-x64.tar.gz         (Linux portable, the AUR source)
    PKGBUILD                                    (Arch, for a manual makepkg)
    aur\PKGBUILD, aur\.SRCINFO                  (what tool/publish_aur.sh pushes)
    geoip.dat, geoip.dat.sha256                 (full geo database for Android)
    SHA256SUMS                                  (sha256sum format, every asset)
    SHA256SUMS.sig                              (only with -SigningKey)

  Releases are normally built by .github/workflows/release.yml, which also
  signs SHA256SUMS. This script is the local twin: same packages, same
  checks, signed only with -SigningKey. The app refuses an update or geo base
  whose SHA256SUMS lacks a valid SHA256SUMS.sig.

  Every version since 0.5.0 reads the hash from a release-wide SHA256SUMS
  (tool/write_sha256sums.ps1). The one sidecar left is geoip.dat.sha256: the
  full geo base download in 0.15.0 - 0.18.0 asks for exactly that name.

  Linux is built inside WSL by tool/build_linux_native.sh.

.PARAMETER SkipAndroid
  Do not build/package the APK.

.PARAMETER SkipWindows
  Do not build/package the Windows zip and installer.

.PARAMETER SkipInstaller
  Package the Windows zip but not the installer. An installed copy then
  updates from the zip, and Windows keeps showing its old version.

.PARAMETER Iscc
  Path to ISCC.exe of Inno Setup 7.1.1. By default the usual install folders
  of Inno Setup 7 are searched.

.PARAMETER SkipLinux
  Do not build the Linux packages in WSL.

.PARAMETER NoClean
  Skip `flutter clean`. A release should not: persistent build directories
  carry stale files into the packages.

.PARAMETER WslDistro
  WSL distribution that builds Linux. Ubuntu 22.04 on purpose: a build made on
  a newer GLib does not start on Ubuntu 22.04 or Debian 12, and
  tool/package_linux.sh refuses to package one.

.PARAMETER Publish
  Create the GitHub release via the `gh` CLI and upload all assets. Needs
  -SigningKey.

.PARAMETER SigningKey
  Update signing key (Ed25519 PEM) for tool/sign_sums.sh, run in Git Bash.

.PARAMETER NotesFile
  Markdown file used as the release body when -Publish is set.

.PARAMETER AllowUnmerged
  Build even though a worktree holds commits this checkout lacks or has
  uncommitted changes. Without it the script stops and lists them.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool\make_release.ps1
  # build everything + SHA256SUMS, no upload

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool\make_release.ps1 -Publish -NotesFile notes.md
#>
[CmdletBinding()]
param(
  [switch]$SkipAndroid,
  [switch]$SkipWindows,
  [switch]$SkipInstaller,
  [string]$Iscc,
  [switch]$SkipLinux,
  [switch]$NoClean,
  [string]$WslDistro = 'Ubuntu-22.04',
  [switch]$Publish,
  [string]$NotesFile,
  [string]$SigningKey,
  [switch]$AllowUnmerged
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

function Repair-PubCacheEnv {
  # WSL/Docker sometimes leave PUB_CACHE=C:\root\.pub-cache on Windows hosts.
  # flutter gen-l10n runs dart format, which resolves package:flutter_lints via
  # PUB_CACHE — a missing cache path aborts `flutter build apk`.
  $windowsCache = Join-Path $env:LOCALAPPDATA 'Pub\Cache'
  if (-not (Test-Path -LiteralPath $windowsCache)) { return }

  $broken = $false
  if ($env:PUB_CACHE) {
    $hosted = Join-Path $env:PUB_CACHE 'hosted'
    if (-not (Test-Path -LiteralPath $hosted)) { $broken = $true }
  }

  if ($broken -or -not $env:PUB_CACHE) {
    if ($env:PUB_CACHE -and $broken) {
      Write-Host "WARN: PUB_CACHE=$($env:PUB_CACHE) is invalid; using $windowsCache" -ForegroundColor Yellow
    }
    $env:PUB_CACHE = $windowsCache
  }
}

Repair-PubCacheEnv

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

# --- Work left in other worktrees -------------------------------------------
# A feature finished in a Claude worktree stays on its own branch until it is
# merged, and a release built here ships without it: 0.34.0 went out without
# the home screen widget that was committed on claude/eloquent-euclid-1538b7.
# flutter regenerates the plugin registrants on every run, they do not count.
if (-not $AllowUnmerged) {
  $left = @()
  $path = $null
  foreach ($line in (git worktree list --porcelain)) {
    if ($line.StartsWith('worktree ')) {
      $path = $line.Substring(9)
      $dirty = @(git -C $path status --porcelain | Where-Object { $_ -notmatch '/flutter/generated_plugin' })
      if ($dirty.Count -gt 0) { $left += "  $path : $($dirty.Count) uncommitted change(s)" }
    } elseif ($line.StartsWith('branch refs/heads/')) {
      $branch = $line.Substring(18)
      # by content, not hash: a commit cherry-picked into this checkout counts as in
      $ahead = @(git cherry HEAD "refs/heads/$branch" | Where-Object { $_.StartsWith('+') }).Count
      if ($ahead -gt 0) { $left += "  $branch : $ahead commit(s) not in this checkout ($path)" }
    }
  }
  if ($left.Count -gt 0) {
    Write-Host "Work that this release would not contain:" -ForegroundColor Yellow
    $left | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
    throw "Merge or commit it first, or rerun with -AllowUnmerged if it is meant to stay out."
  }
}

# An APK carries native code for exactly one ABI, and all of it. A second ABI
# is dead weight (the other set of cores alone is ~80 MB); a missing core
# installs fine and never brings the tunnel up.
function Assert-ApkAbi([string]$apk, [string]$abi) {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [System.IO.Compression.ZipFile]::OpenRead($apk)
  try {
    $libs = @($zip.Entries | Where-Object { $_.FullName -like 'lib/*/*' } | ForEach-Object { $_.FullName })
  } finally {
    $zip.Dispose()
  }
  $abis = @($libs | ForEach-Object { $_.Split('/')[1] } | Sort-Object -Unique)
  if ($abis.Count -ne 1 -or $abis[0] -ne $abi) {
    throw "APK for $abi must carry only lib/$abi, found: $($abis -join ', ')"
  }
  foreach ($so in @('libflutter.so', 'libapp.so', 'libxray.so', 'libmihomo.so', 'libkeqdroid_native.so')) {
    if ($libs -notcontains "lib/$abi/$so") { throw "APK for $abi lacks lib/$abi/$so" }
  }
  Write-Host "    lib/$abi only, all native code present"
}

# --- version from pubspec.yaml: "version: 0.4.9+1" -> "0.4.9", tag "v0.4.9" ---
$pubspec = Get-Content (Join-Path $repoRoot 'pubspec.yaml') -Raw
$m = [regex]::Match($pubspec, '(?m)^\s*version:\s*([0-9]+\.[0-9]+(?:\.[0-9]+)?)')
if (-not $m.Success) { throw "Could not read version from pubspec.yaml" }
$version = $m.Groups[1].Value
$tag = "v$version"
Write-Step "Releasing $tag"

$outDir = Join-Path $repoRoot "release\$version"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

# Per-asset sidecars from an earlier run would ride along into the upload and
# put every file into the release twice, which is exactly what SHA256SUMS
# replaces. geoip.dat.sha256 is rewritten below.
Get-ChildItem -LiteralPath $outDir -Filter '*.sha256' -File -ErrorAction SilentlyContinue |
  Remove-Item -Force
Remove-Item -LiteralPath (Join-Path $outDir 'SHA256SUMS') -Force -ErrorAction SilentlyContinue

if (-not $NoClean) {
  Write-Step "flutter clean"
  flutter clean
  if ($LASTEXITCODE -ne 0) { throw "flutter clean failed" }
}

Write-Step "flutter pub get"
flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }

# --- Android ---------------------------------------------------------------
# Two APKs, one ABI each. arm64-v8a is the main one; armeabi-v7a is for phones
# whose vendor ships a 32-bit Android on a 64-bit chip (Redmi 9A/9C), where an
# arm64 APK does not install at all.
#
# The 32-bit name must sort AFTER the main one. Every updater released before
# it takes the first *.apk of the release, and GitHub lists assets by name,
# case-insensitively, not by upload time. "android-armeabi-v7a" would sort
# first ('-' < '.') and hand 32-bit cores to every arm64 phone on update;
# "armeabi-v7a-android" parts from "android" at 'r' > 'n'. The new updater
# picks by ABI and does not care.
#
# --target-platform is not an optimisation. Without it Flutter also compiles
# its engine and the Dart AOT snapshot for the other ABIs (22.5 MB of 87.5 in
# a published APK), and app/build.gradle.kts picks the APK's ABI from it.
if (-not $SkipAndroid) {
  $apks = @(
    @{ Platform = 'android-arm64'; Abi = 'arm64-v8a';   Name = "keqdroid-$version-android.apk" },
    @{ Platform = 'android-arm';   Abi = 'armeabi-v7a'; Name = "keqdroid-$version-armeabi-v7a-android.apk" }
  )
  if ([string]::Compare($apks[0].Name, $apks[1].Name, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
    throw "$($apks[1].Name) must sort after $($apks[0].Name): older updaters take the first APK"
  }

  $apkSrc = Join-Path $repoRoot 'build\app\outputs\flutter-apk\app-release.apk'
  foreach ($apk in $apks) {
    Write-Step "Building Android APK ($($apk.Abi))"
    # Gone before the build, so a build that silently produced nothing cannot
    # ship the previous ABI's APK under this name.
    if (Test-Path -LiteralPath $apkSrc) { Remove-Item -LiteralPath $apkSrc -Force }
    flutter build apk --release --target-platform $apk.Platform
    if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed for $($apk.Abi)" }
    if (-not (Test-Path -LiteralPath $apkSrc)) { throw "APK not found at $apkSrc" }
    Assert-ApkAbi $apkSrc $apk.Abi

    $apkOut = Join-Path $outDir $apk.Name
    Copy-Item -LiteralPath $apkSrc -Destination $apkOut -Force
    Write-Host "    $($apk.Name) ($([math]::Round((Get-Item -LiteralPath $apkOut).Length / 1MB, 1)) MB)"
  }
}

# --- Windows ---------------------------------------------------------------
if (-not $SkipWindows) {
  Write-Step "Syncing Windows plugins (strip Firebase)"
  powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'sync_windows_plugins.ps1')
  if ($LASTEXITCODE -ne 0) { throw "sync_windows_plugins.ps1 failed" }

  Write-Step "Building Windows (Release)"
  flutter build windows --release
  if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed" }

  $relDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'
  if (-not (Test-Path -LiteralPath (Join-Path $relDir 'keqdroid.exe'))) {
    throw "keqdroid.exe not found in $relDir"
  }
  foreach ($geo in @('geoip.dat', 'geosite.dat')) {
    $geoPath = Join-Path $relDir $geo
    if (-not (Test-Path -LiteralPath $geoPath)) {
      throw "Missing $geo in Windows build output ($relDir). CMake should copy assets/bin/windows/*.dat."
    }
    $size = (Get-Item -LiteralPath $geoPath).Length
    if ($size -lt 1MB) {
      throw "$geo looks truncated ($size bytes) in $relDir"
    }
    Write-Host "    $geo OK ($([math]::Round($size / 1MB, 1)) MB)"
  }
  # Fail closed if the cores are missing: a zip without them generates a valid
  # sha256 but ships a broken app (no cores, no TUN adapter).
  # CMake copies assets/bin/windows/*.{exe,dll} next to keqdroid.exe.
  foreach ($core in @('xray.exe', 'mihomo.exe', 'wintun.dll')) {
    $corePath = Join-Path $relDir $core
    if (-not (Test-Path -LiteralPath $corePath)) {
      throw "Missing $core in Windows build output ($relDir). CMake should copy assets/bin/windows/. Did you build the core?"
    }
    $size = (Get-Item -LiteralPath $corePath).Length
    if ($size -lt 100KB) {
      throw "$core looks truncated ($size bytes) in $relDir"
    }
    Write-Host "    $core OK ($([math]::Round($size / 1MB, 1)) MB)"
  }
  # A clean Windows has no VC++ runtime; without these the exe does not start.
  foreach ($dll in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
    if (-not (Test-Path -LiteralPath (Join-Path $relDir $dll))) {
      throw "Missing $dll in Windows build output ($relDir). windows/CMakeLists.txt installs the VC++ runtime next to keqdroid.exe."
    }
  }
  Write-Host "    VC++ runtime OK"

  # Гео-базы в бандле лежат ДВАЖДЫ, и вторая копия — мёртвый груз.
  #
  # Рядом с exe их кладёт CMake, оттуда их и читает ядро (GeoAssetService._geoDir
  # на Windows возвращает каталог рядом с исполняемым файлом). Вторая копия
  # приезжает во flutter_assets: базы объявлены ассетами Flutter ради ANDROID —
  # там их достаёт XrayGeoAssets через AssetManager, — а Flutter пакует ассеты во
  # все платформы разом. На десктопе этот путь не читает никто.
  #
  # Цена дубля: 6.0 МБ в zip и 27.5 МБ на диске после установки. Linux-упаковщик
  # вырезает его давно (tool/package_linux.sh), Windows — не вырезал.
  foreach ($dup in @('data\flutter_assets\assets\bin\windows',
                     'data\flutter_assets\assets\geo')) {
    $dupPath = Join-Path $relDir $dup
    if (Test-Path -LiteralPath $dupPath) {
      Remove-Item -LiteralPath $dupPath -Recurse -Force
      Write-Host "    pruned $dup"
    }
  }

  # Шрифт иконок десктопная сборка Flutter не ужимает (флаг уходит в кавычках,
  # см. шапку скрипта): без этого шага в пакете весь 1.6 МБ вместо 26 КБ.
  Write-Step "Tree-shaking the icon font"
  powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'shake_icon_font.ps1') -BundleDir $relDir
  if ($LASTEXITCODE -ne 0) { throw "shake_icon_font.ps1 failed" }

  $zipOut = Join-Path $outDir "keqdroid-windows-x64-$version.zip"
  if (Test-Path -LiteralPath $zipOut) { Remove-Item -LiteralPath $zipOut -Force }
  # Zip the contents so keqdroid.exe sits at the archive root (the updater's
  # findPayloadRoot expects keqdroid.exe at root or in a single subfolder).
  Compress-Archive -Path (Join-Path $relDir '*') -DestinationPath $zipOut
  Write-Host "    $(Split-Path $zipOut -Leaf) ($([math]::Round((Get-Item -LiteralPath $zipOut).Length / 1MB, 1)) MB)"

  if (-not $SkipInstaller) {
    Write-Step "Building the Windows installer"
    if (-not $Iscc) {
      $Iscc = @(
        (Join-Path $env:ProgramFiles 'Inno Setup 7\ISCC.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 7\ISCC.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 7\ISCC.exe')
      ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    }
    if (-not $Iscc -or -not (Test-Path -LiteralPath $Iscc)) {
      throw "Inno Setup 7 (ISCC.exe) not found. Install Inno Setup 7.1.1, pass -Iscc, or -SkipInstaller."
    }
    & $Iscc /Q "/DAppVersion=$version" "/DBuildDir=$relDir" "/DOutputDir=$outDir" `
      (Join-Path $repoRoot 'windows\installer\keqdroid.iss')
    if ($LASTEXITCODE -ne 0) { throw "ISCC failed" }
    $setupOut = Join-Path $outDir "keqdroid-windows-x64-$version-setup.exe"
    if (-not (Test-Path -LiteralPath $setupOut)) { throw "ISCC did not produce $setupOut" }
    Write-Host "    $(Split-Path $setupOut -Leaf) ($([math]::Round((Get-Item -LiteralPath $setupOut).Length / 1MB, 1)) MB)"
  }
}

# --- Linux (in WSL) ----------------------------------------------------------
if (-not $SkipLinux) {
  Write-Step "Building Linux packages in WSL ($WslDistro)"
  $root = $repoRoot.Path
  $wslRepo = '/mnt/' + $root.Substring(0, 1).ToLower() + $root.Substring(2).Replace('\', '/')
  wsl -d $WslDistro -e bash "$wslRepo/tool/build_linux_native.sh"
  if ($LASTEXITCODE -ne 0) { throw "Linux build in WSL failed" }
  foreach ($f in @(
      "keqdroid-$version-x86_64.AppImage",
      "keqdroid_$($version)_amd64.deb",
      "keqdroid-$version-1.x86_64.rpm",
      "keqdroid-$version-linux-x64.tar.gz",
      'PKGBUILD',
      'aur\PKGBUILD',
      'aur\.SRCINFO')) {
    if (-not (Test-Path -LiteralPath (Join-Path $outDir $f))) {
      throw "The Linux build did not produce $f"
    }
  }
}

# --- Full geo database ------------------------------------------------------
# The APK carries a trimmed geoip.dat (four codes, 0.6 MB) — see
# tool/geo_lite.dart. GeoBaseDownloader fetches the full one from the LATEST
# release, so every release has to carry it. Its own .sha256 stays: the
# downloader in 0.15.0 - 0.18.0 knows no other place to look.
Write-Step "Publishing the full geo database"
$geoSrc = Join-Path $repoRoot 'assets\bin\windows\geoip.dat'
if (-not (Test-Path -LiteralPath $geoSrc)) { throw "full geoip.dat not found at $geoSrc" }
$geoOut = Join-Path $outDir 'geoip.dat'
Copy-Item -LiteralPath $geoSrc -Destination $geoOut -Force
Write-Host ("    geoip.dat OK ({0} MB)" -f [math]::Round((Get-Item -LiteralPath $geoOut).Length / 1MB, 1))

# --- SHA256SUMS --------------------------------------------------------------
# One script for this and for .github/workflows/release.yml.
Write-Step "Writing SHA256SUMS"
powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'write_sha256sums.ps1') -Dir $outDir
if ($LASTEXITCODE -ne 0) { throw "write_sha256sums.ps1 failed" }

if ($SigningKey) {
  Write-Step "Signing SHA256SUMS"
  # Git Bash, not the bash on PATH: that one may be WSL, which sees other paths
  $gitBash = Join-Path $env:ProgramFiles 'Git\bin\bash.exe'
  if (-not (Test-Path -LiteralPath $gitBash)) { throw "Git Bash not found at $gitBash" }
  & $gitBash (Join-Path $PSScriptRoot 'sign_sums.sh').Replace('\', '/') `
    (Join-Path $outDir 'SHA256SUMS').Replace('\', '/') `
    (Resolve-Path -LiteralPath $SigningKey).Path.Replace('\', '/')
  if ($LASTEXITCODE -ne 0) { throw "sign_sums.sh failed" }
}

Write-Host ""
Write-Step "Artifacts in $outDir"
Get-ChildItem -LiteralPath $outDir -File | Select-Object Name, Length | Format-Table -AutoSize

# --- Publish ---------------------------------------------------------------
if ($Publish) {
  if (-not (Test-Path -LiteralPath (Join-Path $outDir 'SHA256SUMS.sig'))) {
    throw "SHA256SUMS is not signed (pass -SigningKey): the app would refuse this release."
  }
  $gh = Get-Command gh -ErrorAction SilentlyContinue
  if (-not $gh) { throw "gh CLI not found on PATH; install it or upload manually." }

  # Top-level files only: aur\ is pushed to AUR by tool/publish_aur.sh, and a
  # release asset named .SRCINFO would be renamed by GitHub anyway.
  $files = Get-ChildItem -LiteralPath $outDir -File | ForEach-Object { $_.FullName }
  $ghArgs = @('release', 'create', $tag) + $files + @('--title', $tag)
  if ($NotesFile -and (Test-Path -LiteralPath $NotesFile)) {
    $ghArgs += @('--notes-file', $NotesFile)
  } else {
    $ghArgs += @('--generate-notes')
  }

  Write-Step "Creating GitHub release $tag"
  & gh @ghArgs
  if ($LASTEXITCODE -ne 0) { throw "gh release create failed" }
  Write-Host "    published $tag" -ForegroundColor Green
} else {
  Write-Host ""
  Write-Host "Not published. Upload every file in $outDir (not the aur folder) to the $tag release." -ForegroundColor Yellow
}
