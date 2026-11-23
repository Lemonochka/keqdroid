import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/macos_autostart.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  final realExecutable = MacosAutostart.executablePath;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('keq_macos_autostart_');
    MacosAutostart.homeOverride = tmp.path;
    MacosAutostart.executablePath = () =>
        '/Applications/keqdroid.app/Contents/MacOS/keqdroid';
    MacosAutostart.captureLaunchArgs(const []);
  });

  tearDown(() {
    MacosAutostart.homeOverride = null;
    MacosAutostart.executablePath = realExecutable;
    MacosAutostart.captureLaunchArgs(const []);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('generates valid LaunchAgent plist with XML-escaped executable path', () {
    final plist = MacosAutostart.plistFor('/Applications/A & B/keqdroid');
    expect(plist, contains('<string>${MacosAutostart.label}</string>'));
    expect(plist, contains('<string>/Applications/A &amp; B/keqdroid</string>'));
    expect(plist, contains('<string>${MacosAutostart.flag}</string>'));
    expect(plist, contains('<key>RunAtLoad</key>'));
  });

  test('enables, refreshes and disables LaunchAgent on disk', () async {
    expect(MacosAutostart.isEnabled(), isFalse);
    expect(await MacosAutostart.setEnabled(true), isTrue);
    expect(MacosAutostart.isEnabled(), isTrue);

    final plistFile = File(
      p.join(tmp.path, 'Library', 'LaunchAgents', '${MacosAutostart.label}.plist'),
    );
    expect(plistFile.existsSync(), isTrue);

    MacosAutostart.executablePath = () => '/Users/u/Apps/keqdroid';
    await MacosAutostart.refresh();
    expect(plistFile.readAsStringSync(), contains('/Users/u/Apps/keqdroid'));

    expect(await MacosAutostart.setEnabled(false), isTrue);
    expect(MacosAutostart.isEnabled(), isFalse);
    expect(plistFile.existsSync(), isFalse);
  });

  test('tracks autostart launch flag and start-in-tray marker', () async {
    expect(MacosAutostart.launchedAtLogin(), isFalse);
    expect(MacosAutostart.startedInTray(), isFalse);

    MacosAutostart.captureLaunchArgs(['--autostart']);
    expect(MacosAutostart.launchedAtLogin(), isTrue);
    expect(MacosAutostart.startedInTray(), isFalse);

    await MacosAutostart.setStartInTray(true);
    expect(MacosAutostart.startedInTray(), isTrue);

    await MacosAutostart.setStartInTray(false);
    expect(MacosAutostart.startedInTray(), isFalse);
  });
}
