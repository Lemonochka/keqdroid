import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// keqdis внутри приложения держит настройки и ссылки, а человеку на глаза попадать не должно
void main() {
  const main = 'android/app/src/main';
  const kotlin = '$main/kotlin/com/keqdroid/keqdroid';
  final oldName = RegExp('keqdis', caseSensitive: false);

  String read(String path) => File(path).readAsStringSync();

  test('Android labels, tile and VPN session use the new name', () {
    final labels = RegExp(r'android:label="([^"]+)"')
        .allMatches(read('$main/AndroidManifest.xml'))
        .map((m) => m[1])
        .toSet();
    expect(labels, {'keqdroid'});

    expect(RegExp(r'tileObj\.label = "([^"]+)"')
        .firstMatch(read('$kotlin/VpnQuickTileService.kt'))?[1], 'keqdroid');
    expect(RegExp(r'\.setSession\("([^"]+)"\)')
        .firstMatch(read('$kotlin/KeqdisVpnService.kt'))?[1], 'keqdroid');
  });

  test('native strings do not show the old name', () {
    for (final suffix in ['', '-ru', '-de', '-zh', '-fa']) {
      final path = '$main/res/values$suffix/strings.xml';
      expect(oldName.hasMatch(read(path)), isFalse, reason: path);
    }
  });

  test('every language titles the app with the new name', () {
    for (final lang in ['en', 'ru', 'de', 'zh', 'fa']) {
      expect(read('lib/l10n/app_$lang.arb'),
          contains('"appTitle": "keqdroid"'), reason: lang);
    }
  });

  test('saved files carry the new name', () {
    expect(read('lib/screens/settings/backup_restore.dart'),
        contains(r"'keqdroid-backup-$stamp.json'"));
    expect(read('lib/screens/subscriptions_tab.dart'),
        contains(r"'keqdroid_sub_${safe"));
  });

  test('old backups still open', () {
    final service = read('lib/services/settings_backup_service.dart');
    expect(service, contains("'format': 'keqdis_backup'"));
    expect(service, contains("format != 'keqdis_backup'"));
    expect(read('lib/screens/settings/backup_restore.dart'),
        contains("allowedExtensions: const ['json', 'keqdis']"));
  });
}
