<#
.SYNOPSIS
  Build keqdroid for every platform, package the release assets and write one
  SHA256SUMS that covers all of them.

.DESCRIPTION
  Produces, under release\<version>\:
    keqdroid-<version>-android.apk              (Android)
    keqdroid-windows-x64-<version>.zip          (Windows portable)
    keqdroid-<version>-x86_64.AppImage          (Linux)
    keqdroid_<version>_amd64.deb                (Debian / Ubuntu)
    keqdroid-<version>-1.x86_64.rpm             (Fedora / openSUSE)
    keqdroid-<version>-linux-x64.tar.gz         (Linux portable, the AUR source)
    PKGBUILD                                    (Arch, for a manual makepkg)
    aur\PKGBUILD, aur\.SRCINFO                  (what tool/publish_aur.sh pushes)
    geoip.dat, geoip.dat.sha256                 (full geo database for Android)
    SHA256SUMS                                  (sha256sum format, every asset)

  The in-app updater refuses any asset it cannot verify. Every version since
  0.5.0 reads the hash from a release-wide SHA256SUMS, so assets no longer need
  a .sha256 of their own. The one exception is geoip.dat.sha256: the full geo
  base download in 0.15.0 - 0.18.0 fetches it from the LATEST release and asks
  for exactly that name.

  Linux is built inside WSL by tool/build_linux_native.sh.

  Checksum files are ASCII without BOM and with LF line ends: Windows
  PowerShell 5.1 otherwise writes UTF-16 or a BOM, and `sha256sum -c` wants LF.

.PARAMETER SkipAndroid
  Do not build/package the APK.

.PARAMETER SkipWindows
  Do not build/package the Windows zip.

.PARAMETER SkipLinux
  Do not build the Linux packages in WSL.

.PARAMETER NoClean
  Skip `flutter clean`. A release should not: persistent build directories
  carry stale files into the packages.

.PARAMETER WslDistro
  WSL distribution that builds Linux.

.PARAMETER Publish
  Create the GitHub release via the `gh` CLI and upload all assets.

.PARAMETER NotesFile
  Markdown file used as the release body when -Publish is set.

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
  [switch]$SkipLinux,
  [switch]$NoClean,
  [string]$WslDistro = 'Ubuntu-24.04',
  [switch]$Publish,
  [string]$NotesFile
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

# ASCII, no BOM, LF (see the note in the header).
function Write-AsciiLf([string]$path, [string[]]$lines) {
  $text = ($lines -join "`n") + "`n"
  [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.ASCIIEncoding))
}

function Get-Sha256([string]$path) {
  (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower()
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
if (-not $SkipAndroid) {
  Write-Step "Building Android APK"
  # --target-platform android-arm64 — не «оптимизация на всякий случай».
  # Без него Flutter компилирует свой движок и AOT-снимок Dart ещё под
  # armeabi-v7a и x86_64: это 22.5 МБ из 87.5 в опубликованном APK. Работать там
  # приложению всё равно нечем — все четыре ядра собраны только под arm64
  # (`abiFilters` в android/app/build.gradle.kts), так что на этих архитектурах
  # оно устанавливалось и не поднимало туннель.
  flutter build apk --release --target-platform android-arm64
  if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed" }

  $apkSrc = Join-Path $repoRoot 'build\app\outputs\flutter-apk\app-release.apk'
  if (-not (Test-Path -LiteralPath $apkSrc)) { throw "APK not found at $apkSrc" }

  # "-android" в имени — как во всех опубликованных релизах; апдейтер ищет
  # просто *.apk, ему суффикс не важен.
  $apkOut = Join-Path $outDir "keqdroid-$version-android.apk"
  Copy-Item -LiteralPath $apkSrc -Destination $apkOut -Force
  Write-Host "    $(Split-Path $apkOut -Leaf) ($([math]::Round((Get-Item -LiteralPath $apkOut).Length / 1MB, 1)) MB)"
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
  foreach ($core in @('keqrnel.exe', 'mihomo.exe', 'wintun.dll')) {
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

  $zipOut = Join-Path $outDir "keqdroid-windows-x64-$version.zip"
  if (Test-Path -LiteralPath $zipOut) { Remove-Item -LiteralPath $zipOut -Force }
  # Zip the contents so keqdroid.exe sits at the archive root (the updater's
  # findPayloadRoot expects keqdroid.exe at root or in a single subfolder).
  Compress-Archive -Path (Join-Path $relDir '*') -DestinationPath $zipOut
  Write-Host "    $(Split-Path $zipOut -Leaf) ($([math]::Round((Get-Item -LiteralPath $zipOut).Length / 1MB, 1)) MB)"
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
Write-AsciiLf "$geoOut.sha256" @(Get-Sha256 $geoOut)
Write-Host ("    geoip.dat OK ({0} MB)" -f [math]::Round((Get-Item -LiteralPath $geoOut).Length / 1MB, 1))

# --- SHA256SUMS --------------------------------------------------------------
Write-Step "Writing SHA256SUMS"
$sumsPath = Join-Path $outDir 'SHA256SUMS'
$assets = Get-ChildItem -LiteralPath $outDir -File |
  Where-Object { $_.Name -ne 'SHA256SUMS' -and $_.Extension -ne '.sha256' } |
  Sort-Object Name
Write-AsciiLf $sumsPath @($assets | ForEach-Object { '{0}  {1}' -f (Get-Sha256 $_.FullName), $_.Name })

Write-Step "Verifying checksums"
$sumLines = Get-Content -LiteralPath $sumsPath
foreach ($line in $sumLines) {
  $hash, $name = $line -split '  ', 2
  if ((Get-Sha256 (Join-Path $outDir $name)) -ne $hash) { throw "SHA256SUMS mismatch for $name" }
  # Every updater so far takes the first line that CONTAINS the asset name. A
  # name that is part of another line would hand it someone else's hash.
  $hits = @($sumLines | Where-Object { $_.ToLower().Contains($name.ToLower()) })
  if ($hits.Count -ne 1) { throw "Asset name $name appears in $($hits.Count) lines of SHA256SUMS" }
}
if ((Get-Content -LiteralPath "$geoOut.sha256" -Raw).Trim() -ne (Get-Sha256 $geoOut)) {
  throw "geoip.dat.sha256 mismatch"
}
Write-Host "    $($sumLines.Count) assets OK"

Write-Host ""
Write-Step "Artifacts in $outDir"
Get-ChildItem -LiteralPath $outDir -File | Select-Object Name, Length | Format-Table -AutoSize

# --- Publish ---------------------------------------------------------------
if ($Publish) {
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
