import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/linux_autostart.dart';
import 'package:path/path.dart' as p;

void main() {
  test('the autostart entry launches the app with the login flag', () {
    final text = LinuxAutostart.contentFor('/home/u/Apps/keqdroid.AppImage');
    expect(
      text,
      contains('Exec="/home/u/Apps/keqdroid.AppImage" ${LinuxAutostart.flag}\n'),
    );
    expect(text, contains('X-GNOME-Autostart-enabled=true\n'));
    expect(text, startsWith('[Desktop Entry]\n'));
  });

  test('a path with spaces stays one argument', () {
    expect(
      LinuxAutostart.contentFor('/home/u/My Apps/keqdroid'),
      contains('Exec="/home/u/My Apps/keqdroid" --autostart'),
    );
  });

  group('on disk', () {
    late Directory config;
    late int reloads;

    File entry() => File(p.join(config.path, 'autostart', 'keqdroid.desktop'));
    File hyprlandDropIn() => File(p.join(config.path, 'systemd', 'user',
        'hyprland-session.target.d', 'keqdroid.conf'));
    // так systemd-xdg-autostart-generator называет службу из ярлыка
    String generatedUnit() =>
        'app-${p.basenameWithoutExtension(entry().path)}@autostart.service';

    setUp(() {
      config = Directory.systemTemp.createTempSync('kq_autostart_');
      LinuxAutostart.configHomeOverride = config.path;
      reloads = 0;
      LinuxAutostart.reloadUserUnits = () async => reloads++;
    });

    tearDown(() {
      LinuxAutostart.configHomeOverride = null;
      config.deleteSync(recursive: true);
    });

    test('Hyprland without uwsm also starts the app at login', () async {
      expect(await LinuxAutostart.setEnabled(true), isTrue);

      expect(LinuxAutostart.isEnabled(), isTrue);
      expect(
        hyprlandDropIn().readAsStringSync(),
        contains('Wants=${generatedUnit()}\n'),
      );
      expect(reloads, 1);
    });

    test('turning it off removes both files', () async {
      await LinuxAutostart.setEnabled(true);

      expect(await LinuxAutostart.setEnabled(false), isTrue);

      expect(entry().existsSync(), isFalse);
      expect(hyprlandDropIn().existsSync(), isFalse);
      expect(reloads, 2);
    });

    test('autostart turned on in an older version reaches Hyprland on the '
        'next start', () async {
      entry()
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          LinuxAutostart.contentFor(Platform.resolvedExecutable),
        );

      await LinuxAutostart.refresh();
      expect(hyprlandDropIn().existsSync(), isTrue);
      expect(reloads, 1);

      await LinuxAutostart.refresh();
      expect(reloads, 1);
    });

    test('a leftover Hyprland file goes once autostart is off', () async {
      hyprlandDropIn()
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('[Unit]\nWants=${generatedUnit()}\n');

      await LinuxAutostart.refresh();

      expect(hyprlandDropIn().existsSync(), isFalse);
    });

    test('an entry the user made by hand is not taken over', () async {
      const own = '[Desktop Entry]\nExec=keqdroid\n';
      entry()
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(own);

      expect(await LinuxAutostart.setEnabled(true), isFalse);
      await LinuxAutostart.refresh();

      expect(entry().readAsStringSync(), own);
      expect(hyprlandDropIn().existsSync(), isFalse);
    });
  });
}
