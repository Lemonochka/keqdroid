import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/app_logger.dart';

typedef SettingsTool = Future<ProcessResult?> Function(
  String executable,
  List<String> args,
);

// настройки GNOME читают Firefox и GTK в любой среде, KDE только в своей сессии,
// а в XFCE, Hyprland и подобных Chromium берёт прокси из окружения при запуске
class LinuxSystemProxy {
  LinuxSystemProxy({
    required this.run,
    required this.backupFile,
    required this.desktop,
  });

  static Future<LinuxSystemProxy> system() async {
    final dir = await getApplicationSupportDirectory();
    return LinuxSystemProxy(
      run: _runTool,
      backupFile: File(p.join(dir.path, 'system_proxy_backup.json')),
      desktop: Platform.environment['XDG_CURRENT_DESKTOP'] ?? '',
    );
  }

  final SettingsTool run;
  final File backupFile;

  final String desktop;

  static const _host = '127.0.0.1';

  // по этому списку исключений узнаётся наш прокси от упавшей версии без снимка
  static const _ignoreHosts = "['localhost', '127.0.0.0/8', '::1']";

  static const _gnomeKeys = [
    ('org.gnome.system.proxy', 'mode'),
    ('org.gnome.system.proxy', 'ignore-hosts'),
    ('org.gnome.system.proxy.http', 'host'),
    ('org.gnome.system.proxy.http', 'port'),
    ('org.gnome.system.proxy.https', 'host'),
    ('org.gnome.system.proxy.https', 'port'),
    ('org.gnome.system.proxy.socks', 'host'),
    ('org.gnome.system.proxy.socks', 'port'),
  ];

  static const _kdeKeys = [
    'ProxyType',
    'httpProxy',
    'httpsProxy',
    'socksProxy',
    'NoProxyFor',
  ];

  bool get _isKde => desktop.split(':').contains('KDE');

  Future<bool> enable({required int httpPort, required int socksPort}) async {
    // снимок уже лежит, если прошлая сессия упала: в нём настоящие настройки, а текущие наши
    if (!backupFile.existsSync()) {
      final gnome = await _readGnome();
      final kde = _isKde ? await _readKde() : null;
      if (gnome == null && kde == null) return false;
      backupFile.parent.createSync(recursive: true);
      backupFile.writeAsStringSync(jsonEncode({'gnome': ?gnome, 'kde': ?kde}));
    }

    var applied = false;
    if (await _gsettingsGet('org.gnome.system.proxy', 'mode') != null) {
      for (final (schema, port) in [
        ('org.gnome.system.proxy.http', httpPort),
        ('org.gnome.system.proxy.https', httpPort),
        ('org.gnome.system.proxy.socks', socksPort),
      ]) {
        await _gsettings(['set', schema, 'host', _host]);
        await _gsettings(['set', schema, 'port', '$port']);
      }
      await _gsettings(['set', 'org.gnome.system.proxy', 'ignore-hosts', _ignoreHosts]);
      applied = await _gsettings(['set', 'org.gnome.system.proxy', 'mode', 'manual']);
    }

    if (_isKde) {
      // хост и порт через пробел, как пишет сама KDE
      final kdeApplied = await _writeKde({
        'httpProxy': 'http://$_host $httpPort',
        'httpsProxy': 'http://$_host $httpPort',
        'socksProxy': 'socks://$_host $socksPort',
        'NoProxyFor': 'localhost,127.0.0.0/8,::1',
        'ProxyType': '1',
      });
      applied = applied || kdeApplied;
    }
    return applied;
  }

  Future<void> disable() async {
    final backup = _readBackup();
    if (backup == null) {
      await _resetUnbackedLeftover();
      return;
    }

    final gnome = backup['gnome'];
    if (gnome is Map && await _gnomeStillOurs()) {
      for (final (schema, key) in _gnomeKeys) {
        final value = gnome['$schema $key'];
        if (value is String) await _gsettings(['set', schema, key, value]);
      }
    }

    final kde = backup['kde'];
    if (kde is Map && _isKde && await _kdeStillOurs()) {
      await _writeKde({
        for (final key in _kdeKeys) key: kde[key] is String ? kde[key] as String : '',
      });
    }

    try {
      backupFile.deleteSync();
    } on FileSystemException {
      // уже нет
    }
  }

  Map<String, Object?>? _readBackup() {
    try {
      if (!backupFile.existsSync()) return null;
      final data = jsonDecode(backupFile.readAsStringSync());
      return data is Map<String, Object?> ? data : null;
    } catch (e) {
      AppLogger.instance.warn('System proxy backup is unreadable', error: e);
      return null;
    }
  }

  Future<void> _resetUnbackedLeftover() async {
    final mode = await _gsettingsGet('org.gnome.system.proxy', 'mode');
    final host = await _gsettingsGet('org.gnome.system.proxy.http', 'host');
    final ignore = await _gsettingsGet('org.gnome.system.proxy', 'ignore-hosts');
    if (mode == "'manual'" && host == "'$_host'" && ignore == _ignoreHosts) {
      await _gsettings(['set', 'org.gnome.system.proxy', 'mode', 'none']);
    }
  }

  Future<bool> _gnomeStillOurs() async =>
      await _gsettingsGet('org.gnome.system.proxy', 'mode') == "'manual'" &&
      await _gsettingsGet('org.gnome.system.proxy.http', 'host') == "'$_host'";

  Future<bool> _kdeStillOurs() async {
    final values = await _readKde();
    return values != null &&
        values['ProxyType'] == '1' &&
        (values['httpProxy'] ?? '').startsWith('http://$_host ');
  }

  Future<Map<String, String>?> _readGnome() async {
    final out = <String, String>{};
    for (final (schema, key) in _gnomeKeys) {
      final value = await _gsettingsGet(schema, key);
      if (value == null) return null;
      out['$schema $key'] = value;
    }
    return out;
  }

  Future<String?> _gsettingsGet(String schema, String key) async {
    final r = await run('gsettings', ['get', schema, key]);
    if (r == null || r.exitCode != 0) return null;
    return '${r.stdout}'.trim();
  }

  Future<bool> _gsettings(List<String> args) async {
    final r = await run('gsettings', args);
    return r != null && r.exitCode == 0;
  }

  Future<Map<String, String>?> _readKde() async {
    for (final tool in ['kreadconfig6', 'kreadconfig5']) {
      final out = <String, String>{};
      for (final key in _kdeKeys) {
        final r = await run(tool, [
          '--file', 'kioslaverc', '--group', 'Proxy Settings', '--key', key, //
        ]);
        if (r == null) break;
        out[key] = '${r.stdout}'.trim();
      }
      if (out.length == _kdeKeys.length) return out;
    }
    return null;
  }

  Future<bool> _writeKde(Map<String, String> values) async {
    for (final tool in ['kwriteconfig6', 'kwriteconfig5']) {
      var ok = true;
      var found = true;
      for (final MapEntry(:key, :value) in values.entries) {
        final r = await run(tool, [
          '--file', 'kioslaverc', '--group', 'Proxy Settings', '--key', key, //
          if (value.isEmpty) '--delete' else value,
        ]);
        if (r == null) {
          found = false;
          break;
        }
        ok = ok && r.exitCode == 0;
      }
      if (!found) continue;
      // без сигнала KIO-программы перечитают настройки только после перезапуска
      await run('dbus-send', [
        '--type=signal',
        '/KIO/Scheduler',
        'org.kde.KIO.Scheduler.reparseSlaveConfiguration',
        "string:''",
      ]);
      return ok;
    }
    return false;
  }

  static Future<ProcessResult?> _runTool(String exe, List<String> args) async {
    try {
      return await Process.run(exe, args);
    } on ProcessException {
      return null;
    }
  }
}
