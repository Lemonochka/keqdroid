import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

abstract final class MacosAppBundle {
  static final _xmlExecutablePattern = RegExp(
    r'<key>\s*CFBundleExecutable\s*</key>\s*<string>([^<]*)</string>',
  );

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

  @visibleForTesting
  static String? parseXmlExecutable(String xml) {
    final m = _xmlExecutablePattern.firstMatch(xml);
    if (m == null) return null;
    final decoded = m
        .group(1)!
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .trim();
    return decoded.isEmpty ? null : decoded;
  }

  static Future<String?> executableName(String appBundlePath) async {
    final plistFile = File(p.join(appBundlePath, 'Contents', 'Info.plist'));
    if (!plistFile.existsSync()) return null;
    try {
      final bytes = await plistFile.readAsBytes();
      final isBinary =
          bytes.length >= 6 &&
          bytes[0] == 0x62 && // 'b'
          bytes[1] == 0x70 && // 'p'
          bytes[2] == 0x6c && // 'l'
          bytes[3] == 0x69 && // 'i'
          bytes[4] == 0x73 && // 's'
          bytes[5] == 0x74; // 't'
      if (!isBinary) {
        final parsed = parseXmlExecutable(
          utf8.decode(bytes, allowMalformed: true),
        );
        if (parsed != null) return parsed;
      }
    } catch (_) {}
    try {
      final r = await Process.run('/usr/bin/defaults', [
        'read',
        plistFile.path,
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
