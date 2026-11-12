<#
.SYNOPSIS
  Build keqdroid-windows-x64-<version>-setup.exe from a ready Windows bundle.

.DESCRIPTION
  Used by tool/make_release.ps1 and .github/workflows/release.yml.

  Inno Setup signs the uninstaller only while compiling, and SignPath signs
  outside the build, so a signed uninstaller takes Inno's two-step
  SignedUninstaller mode: the first compile writes uninst-<inno>-<hash>.e32 and
  stops, the file is signed elsewhere, the second compile embeds it. The hash
  covers the uninstaller bytes, so the same Inno, script and version give the
  same file on any machine, and Inno refuses a signed file that differs.

.PARAMETER ExportUninstaller
  Only write the unsigned uninstaller of this version to the given path, for
  signing. No setup.exe is built.

.PARAMETER SignedUninstaller
  The file from -ExportUninstaller, signed. setup.exe then installs it as
  unins000.exe. Without it the uninstaller stays unsigned.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Version,
  [Parameter(Mandatory = $true)][string]$BuildDir,
  [string]$OutputDir,
  [string]$Iscc,
  [string]$ExportUninstaller,
  [string]$SignedUninstaller
)

$ErrorActionPreference = 'Stop'
$script = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')) 'windows\installer\keqdroid.iss'

if ($ExportUninstaller -and $SignedUninstaller) { throw '-ExportUninstaller and -SignedUninstaller do not go together' }
if (-not $ExportUninstaller -and -not $OutputDir) { throw '-OutputDir is required to build setup.exe' }
if (-not (Test-Path -LiteralPath (Join-Path $BuildDir 'keqdroid.exe'))) { throw "No keqdroid.exe in $BuildDir" }
# ISCC resolves relative paths against the .iss folder, not the current one
$BuildDir = (Resolve-Path -LiteralPath $BuildDir).Path
if ($OutputDir) { $OutputDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDir) }

if (-not $Iscc) {
  $Iscc = @(
    (Join-Path $env:ProgramFiles 'Inno Setup 7\ISCC.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 7\ISCC.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 7\ISCC.exe')
  ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $Iscc -or -not (Test-Path -LiteralPath $Iscc)) {
  throw 'Inno Setup 7 (ISCC.exe) not found. Install Inno Setup 7.1.1 or pass -Iscc.'
}

function Invoke-Iscc([string[]]$Defines) {
  $isccArgs = @('/Q') + ($Defines | ForEach-Object { "/D$_" }) + $script
  # ISCC prints errors to stderr; Windows PowerShell turns them into terminating errors under Stop
  $ErrorActionPreference = 'Continue'
  $output = & $Iscc @isccArgs 2>&1 | ForEach-Object {
    if ($_ -is [Management.Automation.ErrorRecord]) { $_.Exception.Message -replace '^System\.Management\.Automation\.RemoteException$', '' } else { "$_" }
  } | Out-String
  [pscustomobject]@{ Code = $LASTEXITCODE; Output = $output }
}

function New-UnsignedUninstaller([string]$Dir) {
  $scratchOut = Join-Path $Dir 'out'
  New-Item -ItemType Directory -Force -Path $scratchOut | Out-Null
  $r = Invoke-Iscc @("AppVersion=$Version", "BuildDir=$BuildDir", "OutputDir=$scratchOut", "SignedUninstallerDir=$Dir")
  $made = @(Get-ChildItem -LiteralPath $Dir -Filter 'uninst-*.e??' -File)
  if ($r.Code -eq 0 -or $made.Count -ne 1 -or $r.Output -notmatch 'Signed uninstaller mode is enabled') {
    Write-Host $r.Output
    throw "ISCC did not stop for the uninstaller signature as expected (exit $($r.Code), $($made.Count) uninst-* files)"
  }
  # the expected stop leaves exit code 2, and a GitHub Actions step ends with the last one
  $global:LASTEXITCODE = 0
  $made[0]
}

$work = Join-Path ([IO.Path]::GetTempPath()) "keqdroid-installer-$PID"
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
New-Item -ItemType Directory -Force -Path $work | Out-Null
try {
  if ($ExportUninstaller) {
    $unsigned = New-UnsignedUninstaller $work
    Copy-Item -LiteralPath $unsigned.FullName -Destination $ExportUninstaller -Force
    Write-Host "    unsigned uninstaller $($unsigned.Name) -> $ExportUninstaller"
    return
  }

  $defines = @("AppVersion=$Version", "BuildDir=$BuildDir", "OutputDir=$OutputDir")
  if ($SignedUninstaller) {
    if ((Get-AuthenticodeSignature -LiteralPath $SignedUninstaller).Status -eq 'NotSigned') {
      throw "$SignedUninstaller is not signed"
    }
    $unsigned = New-UnsignedUninstaller $work
    Copy-Item -LiteralPath $SignedUninstaller -Destination $unsigned.FullName -Force
    $defines += "SignedUninstallerDir=$work"
  }
  $r = Invoke-Iscc $defines
  if ($r.Code -ne 0) {
    Write-Host $r.Output
    throw "ISCC failed (exit $($r.Code))"
  }
  $setup = Join-Path $OutputDir "keqdroid-windows-x64-$Version-setup.exe"
  if (-not (Test-Path -LiteralPath $setup)) { throw "ISCC did not produce $setup" }
  Write-Host "    $(Split-Path $setup -Leaf) ($([math]::Round((Get-Item -LiteralPath $setup).Length / 1MB, 1)) MB)"
} finally {
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
