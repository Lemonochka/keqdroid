# Rebuilds the bundled xray geo databases in assets/bin/windows/.
#
# Base is v2fly (countries + the domain-list-community categories). On top of it
# we append a few codes that people actually ask for and v2fly does not ship:
#   geoip:  telegram, google, netflix, twitter, facebook, cloudflare,
#           cloudfront, fastly, tor   (from Loyalsoldier/v2ray-rules-dat)
#   geoip:  refilter                  (from 1andrevich/Re-filter-lists)
#   geosite: refilter                 (from 1andrevich/Re-filter-lists)
#
# Appending works because both files are protobuf `repeated entry = 1`, so a
# concatenation of records is still a valid message. Base codes win on conflict
# (the core resolves a duplicate code to the first record), so the merge never
# rewrites v2fly country data.
#
# Sources are downloaded fresh every run, which makes the result idempotent.
# ASCII only: non-ASCII in this file breaks release builds (cp1251 vs UTF-8).

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $root 'assets\bin\windows'
$tmpDir = Join-Path $env:TEMP ('keqdroid_geo_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

$geoip = Join-Path $outDir 'geoip.dat'
$geosite = Join-Path $outDir 'geosite.dat'

function Get-File([string]$Url, [string]$Path) {
    Write-Host "GET $Url"
    Invoke-WebRequest -Uri $Url -OutFile $Path -UseBasicParsing
    $kib = [math]::Round((Get-Item $Path).Length / 1KB)
    Write-Host ("    {0} KiB -> {1}" -f $kib, $Path)
}

function Merge-Codes([string]$Base, [string]$Source, [string]$Codes) {
    Push-Location $root
    try {
        & dart run tool/geo_merge.dart --base $Base --source $Source --codes $Codes
        if ($LASTEXITCODE -ne 0) { throw "geo_merge failed for $Source (exit $LASTEXITCODE)" }
    } finally {
        Pop-Location
    }
}

try {
    # 1. base databases (v2fly)
    Get-File 'https://github.com/v2fly/geoip/releases/latest/download/geoip.dat' $geoip
    Get-File 'https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat' $geosite

    # 2. extra sources
    $loyalGeoip = Join-Path $tmpDir 'loyalsoldier_geoip.dat'
    $refilterGeoip = Join-Path $tmpDir 'refilter_geoip.dat'
    $refilterGeosite = Join-Path $tmpDir 'refilter_geosite.dat'
    Get-File 'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat' $loyalGeoip
    Get-File 'https://github.com/1andrevich/Re-filter-lists/releases/latest/download/geoip.dat' $refilterGeoip
    Get-File 'https://github.com/1andrevich/Re-filter-lists/releases/latest/download/geosite.dat' $refilterGeosite

    # 3. merge the extra codes into the bundled databases
    Merge-Codes $geoip $loyalGeoip 'telegram,google,netflix,twitter,facebook,cloudflare,cloudfront,fastly,tor'
    Merge-Codes $geoip $refilterGeoip 'refilter'
    Merge-Codes $geosite $refilterGeosite 'refilter'

    Write-Host ''
    Write-Host ("geoip.dat   {0} KiB" -f [math]::Round((Get-Item $geoip).Length / 1KB))
    Write-Host ("geosite.dat {0} KiB" -f [math]::Round((Get-Item $geosite).Length / 1KB))
    Write-Host "Saved to $outDir"
    # Android re-extracts automatically: XrayGeoAssets compares the bundled asset
    # size with the extracted copy, so a rebuilt database always lands on device.
    Write-Host 'Commit the updated .dat files; devices re-extract them on the next app update.'
} finally {
    Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
}
