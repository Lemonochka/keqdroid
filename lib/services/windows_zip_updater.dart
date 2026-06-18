import 'dart:io';

import 'package:path/path.dart' as p;

import 'windows_desktop_service.dart';

/// Portable Windows update: extract release zip and replace files after exit.
class WindowsZipUpdater {
  WindowsZipUpdater._();

  static const exeName = 'keqdroid.exe';

  /// Finds the folder inside an extracted archive that contains [exeName].
  static String? findPayloadRoot(Directory extractDir) {
    final atRoot = File(p.join(extractDir.path, exeName));
    if (atRoot.existsSync()) return extractDir.path;

    final subdirs = extractDir
        .listSync()
        .whereType<Directory>()
        .where((d) => !p.basename(d.path).startsWith('.'))
        .toList();

    if (subdirs.length == 1) {
      final nested = File(p.join(subdirs.single.path, exeName));
      if (nested.existsSync()) return subdirs.single.path;
    }

    for (final dir in subdirs) {
      if (File(p.join(dir.path, exeName)).existsSync()) {
        return dir.path;
      }
    }

    return null;
  }

  /// Downloads are applied in-place; returns `true` when the app is exiting.
  static Future<bool> applyPortableZipUpdate({
    required String zipPath,
    Future<void> Function()? beforeRestart,
  }) async {
    if (!Platform.isWindows) {
      throw StateError('WindowsZipUpdater is Windows-only');
    }

    final zipFile = File(zipPath);
    if (!await zipFile.exists()) {
      throw StateError('Update archive not found');
    }

    final appDir = p.dirname(Platform.resolvedExecutable);
    final exePath = Platform.resolvedExecutable;
    final stagingRoot = Directory(
      p.join(p.dirname(zipPath), 'staging_${DateTime.now().millisecondsSinceEpoch}'),
    );
    final extractDir = Directory(p.join(stagingRoot.path, 'extracted'));

    await stagingRoot.create(recursive: true);
    await extractDir.create(recursive: true);

    try {
      await _extractZip(zipPath, extractDir.path);

      final payloadRoot = findPayloadRoot(extractDir);
      if (payloadRoot == null) {
        throw StateError('Update archive does not contain $exeName');
      }

      final scriptPath = p.join(stagingRoot.path, 'apply_update.ps1');
      await File(scriptPath).writeAsString(
        _updaterScript(),
        flush: true,
      );

      await _launchDetachedUpdater([
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-File',
        scriptPath,
        '-SourceDir',
        payloadRoot,
        '-TargetDir',
        appDir,
        '-ExePath',
        exePath,
        '-AppPid',
        '$pid',
        '-CleanupDir',
        stagingRoot.path,
      ]);

      await beforeRestart?.call();
      await WindowsDesktopService.clearSessionCoreProcesses();
      await WindowsDesktopService.exitApp();
      exit(0);
    } catch (e) {
      if (await stagingRoot.exists()) {
        await stagingRoot.delete(recursive: true);
      }
      rethrow;
    }
  }

  static Future<void> _extractZip(String zipPath, String destination) async {
    final result = await Process.run(
      'powershell.exe',
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        "Expand-Archive -LiteralPath '${_escapePsSingleQuoted(zipPath)}' "
        "-DestinationPath '${_escapePsSingleQuoted(destination)}' -Force",
      ],
    );

    if (result.exitCode != 0) {
      final message = (result.stderr as String).trim();
      throw StateError(
        message.isEmpty ? 'Failed to extract update archive' : message,
      );
    }
  }

  static String _escapePsSingleQuoted(String value) =>
      value.replaceAll("'", "''");

  /// Spawns the updater outside this process tree (`cmd /c start`) so it keeps
  /// running after the app calls [exit].
  static Future<void> _launchDetachedUpdater(List<String> psArgs) {
    return Process.start(
      'cmd.exe',
      ['/c', 'start', '""', '/min', 'powershell.exe', ...psArgs],
      mode: ProcessStartMode.detached,
    );
  }

  static String _updaterScript() => r'''
param(
  [Parameter(Mandatory = $true)][string]$SourceDir,
  [Parameter(Mandatory = $true)][string]$TargetDir,
  [Parameter(Mandatory = $true)][string]$ExePath,
  [Parameter(Mandatory = $true)][int]$AppPid,
  [Parameter(Mandatory = $true)][string]$CleanupDir
)

# Keep going on non-terminating errors so robocopy failures don't abort the
# relaunch, and log everything to a file for diagnosing failed updates.
$ErrorActionPreference = 'Continue'
$log = Join-Path $env:TEMP 'keqdroid_update.log'
function Log($m) {
  try { "$(Get-Date -Format o)  $m" | Out-File -FilePath $log -Append -Encoding utf8 } catch {}
}
Log "=== update start: source=$SourceDir target=$TargetDir exe=$ExePath pid=$AppPid"

# 1) wait for the app to exit (max 120s), then a grace period so the OS
#    releases the .exe / .dll file handles before we overwrite them.
for ($i = 0; $i -lt 120; $i++) {
  if (-not (Get-Process -Id $AppPid -ErrorAction SilentlyContinue)) { break }
  Start-Sleep -Seconds 1
}
Start-Sleep -Seconds 3

# 2) stop leftover processes that may lock binaries in the install dir.
foreach ($name in @('keqdroid', 'xray', 'sing-box', 'wireproxy')) {
  Get-Process -Name $name -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 1

# 3) if the target isn't writable (e.g. installed under Program Files),
#    relaunch this script elevated once to perform the copy.
$writable = $false
try {
  $probe = Join-Path $TargetDir ('.upd_' + [System.Guid]::NewGuid().ToString('N'))
  [System.IO.File]::WriteAllText($probe, 'x')
  Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
  $writable = $true
} catch { $writable = $false }

$isAdmin = ([Security.Principal.WindowsPrincipal] `
  [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $writable -and -not $isAdmin) {
  Log "target not writable; relaunching elevated"
  try {
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @(
      '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
      '-File', $PSCommandPath,
      '-SourceDir', $SourceDir, '-TargetDir', $TargetDir, '-ExePath', $ExePath,
      '-AppPid', $AppPid, '-CleanupDir', $CleanupDir)
    exit 0
  } catch {
    Log "elevation failed: $_"
  }
}

# 4) copy the new files in, retrying transient sharing violations.
#    /IS /IT /IM force overwrite even when timestamps differ (zip entries are
#    often older than installed files, which made robocopy skip app.so).
$copied = $false
for ($attempt = 1; $attempt -le 8; $attempt++) {
  $null = & robocopy $SourceDir $TargetDir /E /IS /IT /IM /R:5 /W:3 /NFL /NDL /NJH /NJS /NP 2>&1
  $code = $LASTEXITCODE
  Log "robocopy attempt $attempt exit=$code"

  $critical = @(
    (Join-Path $SourceDir 'keqdroid.exe'),
    (Join-Path $SourceDir 'data\app.so')
  )
  $allMatch = $true
  foreach ($srcFile in $critical) {
    if (-not (Test-Path -LiteralPath $srcFile)) { continue }
    $rel = $srcFile.Substring($SourceDir.Length).TrimStart('\')
    $dstFile = Join-Path $TargetDir $rel
    if (-not (Test-Path -LiteralPath $dstFile)) {
      Log "missing after robocopy: $rel"
      $allMatch = $false
      continue
    }
    $srcHash = (Get-FileHash -LiteralPath $srcFile -Algorithm SHA256).Hash
    $dstHash = (Get-FileHash -LiteralPath $dstFile -Algorithm SHA256).Hash
    if ($srcHash -eq $dstHash) { continue }

    Log "hash mismatch $rel — retrying direct copy"
    $allMatch = $false
    try {
      $dstParent = Split-Path -Parent $dstFile
      if (-not (Test-Path -LiteralPath $dstParent)) {
        New-Item -ItemType Directory -Path $dstParent -Force | Out-Null
      }
      Copy-Item -LiteralPath $srcFile -Destination $dstFile -Force
      $dstHash = (Get-FileHash -LiteralPath $dstFile -Algorithm SHA256).Hash
      if ($srcHash -eq $dstHash) {
        Log "direct copy ok: $rel"
      } else {
        Log "direct copy still mismatched: $rel"
      }
    } catch {
      Log "direct copy failed $rel : $_"
    }
  }

  # Re-check after direct-copy attempts.
  $allMatch = $true
  foreach ($srcFile in $critical) {
    if (-not (Test-Path -LiteralPath $srcFile)) { continue }
    $rel = $srcFile.Substring($SourceDir.Length).TrimStart('\')
    $dstFile = Join-Path $TargetDir $rel
    if (-not (Test-Path -LiteralPath $dstFile)) { $allMatch = $false; continue }
    $srcHash = (Get-FileHash -LiteralPath $srcFile -Algorithm SHA256).Hash
    $dstHash = (Get-FileHash -LiteralPath $dstFile -Algorithm SHA256).Hash
    if ($srcHash -ne $dstHash) { $allMatch = $false }
  }

  if ($code -lt 8 -and $allMatch) { $copied = $true; break }
  Start-Sleep -Seconds 2
}
if (-not $copied) { Log "update copy FAILED after retries; relaunching previous version" }

# 5) always relaunch so the app reopens, with the app dir as working directory
#    so it can load its DLLs regardless of where this script runs from.
try {
  Start-Process -FilePath $ExePath -WorkingDirectory $TargetDir
  Log "relaunched $ExePath"
} catch {
  Log "relaunch failed: $_"
}

Start-Sleep -Seconds 2
Remove-Item -LiteralPath $CleanupDir -Recurse -Force -ErrorAction SilentlyContinue
''';
}