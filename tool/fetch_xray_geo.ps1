# Downloads xray geoip.dat / geosite.dat into assets/bin/windows/ for Android + Windows bundles.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $root 'assets\bin\windows'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$geoipUrl = 'https://github.com/v2fly/geoip/releases/latest/download/geoip.dat'
$geositeUrl = 'https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat'

Invoke-WebRequest -Uri $geoipUrl -OutFile (Join-Path $outDir 'geoip.dat') -UseBasicParsing
Invoke-WebRequest -Uri $geositeUrl -OutFile (Join-Path $outDir 'geosite.dat') -UseBasicParsing

Write-Host "Saved geoip.dat and geosite.dat to $outDir"
