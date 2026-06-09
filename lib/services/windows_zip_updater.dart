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

      await Process.start(
        'powershell.exe',
        [
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
          '-ProcessId',
          '$pid',
          '-CleanupDir',
          stagingRoot.path,
        ],
        mode: ProcessStartMode.detached,
      );

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

  static String _updaterScript() => r'''
param(
  [Parameter(Mandatory = $true)][string]$SourceDir,
  [Parameter(Mandatory = $true)][string]$TargetDir,
  [Parameter(Mandatory = $true)][string]$ExePath,
  [Parameter(Mandatory = $true)][int]$ProcessId,
  [Parameter(Mandatory = $true)][string]$CleanupDir
)

$ErrorActionPreference = 'SilentlyContinue'

for ($i = 0; $i -lt 120; $i++) {
  if (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) {
    break
  }
  Start-Sleep -Seconds 1
}

foreach ($name in @('xray', 'sing-box')) {
  Get-Process -Name $name -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
}

& robocopy $SourceDir $TargetDir /E /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) {
  exit 1
}

Start-Process -FilePath $ExePath
Start-Sleep -Seconds 2
Remove-Item -LiteralPath $CleanupDir -Recurse -Force -ErrorAction SilentlyContinue
''';
}
