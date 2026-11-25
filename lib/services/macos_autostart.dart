import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../core/app_logger.dart';

class MacosAutostart {
  MacosAutostart._();

  static const flag = '--autostart';
  static const label = 'com.keqdroid.keqdroid';
  static const _fileName = '$label.plist';

  @visibleForTesting
  static String? homeOverride;

  @visibleForTesting
  static String Function() executablePath = () => Platform.resolvedExecutable;

  static List<String> _launchArgs = const [];

  static void captureLaunchArgs(List<String> args) {
    _launchArgs = List.unmodifiable(args);
  }

  static bool launchedAtLogin() => _launchArgs.contains(flag);

  static String _home() => homeOverride ?? Platform.environment['HOME'] ?? '';

  static File _plistFile() =>
      File(p.join(_home(), 'Library', 'LaunchAgents', _fileName));

  // Matches MainFlutterWindow.startsInTray() in macos/Runner/MainFlutterWindow.swift.
  static File _inTrayFile() => File(
    p.join(
      _home(),
      'Library',
      'Application Support',
      label,
      'autostart-in-tray',
    ),
  );

  static bool isEnabled() {
    try {
      final file = _plistFile();
      return file.existsSync() && file.readAsStringSync().contains(label);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> setEnabled(bool enabled) async {
    try {
      final file = _plistFile();
      if (!enabled) {
        if (file.existsSync()) await file.delete();
        return true;
      }
      await file.parent.create(recursive: true);
      await file.writeAsString(plistFor(executablePath()));
      return true;
    } catch (e, st) {
      AppLogger.instance.warn(
        'Could not change macOS autostart',
        error: e,
        stackTrace: st,
      );
      return false;
    }
  }

  static Future<void> refresh() async {
    if (!isEnabled()) return;
    try {
      final file = _plistFile();
      final content = plistFor(executablePath());
      if (await file.readAsString() != content) {
        await file.writeAsString(content);
      }
    } catch (e) {
      AppLogger.instance.warn('macOS autostart not synced', error: e);
    }
  }

  static Future<void> setStartInTray(bool enabled) async {
    try {
      final file = _inTrayFile();
      if (file.existsSync() == enabled) return;
      if (!enabled) {
        await file.delete();
        return;
      }
      await file.parent.create(recursive: true);
      await file.writeAsString('');
    } catch (e, st) {
      AppLogger.instance.warn(
        'Could not change macOS start in tray',
        error: e,
        stackTrace: st,
      );
    }
  }

  static bool startedInTray() {
    try {
      return launchedAtLogin() && _inTrayFile().existsSync();
    } catch (_) {
      return false;
    }
  }

  static String _xmlEscape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  @visibleForTesting
  static String plistFor(String target) =>
      '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>${_xmlEscape(target)}</string>
    <string>$flag</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
''';
}
