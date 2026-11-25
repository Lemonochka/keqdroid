import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

abstract final class MacosAppBundle {
  // File picker returns the .app package, while both cores see its executable.
  static Future<String> resolveProcessPath(String raw) async {
    if (!Platform.isMacOS) return raw;
    final trimmed = raw.trim().replaceAll('"', '');
    if (trimmed.isEmpty) return raw;
    final path = p.posix.normalize(trimmed);
    if (!path.toLowerCase().endsWith('.app')) return raw;

    final name = await executableName(path);
    if (name == null) return raw;
    final executable = executablePath(path, name);
    if (executable == null || !File(executable).existsSync()) return raw;
    return executable;
  }

  @visibleForTesting
  static String? executablePath(String appBundlePath, String executableName) {
    final name = executableName.trim();
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        p.posix.basename(name) != name) {
      return null;
    }
    return p.posix.normalize(
      p.posix.join(appBundlePath, 'Contents', 'MacOS', name),
    );
  }

  static Future<String?> executableName(String appBundlePath) async {
    final plist = p.join(appBundlePath, 'Contents', 'Info.plist');
    if (!File(plist).existsSync()) return null;
    try {
      final r = await Process.run('/usr/bin/defaults', [
        'read',
        plist,
        'CFBundleExecutable',
      ]);
      if (r.exitCode == 0) {
        final name = '${r.stdout}'.trim();
        if (name.isNotEmpty) return name;
      }
    } catch (_) {}
    return null;
  }
}
