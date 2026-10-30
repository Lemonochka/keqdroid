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

  test('caelestia gets a Lua start hook, quotes and backslashes escaped', () {
    expect(
      LinuxAutostart.hyprlandLines('/home/u/Загрузки/keqdroid.AppImage',
          lua: true),
      endsWith('\nhl.on("hyprland.start", function() '
          'hl.exec_cmd("\'/home/u/Загрузки/keqdroid.AppImage\' --autostart") end)\n'),
    );
    expect(
      LinuxAutostart.hyprlandLines(r'/a "b"\c', lua: true),
      contains(r'''hl.exec_cmd("'/a \"b\"\\c' --autostart")'''),
    );
  });

  test('plain Hyprland gets exec-once, a # in the path doubled', () {
    expect(
      LinuxAutostart.hyprlandLines("/home/u/#apps/it's", lua: false),
      endsWith("\nexec-once = '/home/u/##apps/it'\\''s' --autostart\n"),
    );
  });

  group('on disk', () {
    late Directory config;
    late int reloads;
    var hyprland = false;
    var desktopRunsIt = false;
    final realSession = LinuxAutostart.hyprlandSession;
    final realDesktop = LinuxAutostart.desktopRunsAutostart;

    File entry() => File(p.join(config.path, 'autostart', 'keqdroid.desktop'));
    File hyprlandDropIn() => File(p.join(config.path, 'systemd', 'user',
        'hyprland-session.target.d', 'keqdroid.conf'));
    // так systemd-xdg-autostart-generator называет службу из ярлыка
    String generatedUnit() =>
        'app-${p.basenameWithoutExtension(entry().path)}@autostart.service';
    File caelestia() => File(p.join(config.path, 'caelestia', 'hypr-user.lua'));
    File hyprConf() => File(p.join(config.path, 'hypr', 'hyprland.conf'));
    void put(File f, String text) => f
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
    void enabledEarlier() =>
        put(entry(), LinuxAutostart.contentFor(Platform.resolvedExecutable));
    String ours({required bool lua}) =>
        LinuxAutostart.hyprlandLines(Platform.resolvedExecutable, lua: lua);

    setUp(() {
      config = Directory.systemTemp.createTempSync('kq_autostart_');
      LinuxAutostart.configHomeOverride = config.path;
      reloads = 0;
      LinuxAutostart.reloadUserUnits = () async => reloads++;
      hyprland = false;
      desktopRunsIt = false;
      LinuxAutostart.hyprlandSession = () => hyprland;
      LinuxAutostart.desktopRunsAutostart = () async => desktopRunsIt;
    });

    tearDown(() {
      LinuxAutostart.configHomeOverride = null;
      LinuxAutostart.hyprlandSession = realSession;
      LinuxAutostart.desktopRunsAutostart = realDesktop;
      config.deleteSync(recursive: true);
    });

    // жалоба 30.10.2026: caelestia на EndeavourOS, вход через sddm, без uwsm и без hyprland-session.target
    test('caelestia without uwsm gets the start line in its user file', () async {
      hyprland = true;
      put(caelestia(), '');

      expect(await LinuxAutostart.setEnabled(true), isTrue);

      expect(caelestia().readAsStringSync(), ours(lua: true));
    });

    test('plain Hyprland gets exec-once at the end of hyprland.conf', () async {
      hyprland = true;
      const own = 'monitor=,preferred,auto,1\n';
      put(hyprConf(), own);

      await LinuxAutostart.setEnabled(true);

      expect(hyprConf().readAsStringSync(), own + ours(lua: false));
    });

    test('a moved AppImage replaces the line instead of adding one', () async {
      hyprland = true;
      enabledEarlier();
      put(caelestia(),
          '-- mine\n${LinuxAutostart.hyprlandLines('/old/keqdroid.AppImage', lua: true)}');

      await LinuxAutostart.refresh();

      expect(caelestia().readAsStringSync(), '-- mine\n${ours(lua: true)}');
    });

    test('turning autostart off leaves the rest of the config byte for byte',
        () async {
      hyprland = true;
      const own = '-- mine\nhl.config({ general = { gaps_in = 4 } })\n';
      put(caelestia(), own);
      await LinuxAutostart.setEnabled(true);

      await LinuxAutostart.setEnabled(false);

      expect(caelestia().readAsStringSync(), own);
    });

    test('a line the user put under our mark by hand survives', () async {
      const own = '-- keqdroid autostart, added and removed by the app\n'
          'hl.exec_cmd("waybar")\n';
      put(caelestia(), own);

      await LinuxAutostart.setEnabled(false);

      expect(caelestia().readAsStringSync(), 'hl.exec_cmd("waybar")\n');
    });

    test('where XDG autostart runs there is no line, and an old one goes',
        () async {
      hyprland = true;
      desktopRunsIt = true;
      const own = '-- mine\n';
      enabledEarlier();
      put(caelestia(), own + ours(lua: true));

      await LinuxAutostart.refresh();
      expect(caelestia().readAsStringSync(), own);

      await LinuxAutostart.setEnabled(true);
      expect(caelestia().readAsStringSync(), own);
    });

    test('outside Hyprland the line stays for the next Hyprland login',
        () async {
      enabledEarlier();
      final text = '-- mine\n${ours(lua: true)}';
      put(caelestia(), text);

      await LinuxAutostart.refresh();

      expect(caelestia().readAsStringSync(), text);
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
