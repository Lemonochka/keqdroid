import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/linux_desktop_entry.dart';
import 'package:path/path.dart' as p;

void main() {
  group('contentFor', () {
    const appImage = '/home/u/Apps/keqdroid-0.25.2-x86_64.AppImage';

    test('ties the window to the entry by the app id', () {
      final text = LinuxDesktopEntry.contentFor(appImage, hidden: false);
      expect(text, contains('StartupWMClass=com.keqdroid.keqdroid\n'));
      expect(text, contains('Exec="$appImage" %u\n'));
      expect(text, contains('TryExec=$appImage\n'));
      expect(text, contains(LinuxDesktopEntry.marker));
      expect(text, isNot(contains('NoDisplay')));
    });

    test('stays out of the menu when another entry already launches it', () {
      final text = LinuxDesktopEntry.contentFor(appImage, hidden: true);
      expect(text, contains('NoDisplay=true\n'));
    });

    test('opens keqdroid:// and keqdis:// links, hidden or not', () {
      for (final hidden in [false, true]) {
        final text = LinuxDesktopEntry.contentFor(appImage, hidden: hidden);
        expect(
          text,
          contains(
            'MimeType=x-scheme-handler/keqdroid;x-scheme-handler/keqdis;\n',
          ),
        );
      }
    });

    test('the packages declare the same link schemes', () {
      final script = File('tool/package_linux.sh').readAsStringSync();
      final declared = RegExp(r'^MimeType=(.*)$', multiLine: true)
          .allMatches(script)
          .map((m) => m.group(1))
          .toList();
      // ярлык deb/rpm/AppImage и отдельный в PKGBUILD для AUR
      expect(declared, hasLength(2));
      expect(declared, everyElement(LinuxDesktopEntry.mimeTypes));
      final execs = RegExp(r'^Exec=(.*)$', multiLine: true)
          .allMatches(script)
          .map((m) => m.group(1)!)
          .toList();
      expect(execs, hasLength(2));
      expect(execs, everyElement(endsWith(' %u')));
    });
  });

  group('execArgument', () {
    test('quotes a path with spaces', () {
      expect(
        LinuxDesktopEntry.execArgument('/home/u/My Apps/k.AppImage'),
        '"/home/u/My Apps/k.AppImage"',
      );
    });

    test('escapes reserved characters twice, as the spec requires', () {
      // Кавычка, доллар и обратный апостроф экранируются для кавычек, а
      // получившийся обратный слеш — ещё раз как строковое значение ключа.
      expect(LinuxDesktopEntry.execArgument(r'/a"b$c`d'), r'"/a\\"b\\$c\\`d"');
      expect(LinuxDesktopEntry.execArgument(r'/a\b'), r'"/a\\\\b"');
      expect(LinuxDesktopEntry.execArgument('/100%/k'), '"/100%%/k"');
    });
  });

  test('integratedElsewhere spots an AppImageLauncher or Gear Lever entry', () {
    const appImage = '/home/u/Applications/keqdroid.AppImage';
    expect(
      LinuxDesktopEntry.integratedElsewhere(appImage, [
        '[Desktop Entry]\nExec=/usr/bin/firefox\n',
        '[Desktop Entry]\nExec="$appImage" %U\n',
      ]),
      isTrue,
    );
    expect(
      LinuxDesktopEntry.integratedElsewhere(appImage, [
        '[Desktop Entry]\nExec=/usr/bin/firefox\n',
      ]),
      isFalse,
    );
  });

  group('writeIcons', () {
    late Directory home;
    final fresh = Uint8List.fromList([1, 2, 3]);

    setUp(() => home = Directory.systemTemp.createTempSync('desktop_icons'));
    tearDown(() => home.deleteSync(recursive: true));

    File icon(String name) =>
        File(p.join(home.path, 'icons', 'hicolor', '256x256', 'apps', name));

    test('puts the icon under both names', () {
      LinuxDesktopEntry.writeIcons(home.path, fresh);
      expect(icon('keqdroid.png').readAsBytesSync(), fresh);
      expect(icon('com.keqdroid.keqdroid.png').readAsBytesSync(), fresh);
    });

    // AppImage обновился на месте: ярлык тот же, а иконка в нём уже другая
    test('replaces an icon left by an older version', () {
      icon('keqdroid.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync([9, 9]);
      LinuxDesktopEntry.writeIcons(home.path, fresh);
      expect(icon('keqdroid.png').readAsBytesSync(), fresh);
    });

    test('leaves an icon that is already current alone', () {
      final old = DateTime(2026, 1, 1);
      icon('keqdroid.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(fresh)
        ..setLastModifiedSync(old);
      LinuxDesktopEntry.writeIcons(home.path, fresh);
      expect(icon('keqdroid.png').lastModifiedSync(), old);
    });
  });
}
