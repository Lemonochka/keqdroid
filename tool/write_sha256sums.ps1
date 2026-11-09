<#
.SYNOPSIS
  Write and check the release-wide SHA256SUMS for every file in a directory.

.DESCRIPTION
  Shared by tool/make_release.ps1 (local build) and .github/workflows/release.yml
  (the release job runs it under pwsh on Linux), so both produce the manifest
  the same way. Skips SHA256SUMS itself, its .sig and the per-file *.sha256
  sidecars. Rewrites geoip.dat.sha256 when geoip.dat is present: the geo base
  download in 0.15.0 - 0.18.0 asks for exactly that name.

  ASCII without BOM and LF line ends: Windows PowerShell 5.1 otherwise writes
  UTF-16 or a BOM, `sha256sum -c` wants LF, and the signature covers the bytes.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool\write_sha256sums.ps1 -Dir release\0.36.0
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Dir
)

$ErrorActionPreference = 'Stop'

function Write-AsciiLf([string]$path, [string[]]$lines) {
  $text = ($lines -join "`n") + "`n"
  [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.ASCIIEncoding))
}

function Get-Sha256([string]$path) {
  (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower()
}

$Dir = (Resolve-Path -LiteralPath $Dir).Path
$sumsPath = Join-Path $Dir 'SHA256SUMS'
Remove-Item -LiteralPath $sumsPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath "$sumsPath.sig" -Force -ErrorAction SilentlyContinue

$geo = Join-Path $Dir 'geoip.dat'
if (Test-Path -LiteralPath $geo) {
  Write-AsciiLf "$geo.sha256" @(Get-Sha256 $geo)
}

$assets = @(Get-ChildItem -LiteralPath $Dir -File |
  Where-Object { $_.Name -ne 'SHA256SUMS' -and $_.Name -ne 'SHA256SUMS.sig' -and $_.Extension -ne '.sha256' } |
  Sort-Object Name)
if ($assets.Count -eq 0) { throw "No release files in $Dir" }
Write-AsciiLf $sumsPath @($assets | ForEach-Object { '{0}  {1}' -f (Get-Sha256 $_.FullName), $_.Name })

$sumLines = Get-Content -LiteralPath $sumsPath
foreach ($line in $sumLines) {
  $hash, $name = $line -split '  ', 2
  if ((Get-Sha256 (Join-Path $Dir $name)) -ne $hash) { throw "SHA256SUMS mismatch for $name" }
  # Every updater so far takes the first line that CONTAINS the asset name. A
  # name that is part of another line would hand it someone else's hash.
  $hits = @($sumLines | Where-Object { $_.ToLower().Contains($name.ToLower()) })
  if ($hits.Count -ne 1) { throw "Asset name $name appears in $($hits.Count) lines of SHA256SUMS" }
}
if ((Test-Path -LiteralPath $geo) -and
    (Get-Content -LiteralPath "$geo.sha256" -Raw).Trim() -ne (Get-Sha256 $geo)) {
  throw "geoip.dat.sha256 mismatch"
}
Write-Host "    SHA256SUMS: $($sumLines.Count) assets OK"
