import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

// установленную копию выдаёт след Inno Setup: деинсталлятор рядом с exe и запись в Uninstall с этой же папкой.
// в zip их нет, и портабельная копия обновляется zip-ом всегда
class WindowsInstall {
  WindowsInstall._();

  static const setupSuffix = '-setup.exe';

  // AppId из windows/installer/keqdroid.iss
  static const _uninstallKey = r'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion'
      r'\Uninstall\{2F4ADD17-AA28-4805-B040-B3EE05138A9C}_is1';

  static Future<bool> isInstalledCopy() async {
    if (!Platform.isWindows) return false;
    final dir = p.dirname(Platform.resolvedExecutable);
    if (!File(p.join(dir, 'unins000.exe')).existsSync()) return false;
    return isSameInstallDir(await _registeredLocation(), dir);
  }

  // reg.exe печатает в кодовой странице OEM, и папка не латиницей не совпала бы
  static Future<String?> _registeredLocation() async {
    try {
      final result = await Process.run(
        'powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          '[Console]::OutputEncoding = [Text.Encoding]::UTF8; '
              "(Get-ItemProperty -LiteralPath '$_uninstallKey' "
              '-ErrorAction Stop).InstallLocation',
        ],
        stdoutEncoding: utf8,
      );
      if (result.exitCode != 0) return null;
      final out = (result.stdout as String).trim();
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }

  // Inno пишет InstallLocation с косой чертой в конце
  @visibleForTesting
  static bool isSameInstallDir(String? registered, String exeDir) {
    if (registered == null || registered.trim().isEmpty) return false;
    String norm(String path) => p.windows.normalize(path.trim()).toLowerCase();
    return norm(registered) == norm(exeDir);
  }
}
