import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import 'windows_desktop_service.dart';

// установленная копия обновляется своим установщиком, иначе версия в «Приложениях» застряла бы на старой
class WindowsSetupUpdater {
  WindowsSetupUpdater._();

  static Future<bool> runSilentSetup({
    required String setupPath,
    Future<void> Function()? beforeRestart,
  }) async {
    if (!Platform.isWindows) {
      throw StateError('WindowsSetupUpdater is Windows-only');
    }
    final scriptPath = p.join(
      p.dirname(setupPath),
      'keqdroid_setup_${DateTime.now().millisecondsSinceEpoch}.ps1',
    );
    // BOM обязателен: Windows PowerShell 5.1 иначе читает .ps1 в ANSI
    await File(scriptPath).writeAsString('\u{FEFF}$script', flush: true);

    // вне нашего дерева процессов, чтобы пережил exit. права у скрипта наши, с ними же он и вернёт приложение
    await Process.start(
      'cmd.exe',
      [
        '/c',
        'start',
        '""',
        '/min',
        'powershell.exe',
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-File',
        scriptPath,
        '-Setup',
        setupPath,
        '-ExePath',
        Platform.resolvedExecutable,
        '-AppPid',
        '$pid',
      ],
      mode: ProcessStartMode.detached,
    );

    await beforeRestart?.call();
    await WindowsDesktopService.clearSessionCoreProcesses();
    await WindowsDesktopService.exitApp();
    exit(0);
  }

  // установщик ждёт, пока приложение выйдет: в тихом режиме AppMutex отвечает за человека «Отмена».
  // отказ в UAC или сбой установки тоже возвращают приложение, просто прежней версии
  @visibleForTesting
  static const script = r'''
param(
  [Parameter(Mandatory = $true)][string]$Setup,
  [Parameter(Mandatory = $true)][string]$ExePath,
  [Parameter(Mandatory = $true)][int]$AppPid
)

$ErrorActionPreference = 'Continue'
$log = Join-Path $env:TEMP 'keqdroid_update.log'
function Log($m) {
  try { "$(Get-Date -Format o)  $m" | Out-File -FilePath $log -Append -Encoding utf8 } catch {}
}
Log "=== setup update start: setup=$Setup exe=$ExePath pid=$AppPid"

for ($i = 0; $i -lt 120; $i++) {
  if (-not (Get-Process -Id $AppPid -ErrorAction SilentlyContinue)) { break }
  Start-Sleep -Seconds 1
}
Start-Sleep -Seconds 1

$setupLog = Join-Path $env:TEMP 'keqdroid_setup.log'
$code = -1
try {
  $p = Start-Process -FilePath $Setup -PassThru -Wait -ArgumentList @(
    '/SP-', '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/LOG=`"$setupLog`"")
  $code = $p.ExitCode
} catch {
  Log "setup did not start: $_"
}
Log "setup exit=$code"

try {
  Start-Process -FilePath $ExePath -WorkingDirectory (Split-Path -Parent $ExePath)
  Log "relaunched $ExePath"
} catch {
  Log "relaunch failed: $_"
}

Remove-Item -LiteralPath $Setup -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
''';
}
