import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/macos_app_bundle.dart';

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
  });
}
