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
      LinuxAutostart.startLines('hyprland', 'hypr-user.lua',
          '/home/u/Загрузки/keqdroid.AppImage'),
      endsWith('\nhl.on("hyprland.start", function() '
          'hl.exec_cmd("\'/home/u/Загрузки/keqdroid.AppImage\' --autostart") end)\n'),
    );
    expect(
      LinuxAutostart.startLines('hyprland', 'hypr-user.lua', r'/a "b"\c'),
      contains(r'''hl.exec_cmd("'/a \"b\"\\c' --autostart")'''),
    );
  });

  test('plain Hyprland gets exec-once, the path kept through hyprlang', () {
    expect(
      LinuxAutostart.startLines(
          'hyprland', 'hyprland.conf', r"/home/u/#apps/it's $mod\x"),
      endsWith('''\nexec-once = '/home/u/##apps/it'"'"'s \$''mod\\\\x' --autostart\n'''),
    );
  });

  test('sway starts it with exec, river from init in the background', () {
    expect(
      LinuxAutostart.startLines('sway', 'config', '/home/u/keqdroid'),
      endsWith("\nexec '/home/u/keqdroid' --autostart\n"),
    );
    expect(
      LinuxAutostart.startLines('river', 'init', '/home/u/keqdroid'),
      endsWith("\n'/home/u/keqdroid' --autostart &\n"),
    );
  });

  // sway до sh -c сам снимает обратную косую и подставляет $имя: '\'' превращался в незакрытую кавычку
  test('sway gets an apostrophe, a backslash and a dollar in the path intact', () {
    expect(
      LinuxAutostart.startLines('sway', 'config', r"/home/u/it's $mod\x"),
      endsWith('''\nexec '/home/u/it'"'"'s \$\$mod\\\\x' --autostart\n'''),
    );
    expect(
      LinuxAutostart.startLines('river', 'init', "/home/u/it's"),
      endsWith('''\n'/home/u/it'"'"'s' --autostart &\n'''),
    );
  });

  test('niri gets spawn-at-startup with the path as its own KDL string', () {
    expect(
      LinuxAutostart.startLines('niri', 'config.kdl', r'/home/u/"x"\keqdroid'),
      endsWith('\nspawn-at-startup "/home/u/\\"x\\"\\\\keqdroid" "--autostart"\n'),
    );
  });

  group('on disk', () {
    late Directory config;
    late int reloads;
    String? wm;
    var desktopRunsIt = false;
    final realCompositor = LinuxAutostart.compositor;
    final realDesktop = LinuxAutostart.desktopRunsAutostart;

    File entry() => File(p.join(config.path, 'autostart', 'keqdroid.desktop'));
    File hyprlandDropIn() => File(p.join(config.path, 'systemd', 'user',
        'hyprland-session.target.d', 'keqdroid.conf'));
    // так systemd-xdg-autostart-generator называет службу из ярлыка
    String generatedUnit() =>
        'app-${p.basenameWithoutExtension(entry().path)}@autostart.service';
    File caelestia() => File(p.join(config.path, 'caelestia', 'hypr-user.lua'));
    File hyprConf() => File(p.join(config.path, 'hypr', 'hyprland.conf'));
    File swayConf() => File(p.join(config.path, 'sway', 'config'));
    File swayHomeConf() => File(p.join(config.path, 'home', '.sway', 'config'));
    File riverInit() => File(p.join(config.path, 'river', 'init'));
    File niriConf() => File(p.join(config.path, 'niri', 'config.kdl'));
    void put(File f, String text) => f
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
    void enabledEarlier() =>
        put(entry(), LinuxAutostart.contentFor(Platform.resolvedExecutable));
    // ожидание считается тем же кодом, что пишет строку: пустое прошло бы молча
    String ours(String wm, File file) {
      final lines = LinuxAutostart.startLines(
          wm, file.path, Platform.resolvedExecutable);
      expect(lines, contains(LinuxAutostart.flag));
      return lines;
    }

    setUp(() {
      config = Directory.systemTemp.createTempSync('kq_autostart_');
      LinuxAutostart.configHomeOverride = config.path;
      reloads = 0;
      LinuxAutostart.reloadUserUnits = () async => reloads++;
      wm = null;
      desktopRunsIt = false;
      LinuxAutostart.compositor = () => wm;
      LinuxAutostart.homeOverride = p.join(config.path, 'home');
      LinuxAutostart.desktopRunsAutostart = () async => desktopRunsIt;
    });

    tearDown(() {
      LinuxAutostart.configHomeOverride = null;
      LinuxAutostart.compositor = realCompositor;
      LinuxAutostart.homeOverride = null;
      LinuxAutostart.desktopRunsAutostart = realDesktop;
      config.deleteSync(recursive: true);
    });

    // жалоба 30.10.2026: caelestia на EndeavourOS, вход через sddm, без uwsm и без hyprland-session.target
    test('caelestia without uwsm gets the start line in its user file', () async {
      wm = 'hyprland';
      put(caelestia(), '');

      expect(await LinuxAutostart.setEnabled(true), isTrue);

      expect(caelestia().readAsStringSync(), ours('hyprland', caelestia()));
    });

    test('plain Hyprland gets exec-once at the end of hyprland.conf', () async {
      wm = 'hyprland';
      const own = 'monitor=,preferred,auto,1\n';
      put(hyprConf(), own);

      await LinuxAutostart.setEnabled(true);

      expect(hyprConf().readAsStringSync(), own + ours('hyprland', hyprConf()));
    });

    test('a moved AppImage replaces the line instead of adding one', () async {
      wm = 'hyprland';
      enabledEarlier();
      put(caelestia(),
          '-- mine\n${LinuxAutostart.startLines('hyprland', caelestia().path, '/old/keqdroid.AppImage')}');

      await LinuxAutostart.refresh();

      expect(caelestia().readAsStringSync(), '-- mine\n${ours('hyprland', caelestia())}');
    });

    test('turning autostart off leaves the rest of the config byte for byte',
        () async {
      wm = 'hyprland';
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
      wm = 'hyprland';
      desktopRunsIt = true;
      const own = '-- mine\n';
      enabledEarlier();
      put(caelestia(), own + ours('hyprland', caelestia()));

      await LinuxAutostart.refresh();
      expect(caelestia().readAsStringSync(), own);

      await LinuxAutostart.setEnabled(true);
      expect(caelestia().readAsStringSync(), own);
    });

    test('outside Hyprland the line stays for the next Hyprland login',
        () async {
      enabledEarlier();
      final text = '-- mine\n${ours('hyprland', caelestia())}';
      put(caelestia(), text);

      await LinuxAutostart.refresh();

      expect(caelestia().readAsStringSync(), text);
    });

    test('sway without its own session starts it with exec from its config',
        () async {
      wm = 'sway';
      const own = 'set \$mod Mod4\n';
      put(swayConf(), own);

      await LinuxAutostart.setEnabled(true);

      expect(swayConf().readAsStringSync(), own + ours('sway', swayConf()));
    });

    test('sway gets the line in ~/.sway/config when it exists, as sway reads it first',
        () async {
      wm = 'sway';
      put(swayHomeConf(), '');
      put(swayConf(), '');

      await LinuxAutostart.setEnabled(true);

      expect(swayHomeConf().readAsStringSync(), ours('sway', swayHomeConf()));
      expect(swayConf().readAsStringSync(), '');
    });

    test('river gets the line right after the shebang, before an exec at the end',
        () async {
      wm = 'river';
      const body = 'riverctl map normal Super Return spawn foot\n'
          'exec rivertile -view-padding 6\n';
      put(riverInit(), '#!/bin/sh\n$body');

      await LinuxAutostart.setEnabled(true);
      expect(riverInit().readAsStringSync(),
          '#!/bin/sh\n${ours('river', riverInit())}$body');

      await LinuxAutostart.setEnabled(false);
      expect(riverInit().readAsStringSync(), '#!/bin/sh\n$body');
    });

    test('a river init in another language is left alone', () async {
      wm = 'river';
      const own = "#!/usr/bin/env python3\nprint('river')\n";
      put(riverInit(), own);

      await LinuxAutostart.setEnabled(true);

      expect(riverInit().readAsStringSync(), own);
    });

    test('niri started without niri-session gets spawn-at-startup', () async {
      wm = 'niri';
      const own = 'input {\n    keyboard {\n    }\n}\n';
      put(niriConf(), own);

      await LinuxAutostart.setEnabled(true);

      expect(niriConf().readAsStringSync(), own + ours('niri', niriConf()));
    });

    test('in a sway session the Hyprland line stays for Hyprland', () async {
      wm = 'sway';
      enabledEarlier();
      final text = ours('hyprland', caelestia());
      put(caelestia(), text);
      put(swayConf(), '');

      await LinuxAutostart.refresh();

      expect(caelestia().readAsStringSync(), text);
      expect(swayConf().readAsStringSync(), ours('sway', swayConf()));
    });

    test('turning autostart off takes the line out of every compositor',
        () async {
      put(caelestia(), '-- mine\n${ours('hyprland', caelestia())}');
      put(swayConf(), '# mine\n${ours('sway', swayConf())}');
      put(riverInit(), '#!/bin/sh\n${ours('river', riverInit())}# mine\n');
      put(niriConf(), '// mine\n${ours('niri', niriConf())}');

      await LinuxAutostart.setEnabled(false);

      expect(caelestia().readAsStringSync(), '-- mine\n');
      expect(swayConf().readAsStringSync(), '# mine\n');
      expect(riverInit().readAsStringSync(), '#!/bin/sh\n# mine\n');
      expect(niriConf().readAsStringSync(), '// mine\n');
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
