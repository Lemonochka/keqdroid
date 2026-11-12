import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// MainActivity открыта наружу: extra с командой мимо закрытого алиаса дало бы любому приложению отключить VPN
void main() {
  const main = 'android/app/src/main';
  const kotlin = '$main/kotlin/com/keqdroid/keqdroid';
  const alias = 'com.keqdroid.keqdroid.LaunchAction';

  test('the alias is closed to other apps and leads to MainActivity', () {
    final manifest = File('$main/AndroidManifest.xml').readAsStringSync();
    final tag = RegExp(r'<activity-alias\b[^>]*android:name="\.LaunchAction"[^>]*>')
        .firstMatch(manifest)?[0];
    expect(tag, isNotNull);
    expect(tag, contains('android:exported="false"'));
    expect(tag, contains('android:targetActivity=".MainActivity"'));
  });

  test('launcher shortcuts target the alias', () {
    final xml = File('$main/res/xml/shortcuts.xml').readAsStringSync();
    final targets = RegExp(r'android:targetClass="([^"]+)"')
        .allMatches(xml)
        .map((m) => m[1])
        .toList();
    expect(targets, [alias, alias]);
  });

  test('a command is read in one place, after checking the alias', () {
    final activity = File('$kotlin/MainActivity.kt').readAsStringSync();
    expect('getStringExtra(EXTRA_LAUNCH_ACTION)'.allMatches(activity).length, 1);

    final trusted = RegExp(r'fun trustedLaunchAction\(\)[\s\S]*?getStringExtra')
        .firstMatch(activity)?[0];
    expect(trusted, contains('launchActionFrom(intent?.component?.className)'));
    // само поведение проверяет android/app/src/test/.../DeviceAndAppRulesTest.kt
    final check = RegExp(r'fun launchActionFrom\([\s\S]*?LAUNCH_ACTIONS')
        .firstMatch(activity)?[0];
    expect(check, contains('className == LAUNCH_ALIAS) action()'));
    expect(activity, contains('LAUNCH_ALIAS = "$alias"'));
  });

  test('every native sender goes through the alias', () {
    final senders = [
      for (final f in Directory(kotlin).listSync())
        if (f is File && f.path.endsWith('.kt'))
          if (RegExp(r'putExtra\(\s*("action"|(MainActivity\.)?EXTRA_LAUNCH_ACTION)')
              .hasMatch(f.readAsStringSync()))
            f.uri.pathSegments.last,
    ];
    expect(senders, ['MainActivity.kt']);
  });
}
