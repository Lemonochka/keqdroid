# Build xray for every platform from one patched xray-core:
#
#   android - libxray.so (arm64-v8a and armeabi-v7a)
#   windows - assets/bin/windows/xray.exe
#   linux   - assets/bin/linux/xray
#
# The keqrnel checkout owns the patched tree: its tools/patchxray takes the
# revision pinned in keqrnel's go.mod, applies keqrnel's patches/xray-*.patch,
# then tool/patches/xray-*.patch from this repository (-extra), and writes a
# module file that points the build at that tree. Every dependency comes from
# keqrnel's go.mod, so every platform runs the same Xray. The patch headers say
# what each one fixes. keqrnel itself (xray inside sing-box) is no longer
# built: on the desktop xray owns the TUN.
#
# libxray.so, like libmihomo.so, is a plain executable in jniLibs: that is the
# only directory Android extracts with the exec bit set (see build_mihomo.ps1).
# -checklinkname=0: the anet dependency links into net.zoneCache in the
# standard library, which Go 1.26+ rejects without the flag.
#
# Windows gets -w only: a fully stripped unsigned exe next to the app is a
# Defender heuristic, see build_mihomo.ps1. Linux gets -s -w.
#
# Android links with --pack-dyn-relocs=android: the relocation table, 4.1 MB of
# plain RELA in the arm64 core, is stored packed (Android 6+, minSdk is 24) and
# the core takes 3.4 MB less on the phone. The dynamic linker unpacks it before
# Go starts, so the running core is the same. RELR would pack it tighter but
# needs Android 9.
#
# Requires: Go, git, a keqrnel checkout next to this repository. Android NDK
# only for -Target android.
#
# Examples:
#   powershell -File tool/build_xray_cores.ps1
#   powershell -File tool/build_xray_cores.ps1 -Target windows

param(
    [ValidateSet("all", "android", "windows", "linux")]
    [string]$Target = "all",
    [string]$Keqrnel = (Join-Path $PSScriptRoot "..\..\keqrnel")
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$go = (Get-Command go -ErrorAction SilentlyContinue)
if (-not $go) { Write-Error "go not found. Install Go: https://go.dev/dl/" }
# pinned: without it the go line in keqrnel's go.mod picks the oldest 1.27.x, security fixes included or not
$env:GOTOOLCHAIN = "go1.27.3"
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "git not found (tools/patchxray applies the patches with it)."
}

$wantAndroid = ($Target -eq "all") -or ($Target -eq "android")
$wantWindows = ($Target -eq "all") -or ($Target -eq "windows")
$wantLinux = ($Target -eq "all") -or ($Target -eq "linux")

$Keqrnel = (Resolve-Path $Keqrnel).Path
if (-not (Test-Path (Join-Path $Keqrnel "tools\patchxray"))) {
    Write-Error "keqrnel checkout with tools/patchxray not found: $Keqrnel"
}

# ---- NDK -------------------------------------------------------------------
$tc = $null
if ($wantAndroid) {
    $ndk = $env:ANDROID_NDK_HOME
    if (-not $ndk) {
        $sdk = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT }
               elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME }
               else { Join-Path $env:LOCALAPPDATA "Android\Sdk" }
        $ndkRoot = Join-Path $sdk "ndk"
        if (Test-Path $ndkRoot) {
            $ndk = (Get-ChildItem $ndkRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1).FullName
        }
    }
    if (-not $ndk -or -not (Test-Path $ndk)) {
        Write-Error "Android NDK not found. Set ANDROID_NDK_HOME or install NDK via Android Studio."
    }
    Write-Host "Using NDK: $ndk"
    $tc = Join-Path $ndk "toolchains\llvm\prebuilt\windows-x86_64\bin"
}

# ---- Patched xray-core -----------------------------------------------------
# No stderr redirection around go: in PowerShell 5.1 it turns download
# progress into NativeCommandError and aborts the script (see build_mihomo.ps1).
function Prepare-Xray {
    param([string]$Src, [string]$ModFile, [string]$Extra)

    Push-Location $Keqrnel
    try {
        $toolArgs = @("run", "./tools/patchxray", "-src", $Src, "-modfile", $ModFile)
        if ($Extra) { $toolArgs += @("-extra", $Extra) }
        & $go.Source @toolArgs
        if ($LASTEXITCODE -ne 0) { Write-Error "tools/patchxray failed for $ModFile" }
    }
    finally { Pop-Location }
}

# ---- Build -----------------------------------------------------------------
function Build-Core {
    param(
        [string]$ModFile,
        [string]$Goos,
        [string]$Goarch,
        [string]$Goarm,
        [string]$Goarm64,
        [string]$Cc,
        [string]$Tags,
        [string]$Gcflags,
        [string]$Ldflags,
        [string]$Package,
        [string]$OutPath,
        [string]$Label
    )

    Push-Location $Keqrnel
    try {
        $env:CGO_ENABLED = if ($Cc) { "1" } else { "0" }
        $env:GOOS = $Goos
        $env:GOARCH = $Goarch
        if ($Goarm) { $env:GOARM = $Goarm }
        if ($Goarm64) { $env:GOARM64 = $Goarm64 }
        if ($Cc) { $env:CC = $Cc }

        $buildArgs = @("build", "-modfile=$ModFile", "-trimpath", "-buildvcs=false")
        if ($Tags) { $buildArgs += @("-tags", $Tags) }
        if ($Gcflags) { $buildArgs += $Gcflags }
        $buildArgs += @("-ldflags", $Ldflags, "-o", $OutPath, $Package)

        Write-Host "Building $Label ..."
        & $go.Source @buildArgs
        if ($LASTEXITCODE -ne 0) { Write-Error "go build failed for $Label" }
    }
    finally {
        Pop-Location
        Remove-Item Env:CGO_ENABLED, Env:GOOS, Env:GOARCH -ErrorAction SilentlyContinue
        if ($Goarm) { Remove-Item Env:GOARM -ErrorAction SilentlyContinue }
        if ($Goarm64) { Remove-Item Env:GOARM64 -ErrorAction SilentlyContinue }
        if ($Cc) { Remove-Item Env:CC -ErrorAction SilentlyContinue }
    }

    $size = (Get-Item $OutPath).Length
    Write-Host ("  -> {0} ({1:N0} bytes)" -f $OutPath, $size)
}

Prepare-Xray -Src ".build/xray-android" -ModFile "go.android.mod" -Extra (Join-Path $PSScriptRoot "patches")

if ($wantWindows) {
    Build-Core -ModFile "go.android.mod" -Goos "windows" -Goarch "amd64" -Ldflags "-w" `
        -Package "github.com/xtls/xray-core/main" `
        -OutPath (Join-Path $repoRoot "assets\bin\windows\xray.exe") `
        -Label "xray.exe for windows/amd64"
}

if ($wantLinux) {
    Build-Core -ModFile "go.android.mod" -Goos "linux" -Goarch "amd64" -Ldflags "-s -w" `
        -Package "github.com/xtls/xray-core/main" `
        -OutPath (Join-Path $repoRoot "assets\bin\linux\xray") `
        -Label "xray for linux/amd64"
}

if ($wantAndroid) {
    Build-Core -ModFile "go.android.mod" -Goos "android" -Goarch "arm64" -Goarm64 "v8.0" `
        -Cc (Join-Path $tc "aarch64-linux-android21-clang.cmd") `
        -Gcflags "-gcflags=all=-l=4" -Ldflags "-s -w -checklinkname=0 -extldflags=-Wl,--pack-dyn-relocs=android" `
        -Package "github.com/xtls/xray-core/main" `
        -OutPath (Join-Path $repoRoot "android\app\src\main\jniLibs\arm64-v8a\libxray.so") `
        -Label "libxray.so for arm64-v8a"
    Build-Core -ModFile "go.android.mod" -Goos "android" -Goarch "arm" -Goarm "7" `
        -Cc (Join-Path $tc "armv7a-linux-androideabi21-clang.cmd") `
        -Gcflags "-gcflags=all=-l=4" -Ldflags "-s -w -checklinkname=0 -extldflags=-Wl,--pack-dyn-relocs=android" `
        -Package "github.com/xtls/xray-core/main" `
        -OutPath (Join-Path $repoRoot "android\app\src\main\jniLibs\armeabi-v7a\libxray.so") `
        -Label "libxray.so for armeabi-v7a"
}

Write-Host "Done. Patched xray built (target: $Target)."
