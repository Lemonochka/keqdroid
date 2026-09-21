# Build the mihomo core for Keqdroid.
#
# Three targets, one source tree:
#
#   android - libmihomo.so (arm64-v8a), a plain executable rather than a
#             library. It goes into jniLibs because that is the only directory
#             Android extracts with the exec bit set; KeqdisVpnService
#             fork+execv's it (see NativeHelper.startCore).
#   windows - assets/bin/windows/mihomo.exe
#   linux   - assets/bin/linux/mihomo
#
# Desktop binaries are laid next to the app executable by CMake, exactly like
# keqrnel; they are NOT declared as Flutter assets (Flutter packs assets into
# every platform, and desktop cores once dragged ~150 MB into the APK).
#
# All targets carry -tags with_gvisor: the gVisor stack is what mihomo uses
# when it owns the TUN device - the wintun adapter on Windows, the fd handed
# over by VpnService on Android. A core built without the tag parses such a
# config fine and then dies on start with "gVisor is not included in this
# build", which reads as "TUN did not start" and nothing else.
#
# They also carry no_tailscale and no_zerotier, which drop two whole embedded
# network stacks the client can never reach - see $BuildTags below for the
# numbers and the reasoning.
#
# The Windows binary is deliberately NOT stripped: a stripped, unsigned exe next
# to the app is a Defender heuristic, and the core went to quarantine mid-build
# over it. Nothing of the kind applies elsewhere, so Android and Linux are built
# with -s -w: it takes 18 MB off this core on Linux, and 13 MB off what the
# user downloads. Go still prints stack traces with function names without the
# symbol table, so nothing is lost for debugging.
#
# The build is NOT stock upstream: tool/patches/*.patch are applied first and
# the script fails if any of them does not apply. Read the patch headers before
# bumping -Version - they explain what they fix and what to keep in step.
#
# Requires: Go (https://go.dev), git. Android NDK only for -Target android.
#
# Examples:
#   powershell -File tool/build_mihomo.ps1
#   powershell -File tool/build_mihomo.ps1 -Target windows
#   powershell -File tool/build_mihomo.ps1 -Version v1.19.32

param(
    [string]$Version = "v1.19.31",
    [ValidateSet("all", "android", "windows", "linux")]
    [string]$Target = "all",
    [string]$BuildDir = (Join-Path $PSScriptRoot "..\..\mihomo-build")
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$go = (Get-Command go -ErrorAction SilentlyContinue)
if (-not $go) { Write-Error "go not found. Install Go: https://go.dev/dl/" }
$git = (Get-Command git -ErrorAction SilentlyContinue)
if (-not $git) { Write-Error "git not found (needed to apply tool/patches)." }

$wantAndroid = ($Target -eq "all") -or ($Target -eq "android")
$wantWindows = ($Target -eq "all") -or ($Target -eq "windows")
$wantLinux = ($Target -eq "all") -or ($Target -eq "linux")

# ---- NDK -------------------------------------------------------------------
# Only android needs it, and even there only for the C toolchain path; the
# build itself is CGO_ENABLED=0. Desktop-only runs must not require an NDK.
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

# ---- Sources ---------------------------------------------------------------
# Taken from the module cache rather than a git clone: `go mod download` pins
# the exact published module, checksum included, and cannot drift with a moved
# tag. The cache is read-only, so we work on a copy.
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
$src = Join-Path $BuildDir "mihomo-$Version"

if (Test-Path $src) {
    Write-Host "Removing previous source tree..."
    # Module-cache copies are read-only; clear the bit or Remove-Item fails.
    Get-ChildItem $src -Recurse -Force | ForEach-Object { $_.Attributes = 'Normal' }
    Remove-Item -Recurse -Force $src
}

Write-Host "Downloading github.com/metacubex/mihomo@$Version ..."
Push-Location $BuildDir
try {
    if (-not (Test-Path (Join-Path $BuildDir "go.mod"))) {
        & $go.Source mod init keqdroid-mihomo-build | Out-Null
    }
    # No -x, and no stderr redirection: -x writes its trace to stderr, and
    # redirecting a native command's stderr in PowerShell 5.1 wraps every line
    # in a NativeCommandError, which $ErrorActionPreference = "Stop" turns into
    # an abort. That killed the script on the first line of download progress --
    # and only ever on a version bump, because a cached module prints nothing.
    & $go.Source mod download "github.com/metacubex/mihomo@$Version"
    if ($LASTEXITCODE -ne 0) { Write-Error "go mod download failed for $Version" }
    $modCache = (& $go.Source env GOMODCACHE).Trim()
}
finally { Pop-Location }

$cached = Join-Path $modCache "github.com\metacubex\mihomo@$Version"
if (-not (Test-Path $cached)) { Write-Error "module not found in cache: $cached" }

Write-Host "Copying sources to $src ..."
Copy-Item -Recurse -Force $cached $src
Get-ChildItem $src -Recurse -Force | ForEach-Object { $_.Attributes = 'Normal' }

# ---- Patches ---------------------------------------------------------------
# Hard failure on a patch that no longer applies is the point: a silently
# unpatched core looks healthy and fails only against particular servers, which
# is exactly the kind of bug that costs days to find.
$patches = Get-ChildItem (Join-Path $PSScriptRoot "patches") -Filter "mihomo-*.patch" | Sort-Object Name
if ($patches.Count -eq 0) { Write-Error "no mihomo patches found in tool/patches" }

Push-Location $src
try {
    foreach ($p in $patches) {
        Write-Host ("Applying {0} ..." -f $p.Name)
        & $git.Source apply --verbose --whitespace=nowarn $p.FullName
        if ($LASTEXITCODE -ne 0) {
            Write-Error ("patch {0} does not apply to mihomo {1} - rebase it before building" -f $p.Name, $Version)
        }
    }
}
finally { Pop-Location }

# ---- Build -----------------------------------------------------------------
# -checklinkname=0: mihomo's TLS stack reaches into runtime internals with
# //go:linkname, which Go 1.23+ refuses by default.
$versionFlag = '-X "github.com/metacubex/mihomo/constant.Version={0}"' -f $Version

# Теги сборки.
#
#   with_gvisor  - обязателен, см. шапку файла.
#   no_tailscale - выкидывает клиент Tailscale.
#   no_zerotier  - выкидывает клиент ZeroTier.
#   no_easytier  - выкидывает клиент EasyTier (появился в v1.19.31).
#
# Последние три — не экономия на спичках: каждый тянет собственный сетевой стек.
# Tailscale с ZeroTier вдвоём дают 8.4 МБ из 52 у android-бинарника (52 232 545 ->
# 43 385 185 при прочих равных, замерено на v1.19.30), а один EasyTier — ещё 10.8 МБ
# (54 722 913 -> 43 909 473 на v1.19.31; на десктопе около 12 МБ). Без его тега
# патч-релиз 1.19.30 -> 1.19.31 раздул бы бинарь на 11 МБ, и по одному размеру
# было бы не понять, откуда.
#
# Выкинуть их можно потому, что это mesh-VPN, а не прокси: наш генератор их не
# выпускает, а в подписочных Clash-конфигах их не бывает. Остальные экзотические
# аутбаунды (mieru, anytls, masque, openvpn, ssh, snell, ssr) тегов не имеют, и
# резать их пришлось бы форком — а чужие конфиги клиент импортирует как серверы,
# и какой протокол принесут завтра, мы не выбираем.
#
# Побочный эффект ровно как у gvisor: конфиг с `type: tailscale` не запустится,
# ядро скажет, что этого в сборке нет.
$BuildTags = "with_gvisor,no_tailscale,no_zerotier,no_easytier"

function Build-Mihomo {
    param(
        [string]$Goos,
        [string]$Goarch,
        [string]$OutPath,
        [string]$Ldflags,
        [string]$Cc,
        [string]$Label
    )

    $outDir = Split-Path -Parent $OutPath
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null

    Push-Location $src
    try {
        $env:CGO_ENABLED = "0"
        $env:GOOS = $Goos
        $env:GOARCH = $Goarch
        if ($Cc) { $env:CC = $Cc }

        Write-Host "Building $Label ..."
        & $go.Source build -trimpath -buildvcs=false -tags $BuildTags `
            -ldflags $Ldflags `
            -o $OutPath .
        if ($LASTEXITCODE -ne 0) { Write-Error "go build failed for $Label" }
    }
    finally {
        Pop-Location
        Remove-Item Env:CGO_ENABLED, Env:GOOS, Env:GOARCH -ErrorAction SilentlyContinue
        if ($Cc) { Remove-Item Env:CC -ErrorAction SilentlyContinue }
    }

    $size = (Get-Item $OutPath).Length
    Write-Host ("  -> {0} ({1:N0} bytes)" -f $OutPath, $size)
}

if ($wantAndroid) {
    Build-Mihomo `
        -Goos "android" -Goarch "arm64" `
        -OutPath (Join-Path $repoRoot "android\app\src\main\jniLibs\arm64-v8a\libmihomo.so") `
        -Ldflags ("-s -w -checklinkname=0 {0}" -f $versionFlag) `
        -Cc (Join-Path $tc "aarch64-linux-android24-clang.cmd") `
        -Label "libmihomo.so for arm64-v8a"
}

if ($wantWindows) {
    Build-Mihomo `
        -Goos "windows" -Goarch "amd64" `
        -OutPath (Join-Path $repoRoot "assets\bin\windows\mihomo.exe") `
        -Ldflags ("-checklinkname=0 {0}" -f $versionFlag) `
        -Label "mihomo.exe for windows/amd64"
}

if ($wantLinux) {
    Build-Mihomo `
        -Goos "linux" -Goarch "amd64" `
        -OutPath (Join-Path $repoRoot "assets\bin\linux\mihomo") `
        -Ldflags ("-s -w -checklinkname=0 {0}" -f $versionFlag) `
        -Label "mihomo for linux/amd64"
}

Write-Host "Done. Patched mihomo $Version built (target: $Target)."
