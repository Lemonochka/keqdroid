# Build the AmneziaWG core for Keqdroid.
#
# Android : libwg-go.so (amneziawg-go via NDK, c-shared) for arm64-v8a and x86_64.
# Windows : wireproxy.exe (wireproxy-awg; embeds amneziawg-go, exposes SOCKS5/HTTP) + wintun.dll.
#           Used for both AmneziaWG proxy mode and TUN mode (TUN: wireproxy -> sing-box).
#
# Requires: Go (https://go.dev), Android NDK (for -Android), git.
#
# Examples:
#   powershell -File tool/build_amneziawg.ps1 -Android
#   powershell -File tool/build_amneziawg.ps1 -Windows
#   powershell -File tool/build_amneziawg.ps1            # both

param(
    [switch]$Windows,
    [switch]$Android,
    [string]$BuildDir = (Join-Path $PSScriptRoot "..\..\awg-build"),
    # wintun.dll (amd64) - official signed build from wintun.net.
    [string]$WintunUrl = "https://www.wintun.net/builds/wintun-0.14.1.zip"
)

$ErrorActionPreference = "Stop"

if (-not $Windows -and -not $Android) {
    $Windows = $true
    $Android = $true
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$go = (Get-Command go -ErrorAction SilentlyContinue)
if (-not $go) { Write-Error "go not found. Install Go: https://go.dev/dl/" }

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

# ---- Android: libwg-go.so --------------------------------------------------
if ($Android) {
    Write-Host "== Building libwg-go.so (amneziawg-go) =="

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

    # libwg-go sources come from amneziawg-android: it has go.mod + jni.c, which cgo
    # compiles into the .so, exposing the org.amnezia.awg.GoBackend JNI symbols.
    $awgAndroid = Join-Path $BuildDir "amneziawg-android"
    if (-not (Test-Path $awgAndroid)) {
        Write-Host "Cloning amneziawg-android..."
        git clone --depth 1 https://github.com/amnezia-vpn/amneziawg-android.git $awgAndroid
    }
    $libwgDir = Join-Path $awgAndroid "tunnel\tools\libwg-go"
    if (-not (Test-Path (Join-Path $libwgDir "go.mod"))) {
        Write-Error "libwg-go sources not found at $libwgDir"
    }

    $jni = Join-Path $repoRoot "android\app\src\main\jniLibs"
    $strip = Join-Path $tc "llvm-strip.exe"

    $targets = @(
        @{ Abi = "arm64-v8a"; GoArch = "arm64"; Cc = "aarch64-linux-android24-clang.cmd" },
        @{ Abi = "x86_64";    GoArch = "amd64"; Cc = "x86_64-linux-android24-clang.cmd" }
    )

    Push-Location $libwgDir
    try {
        foreach ($t in $targets) {
            Write-Host ("Building libwg-go.so for {0}..." -f $t.Abi)
            $outDir = Join-Path $jni $t.Abi
            New-Item -ItemType Directory -Force -Path $outDir | Out-Null
            $out = Join-Path $outDir "libwg-go.so"

            $env:CGO_ENABLED = "1"
            $env:GOOS = "android"
            $env:GOARCH = $t.GoArch
            $env:CC = (Join-Path $tc $t.Cc)

            & $go.Source build -trimpath -buildvcs=false -buildmode=c-shared -o $out
            if ($LASTEXITCODE -ne 0) { Write-Error ("go build failed for {0}" -f $t.Abi) }

            if (Test-Path $strip) { & $strip --strip-unneeded $out }
            # c-shared also emits a .h header next to the .so - drop it from jniLibs.
            Remove-Item -Force (Join-Path $outDir "libwg-go.h") -ErrorAction SilentlyContinue
            Write-Host ("  -> {0}" -f $out)
        }
    }
    finally {
        Pop-Location
        Remove-Item Env:CGO_ENABLED, Env:GOOS, Env:GOARCH, Env:CC -ErrorAction SilentlyContinue
    }
    Write-Host "libwg-go.so built for arm64-v8a and x86_64."
}

# ---- Windows: wireproxy.exe + wintun.dll -----------------------------------
if ($Windows) {
    Write-Host "== Windows core: wireproxy.exe + wintun.dll =="
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $dstDir = Join-Path $repoRoot "assets\bin\windows"
    New-Item -ItemType Directory -Force -Path $dstDir | Out-Null

    # wireproxy.exe (wireproxy-awg) - embeds amneziawg-go, exposes SOCKS5/HTTP.
    # Pure Go (gvisor netstack), no CGO - cross-compiles trivially.
    # Bundled in flutter_assets like xray/sing-box. If Defender keeps eating it,
    # add an exclusion for $repoRoot (it flags the unsigned PE).
    Write-Host "Building wireproxy.exe (wireproxy-awg)..."
    $wp = Join-Path $BuildDir "wireproxy-awg"
    if (-not (Test-Path $wp)) {
        git clone --depth 1 https://github.com/artem-russkikh/wireproxy-awg.git $wp
    }
    Push-Location $wp
    try {
        $env:CGO_ENABLED = "0"
        $env:GOOS = "windows"
        $env:GOARCH = "amd64"
        # Build outside the assets dir first — a failed build must not delete the
        # last known-good wireproxy.exe.
        $built = Join-Path $BuildDir "wireproxy.exe"
        $dst = Join-Path $dstDir "wireproxy.exe"
        # No '-s -w': a stripped Go binary looks more like packed malware to
        # Defender's heuristics. Keeping the symbols costs a few MB and trims
        # one reason it gets flagged as a PUA.
        & $go.Source build -trimpath -o $built ./cmd/wireproxy
        if ($LASTEXITCODE -ne 0) {
            Write-Error @"
wireproxy build failed. If the log mentions 'virus or potentially unwanted software',
Windows Defender is quarantining wireproxy — add an exclusion for:
  $repoRoot
Then re-run: powershell -File tool/build_amneziawg.ps1 -Windows
"@
        }
        Copy-Item -LiteralPath $built -Destination $dst -Force
        Write-Host "  -> assets\bin\windows\wireproxy.exe"
    }
    finally {
        Pop-Location
        Remove-Item Env:CGO_ENABLED, Env:GOOS, Env:GOARCH -ErrorAction SilentlyContinue
    }

    # wintun.dll (amd64) for the sing-box TUN adapter (AmneziaWG TUN mode).
    $wintun = Join-Path $dstDir "wintun.dll"
    if (Test-Path $wintun) {
        Write-Host "  wintun.dll already present, skipping."
    }
    elseif ($WintunUrl) {
        Write-Host ("Downloading wintun from {0} ..." -f $WintunUrl)
        $zip = Join-Path $BuildDir "wintun.zip"
        Invoke-WebRequest -Uri $WintunUrl -OutFile $zip
        $ex = Join-Path $BuildDir "wintun"
        Remove-Item -Recurse -Force $ex -ErrorAction SilentlyContinue
        Expand-Archive -LiteralPath $zip -DestinationPath $ex -Force
        $dll = Get-ChildItem $ex -Recurse -Filter "wintun.dll" |
            Where-Object { $_.FullName -match "amd64" } | Select-Object -First 1
        if ($dll) { Copy-Item -Force $dll.FullName $wintun; Write-Host "  -> wintun.dll" }
        else { Write-Warning "wintun.dll (amd64) not found in archive - place it manually." }
    }
    else {
        Write-Warning "wintun.dll missing - place it in assets\bin\windows\ manually."
    }
}

Write-Host "Done."
