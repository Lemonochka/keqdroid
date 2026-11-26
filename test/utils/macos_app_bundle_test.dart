import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/macos_app_bundle.dart';
import 'package:path/path.dart' as p;

void main() {
  group('macOS app bundle process path', () {
    test('uses CFBundleExecutable instead of the package or display name', () {
      expect(
        MacosAppBundle.executablePath(
          '/Applications/Visible Name.app',
          'actual-binary',
        ),
        '/Applications/Visible Name.app/Contents/MacOS/actual-binary',
      );
    });

    test('normalizes a trailing slash and preserves spaces', () {
      expect(
        MacosAppBundle.executablePath(
          '/Applications/My App.app/',
          'My App Helper',
        ),
        '/Applications/My App.app/Contents/MacOS/My App Helper',
      );
    });

    test('rejects missing names and path traversal', () {
      const app = '/Applications/Foo.app';
      expect(MacosAppBundle.executablePath(app, ' '), isNull);
      expect(MacosAppBundle.executablePath(app, '../Foo'), isNull);
      expect(MacosAppBundle.executablePath(app, 'Contents/MacOS/Foo'), isNull);
      expect(MacosAppBundle.executablePath(app, '..'), isNull);
    });

    test('parses CFBundleExecutable directly from XML Info.plist', () async {
      const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>Visible</string>
  <key>CFBundleExecutable</key>
  <string>Foo &amp; Bar</string>
</dict>
</plist>''';
      expect(MacosAppBundle.parseXmlExecutable(xml), 'Foo & Bar');

      final tmp = Directory.systemTemp.createTempSync('keq_plist_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final contents = Directory(p.join(tmp.path, 'Test.app', 'Contents'))
        ..createSync(recursive: true);
      File(p.join(contents.path, 'Info.plist')).writeAsStringSync(xml);

      expect(
        await MacosAppBundle.executableName(p.join(tmp.path, 'Test.app')),
        'Foo & Bar',
      );
    });
  });
}
