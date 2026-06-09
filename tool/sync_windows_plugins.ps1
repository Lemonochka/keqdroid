# Regenerates Windows plugin files without firebase_core (Android-only Crashlytics).
# Run after: flutter pub get
# Usage: powershell -File tool/sync_windows_plugins.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$flutterDir = Join-Path $root 'windows/flutter'

$generatedCmake = Join-Path $flutterDir 'generated_plugins.cmake'
$generatedRegistrant = Join-Path $flutterDir 'generated_plugin_registrant.cc'
$appCmake = Join-Path $flutterDir 'app_plugins.cmake'
$appRegistrant = Join-Path $flutterDir 'app_plugin_registrant.cc'

if (-not (Test-Path $generatedCmake)) {
    throw 'Missing generated_plugins.cmake. Run flutter pub get first.'
}

function Filter-FirebasePluginLines([string[]]$lines) {
    $lines | Where-Object { $_ -notmatch '^\s*firebase_core\s*$' }
}

function Filter-FirebaseRegistrant([string]$text) {
    $text `
        -replace '#include <firebase_core/firebase_core_plugin_c_api\.h>\r?\n', '' `
        -replace '\s*FirebaseCorePluginCApiRegisterWithRegistrar\(\s*\r?\n\s*registry->GetRegistrarForPlugin\("FirebaseCorePluginCApi"\)\);\r?\n', "`n"
}

# --- app_plugins.cmake ---
$cmakeHeader = @(
    '# Windows plugins for keqdroid (firebase_core excluded — Crashlytics is Android-only).',
    '# Regenerate after adding plugins: powershell -File tool/sync_windows_plugins.ps1',
    ''
)
$cmakeBody = Get-Content $generatedCmake | Select-Object -Skip 3
$cmakeFiltered = Filter-FirebasePluginLines $cmakeBody
[System.IO.File]::WriteAllLines($appCmake, ($cmakeHeader + $cmakeFiltered))
Write-Host "Wrote $appCmake"

# --- app_plugin_registrant.cc ---
$regHeader = @(
    '// Windows plugin registration (firebase_core excluded — Crashlytics is Android-only).',
    '// Regenerate after adding plugins: powershell -File tool/sync_windows_plugins.ps1',
    ''
)
$regText = [System.IO.File]::ReadAllText($generatedRegistrant)
$regFiltered = Filter-FirebaseRegistrant $regText
$regFiltered = $regFiltered -replace '// clang-format off\r?\n\r?\n#include "generated_plugin_registrant.h"\r?\n\r?\n', ''
$regBody = $regFiltered -replace '(?s)^.*?#include "generated_plugin_registrant.h"\r?\n\r?\n', ''
$regOut = ($regHeader -join "`n") + "#include `"generated_plugin_registrant.h`"`n`n" + $regBody.TrimStart()
[System.IO.File]::WriteAllText($appRegistrant, $regOut)
Write-Host "Wrote $appRegistrant"
Write-Host 'Done.'
