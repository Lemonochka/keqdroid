# Сборка KpHTTP (rust-kp) для Keqdroid
#
# Требуется: Rust toolchain (https://rustup.rs)
# Android NDK — для кросс-компиляции под arm64/x86_64 (через cargo-ndk или вручную)

param(
    [switch]$Windows,
    [switch]$Android,
    [string]$RustKpRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\rust-kp")).Path
)

$ErrorActionPreference = "Stop"

$cargo = Get-Command cargo -ErrorAction SilentlyContinue
if (-not $cargo) {
    $fallback = Join-Path $env:USERPROFILE ".cargo\bin\cargo.exe"
    if (Test-Path $fallback) {
        $cargo = Get-Item $fallback
    }
}
if (-not $cargo) {
    Write-Error "cargo not found. Install Rust: https://rustup.rs"
}
$cargoExe = if ($cargo.Source) { $cargo.Source } else { $cargo.FullName }

if (-not $Windows -and -not $Android) {
    $Windows = $true
    $Android = $true
}

Push-Location $RustKpRoot
try {
    if ($Windows) {
        Write-Host "Building kphttp-client for Windows x64..."
        & $cargoExe build --release --bin kphttp-client
        $src = Join-Path $RustKpRoot "target\release\kphttp-client.exe"
        $dstDir = Join-Path $PSScriptRoot "..\assets\bin\windows"
        New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
        Copy-Item -Force $src (Join-Path $dstDir "kphttp-client.exe")
        Write-Host "Copied to assets/bin/windows/kphttp-client.exe"
    }

    if ($Android) {
        $ndkHome = $env:ANDROID_NDK_HOME
        if (-not $ndkHome) {
            $sdk = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT }
                   elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME }
                   else { Join-Path $env:LOCALAPPDATA "Android\Sdk" }
            $ndkRoot = Join-Path $sdk "ndk"
            $preferred = Join-Path $ndkRoot "28.2.13676358"
            if (Test-Path $preferred) {
                $ndkHome = $preferred
            } elseif (Test-Path $ndkRoot) {
                $ndkHome = (Get-ChildItem $ndkRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1).FullName
            }
        }
        if (-not $ndkHome -or -not (Test-Path $ndkHome)) {
            Write-Error "Android NDK not found. Set ANDROID_NDK_HOME or install NDK via Android Studio."
        }
        $env:ANDROID_NDK_HOME = $ndkHome
        Write-Host "Using NDK: $ndkHome"

        foreach ($target in @("aarch64-linux-android", "x86_64-linux-android")) {
            & "$env:USERPROFILE\.cargo\bin\rustup.exe" target add $target | Out-Null
        }

        $jniDir = Join-Path $PSScriptRoot "..\android\app\src\main\jniLibs"
        Write-Host "Building kphttp-client for arm64-v8a and x86_64..."
        & $cargoExe ndk `
            -t arm64-v8a `
            -t x86_64 `
            -P 24 `
            build --release --bin kphttp-client

        $map = @{
            "aarch64-linux-android" = "arm64-v8a"
            "x86_64-linux-android"  = "x86_64"
        }
        foreach ($entry in $map.GetEnumerator()) {
            $bin = Join-Path $RustKpRoot "target\$($entry.Key)\release\kphttp-client"
            $outDir = Join-Path $jniDir $entry.Value
            New-Item -ItemType Directory -Force -Path $outDir | Out-Null
            if (-not (Test-Path $bin)) {
                Write-Error "Expected binary not found: $bin"
            }
            Copy-Item -Force $bin (Join-Path $outDir "libkphttp.so")
            Write-Host "Copied libkphttp.so -> jniLibs/$($entry.Value)/"
        }
    }
}
finally {
    Pop-Location
}

Write-Host "Done."
