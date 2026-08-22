# Build the mihomo core for Keqdroid.
#
# Android: libmihomo.so (arm64-v8a) - a plain executable, not a library. It goes
# into jniLibs because that is the only directory Android extracts with the
# exec bit set; KeqdisVpnService fork+execv's it (see NativeHelper.startCore).
#
# The build is NOT stock upstream: tool/patches/*.patch are applied first and
# the script fails if any of them does not apply. Read the patch headers before
# bumping -Version - they explain what they fix and what to keep in step.
#
# Requires: Go (https://go.dev), Android NDK, git.
#
# Examples:
#   powershell -File tool/build_mihomo.ps1
#   powershell -File tool/build_mihomo.ps1 -Version v1.19.31

param(
    [string]$Version = "v1.19.30",
    [string]$BuildDir = (Join-Path $PSScriptRoot "..\..\mihomo-build")
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$go = (Get-Command go -ErrorAction SilentlyContinue)
if (-not $go) { Write-Error "go not found. Install Go: https://go.dev/dl/" }
$git = (Get-Command git -ErrorAction SilentlyContinue)
if (-not $git) { Write-Error "git not found (needed to apply tool/patches)." }

# ---- NDK -------------------------------------------------------------------
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
    & $go.Source mod download -x "github.com/metacubex/mihomo@$Version" 2>&1 | Out-Null
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
$outDir = Join-Path $repoRoot "android\app\src\main\jniLibs\arm64-v8a"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$out = Join-Path $outDir "libmihomo.so"

Push-Location $src
try {
    $env:CGO_ENABLED = "0"
    $env:GOOS = "android"
    $env:GOARCH = "arm64"
    $env:CC = (Join-Path $tc "aarch64-linux-android24-clang.cmd")

    # -checklinkname=0: mihomo's TLS stack reaches into runtime internals with
    # //go:linkname, which Go 1.23+ refuses by default.
    # No `with_gvisor` tag: we never use mihomo's own tun inbound - the TUN
    # belongs to VpnService and tun2socks, mihomo only serves local SOCKS5.
    Write-Host "Building libmihomo.so for arm64-v8a ..."
    & $go.Source build -trimpath -buildvcs=false `
        -ldflags "-s -w -checklinkname=0" `
        -o $out .
    if ($LASTEXITCODE -ne 0) { Write-Error "go build failed" }
}
finally {
    Pop-Location
    Remove-Item Env:CGO_ENABLED, Env:GOOS, Env:GOARCH, Env:CC -ErrorAction SilentlyContinue
}

$size = (Get-Item $out).Length
Write-Host ("  -> {0} ({1:N0} bytes)" -f $out, $size)
Write-Host "Done. Patched mihomo $Version built for arm64-v8a."
