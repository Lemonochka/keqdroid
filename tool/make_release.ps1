<#
.SYNOPSIS
  Build keqdroid, package release assets, generate SHA-256 sidecars, and
  (optionally) publish a GitHub release.

.DESCRIPTION
  Produces, under release\<version>\:
    keqdroid-<version>.apk                      (Android)
    keqdroid-<version>.apk.sha256
    keqdroid-windows-x64-<version>.zip          (Windows portable)
    keqdroid-windows-x64-<version>.zip.sha256

  The in-app updater (UpdateService) refuses to install any asset whose
  matching <asset>.sha256 is missing or does not match. Every published
  release MUST therefore carry the sidecars this script generates.

  Sidecars are written as ASCII without BOM on purpose: Windows PowerShell 5.1
  otherwise emits UTF-16/BOM, which corrupts generated files.

.PARAMETER SkipAndroid
  Do not build/package the APK.

.PARAMETER SkipWindows
  Do not build/package the Windows zip.

.PARAMETER Publish
  Create the GitHub release via the `gh` CLI and upload all assets.

.PARAMETER NotesFile
  Markdown file used as the release body when -Publish is set.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool\make_release.ps1
  # build everything + sha256, no upload

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool\make_release.ps1 -Publish -NotesFile notes.md
#>
[CmdletBinding()]
param(
  [switch]$SkipAndroid,
  [switch]$SkipWindows,
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

# --- version from pubspec.yaml: "version: 0.4.9+1" -> "0.4.9", tag "v0.4.9" ---
$pubspec = Get-Content (Join-Path $repoRoot 'pubspec.yaml') -Raw
$m = [regex]::Match($pubspec, '(?m)^\s*version:\s*([0-9]+\.[0-9]+(?:\.[0-9]+)?)')
if (-not $m.Success) { throw "Could not read version from pubspec.yaml" }
$version = $m.Groups[1].Value
$tag = "v$version"
Write-Step "Releasing $tag"

$outDir = Join-Path $repoRoot "release\$version"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

# ASCII, no BOM (avoids the cp1251/UTF-8 trap that breaks the updater).
function Write-Sha256Sidecar([string]$assetPath) {
  $hash = (Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash.ToLower()
  $sidecar = "$assetPath.sha256"
  [System.IO.File]::WriteAllText($sidecar, $hash, (New-Object System.Text.ASCIIEncoding))
  Write-Host "    sha256 $([System.IO.Path]::GetFileName($assetPath)) = $hash"
}

Write-Step "flutter pub get"
flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }

# --- Android ---------------------------------------------------------------
if (-not $SkipAndroid) {
  Write-Step "Building Android APK"
  flutter build apk --release
  if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed" }

  $apkSrc = Join-Path $repoRoot 'build\app\outputs\flutter-apk\app-release.apk'
  if (-not (Test-Path -LiteralPath $apkSrc)) { throw "APK not found at $apkSrc" }

  $apkOut = Join-Path $outDir "keqdroid-$version.apk"
  Copy-Item -LiteralPath $apkSrc -Destination $apkOut -Force
  Write-Sha256Sidecar $apkOut
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
  # sha256 but ships a broken app (no xray/sing-box/AmneziaWG, no TUN adapter).
  # CMake copies assets/bin/windows/*.{exe,dll} next to keqdroid.exe.
  foreach ($core in @('keqrnel.exe', 'wireproxy.exe', 'wintun.dll')) {
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

  $zipOut = Join-Path $outDir "keqdroid-windows-x64-$version.zip"
  if (Test-Path -LiteralPath $zipOut) { Remove-Item -LiteralPath $zipOut -Force }
  # Zip the contents so keqdroid.exe sits at the archive root (the updater's
  # findPayloadRoot expects keqdroid.exe at root or in a single subfolder).
  Compress-Archive -Path (Join-Path $relDir '*') -DestinationPath $zipOut
  Write-Sha256Sidecar $zipOut
}

# --- Verify sidecars match (cheap sanity) ----------------------------------
Write-Step "Verifying sidecars"
Get-ChildItem -LiteralPath $outDir -Filter '*.sha256' | ForEach-Object {
  $asset = $_.FullName.Substring(0, $_.FullName.Length - '.sha256'.Length)
  $expected = (Get-Content -LiteralPath $_.FullName -Raw).Trim().ToLower()
  $actual = (Get-FileHash -LiteralPath $asset -Algorithm SHA256).Hash.ToLower()
  if ($expected -ne $actual) { throw "Sidecar mismatch for $asset" }
}
Write-Host "    all sidecars OK"

Write-Host ""
Write-Step "Artifacts in $outDir"
Get-ChildItem -LiteralPath $outDir | Select-Object Name, Length | Format-Table -AutoSize

# --- Publish ---------------------------------------------------------------
if ($Publish) {
  $gh = Get-Command gh -ErrorAction SilentlyContinue
  if (-not $gh) { throw "gh CLI not found on PATH; install it or upload manually." }

  $assets = Get-ChildItem -LiteralPath $outDir -File | ForEach-Object { $_.FullName }
  $ghArgs = @('release', 'create', $tag) + $assets + @('--title', $tag)
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
  Write-Host "Not published. To upload manually:" -ForegroundColor Yellow
  Write-Host "  gh release create $tag $outDir\* --title $tag --generate-notes"
}
