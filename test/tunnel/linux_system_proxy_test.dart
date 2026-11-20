import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/tunnel/linux_system_proxy.dart';

/// gsettings и kreadconfig/kwriteconfig в памяти. gsettings отдаёт значения в
/// записи GVariant: строки в кавычках, числа и списки как есть — так же, как
/// настоящий, иначе снимок и возврат проверялись бы не на тех данных.
class _FakeDesktop {
  _FakeDesktop({this.hasGsettings = true, this.hasKde = false});

  final bool hasGsettings;
  final bool hasKde;
  final calls = <String>[];

  final gnome = <String, String>{
    'org.gnome.system.proxy mode': "'none'",
    'org.gnome.system.proxy ignore-hosts': "['localhost', '127.0.0.0/8']",
    'org.gnome.system.proxy.http host': "''",
    'org.gnome.system.proxy.http port': '8080',
    'org.gnome.system.proxy.https host': "''",
    'org.gnome.system.proxy.https port': '0',
    'org.gnome.system.proxy.socks host': "''",
    'org.gnome.system.proxy.socks port': '0',
  };
  final kde = <String, String>{};

  static String _asVariant(String value) {
    if (value.startsWith("'") ||
        value.startsWith('[') ||
        value.startsWith('@') ||
        int.tryParse(value) != null) {
      return value;
    }
    return "'$value'";
  }

  Future<ProcessResult?> run(String exe, List<String> args) async {
    calls.add('$exe ${args.join(' ')}');
    ProcessResult ok([String out = '']) => ProcessResult(0, 0, out, '');
    switch (exe) {
      case 'gsettings' when hasGsettings:
        final key = '${args[1]} ${args[2]}';
        if (args[0] == 'get') return ok('${gnome[key]}\n');
        gnome[key] = _asVariant(args[3]);
        return ok();
      case 'kreadconfig6' when hasKde:
        return ok('${kde[args[5]] ?? ''}\n');
      case 'kwriteconfig6' when hasKde:
        if (args[6] == '--delete') {
          kde.remove(args[5]);
        } else {
          kde[args[5]] = args[6];
        }
        return ok();
      case 'dbus-send':
        return ok();
    }
    return null;
  }
}

void main() {
  late Directory tmp;
  late File backup;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('keq_sysproxy_');
    backup = File('${tmp.path}/system_proxy_backup.json');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  LinuxSystemProxy proxyFor(_FakeDesktop d, {String desktop = 'GNOME'}) =>
      LinuxSystemProxy(run: d.run, backupFile: backup, desktop: desktop);

  group('GNOME settings', () {
    test('points the system at the local ports', () async {
      final d = _FakeDesktop();
      expect(await proxyFor(d).enable(httpPort: 2081, socksPort: 2080), isTrue);

      expect(d.gnome['org.gnome.system.proxy mode'], "'manual'");
      expect(d.gnome['org.gnome.system.proxy.http host'], "'127.0.0.1'");
      expect(d.gnome['org.gnome.system.proxy.http port'], '2081');
      expect(d.gnome['org.gnome.system.proxy.https port'], '2081');
      expect(d.gnome['org.gnome.system.proxy.socks port'], '2080');
    });

    test('gives back the proxy the user had before connecting', () async {
      final d = _FakeDesktop();
      d.gnome['org.gnome.system.proxy mode'] = "'manual'";
      d.gnome['org.gnome.system.proxy.http host'] = "'proxy.corp'";
      d.gnome['org.gnome.system.proxy.http port'] = '3128';
      final before = Map.of(d.gnome);

      final proxy = proxyFor(d);
      await proxy.enable(httpPort: 2081, socksPort: 2080);
      await proxy.disable();

      expect(d.gnome, before);
      expect(backup.existsSync(), isFalse);
    });

    test('finishes the restore on the next start after a crash', () async {
      final d = _FakeDesktop();
      final before = Map.of(d.gnome);
      await proxyFor(d).enable(httpPort: 2081, socksPort: 2080);
      // Новый процесс: тот же файл-снимок, сессия до disable не дошла.
      await proxyFor(d).disable();

      expect(d.gnome, before);
    });

    test(
      'a second connect after a crash keeps the original snapshot',
      () async {
        final d = _FakeDesktop();
        final before = Map.of(d.gnome);
        await proxyFor(d).enable(httpPort: 2081, socksPort: 2080);
        await proxyFor(d).enable(httpPort: 3081, socksPort: 3080);
        await proxyFor(d).disable();

        expect(d.gnome, before);
      },
    );

    test('leaves alone a proxy the user set while connected', () async {
      final d = _FakeDesktop();
      final proxy = proxyFor(d);
      await proxy.enable(httpPort: 2081, socksPort: 2080);
      d.gnome['org.gnome.system.proxy.http host'] = "'proxy.corp'";

      await proxy.disable();

      expect(d.gnome['org.gnome.system.proxy mode'], "'manual'");
      expect(d.gnome['org.gnome.system.proxy.http host'], "'proxy.corp'");
      expect(backup.existsSync(), isFalse);
    });
  });

  group('without a snapshot', () {
    test('switches off the proxy an older version left behind', () async {
      final d = _FakeDesktop();
      d.gnome['org.gnome.system.proxy mode'] = "'manual'";
      d.gnome['org.gnome.system.proxy.http host'] = "'127.0.0.1'";
      d.gnome['org.gnome.system.proxy ignore-hosts'] =
          "['localhost', '127.0.0.0/8', '::1']";

      await proxyFor(d).disable();

      expect(d.gnome['org.gnome.system.proxy mode'], "'none'");
    });

    test('does not touch somebody else\'s proxy', () async {
      final d = _FakeDesktop();
      d.gnome['org.gnome.system.proxy mode'] = "'manual'";
      d.gnome['org.gnome.system.proxy.http host'] = "'proxy.corp'";

      await proxyFor(d).disable();

      expect(d.gnome['org.gnome.system.proxy mode'], "'manual'");
      expect(d.calls.where((c) => c.contains(' set ')), isEmpty);
    });
  });

  group('KDE', () {
    test('writes kioslaverc in a KDE session and tells KIO about it', () async {
      final d = _FakeDesktop(hasKde: true);
      await proxyFor(d, desktop: 'KDE').enable(httpPort: 2081, socksPort: 2080);

      expect(d.kde['ProxyType'], '1');
      expect(d.kde['httpProxy'], 'http://127.0.0.1 2081');
      expect(d.kde['socksProxy'], 'socks://127.0.0.1 2080');
      expect(d.calls.any((c) => c.startsWith('dbus-send')), isTrue);
    });

    test(
      'restores the previous KDE settings, dropping keys it added',
      () async {
        final d = _FakeDesktop(hasKde: true);
        d.kde['ProxyType'] = '0';
        final proxy = proxyFor(d, desktop: 'KDE');

        await proxy.enable(httpPort: 2081, socksPort: 2080);
        await proxy.disable();

        expect(d.kde, {'ProxyType': '0'});
      },
    );

    test('is not touched outside a KDE session', () async {
      final d = _FakeDesktop(hasKde: true);
      await proxyFor(
        d,
        desktop: 'Hyprland',
      ).enable(httpPort: 2081, socksPort: 2080);

      expect(d.calls.where((c) => c.startsWith('kwriteconfig')), isEmpty);
    });
  });

  test(
    'reports failure and keeps no snapshot when no desktop takes it',
    () async {
      final d = _FakeDesktop(hasGsettings: false);
      expect(
        await proxyFor(
          d,
          desktop: 'Hyprland',
        ).enable(httpPort: 2081, socksPort: 2080),
        isFalse,
      );
      expect(backup.existsSync(), isFalse);
    },
  );
}
