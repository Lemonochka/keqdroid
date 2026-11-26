import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/app_logger.dart';

typedef MacosNetworkTool =
    Future<ProcessResult?> Function(String executable, List<String> args);

class MacosSystemProxy {
  MacosSystemProxy({required this.run, required this.backupFile});

  static Future<MacosSystemProxy> system() async {
    final dir = await getApplicationSupportDirectory();
    return MacosSystemProxy(
      run: _runTool,
      backupFile: File(p.join(dir.path, 'system_proxy_backup.json')),
    );
  }

  final MacosNetworkTool run;
  final File backupFile;

  static const _tool = '/usr/sbin/networksetup';
  static const _host = '127.0.0.1';
  static const _appliedKey = '__keqdroid_applied__';
  static const bypassDomains = [
    'localhost',
    '127.0.0.1',
    '::1',
    '169.254/16',
    '*.local',
  ];

  Future<bool> enable({required int httpPort, required int socksPort}) async {
    final services = await listActiveServices();
    if (services.isEmpty) return false;

    // после сбоя сохраняем исходный снимок, добавляя только новые сетевые службы
    final existing = _readBackup();
    final snapshot = existing != null
        ? Map<String, Object?>.of(existing)
        : <String, Object?>{};
    final missing = [
      for (final service in services)
        if (!snapshot.containsKey(service)) service,
    ];
    if (missing.isNotEmpty) {
      final read = await Future.wait(missing.map(_readService));
      for (var i = 0; i < missing.length; i++) {
        final state = read[i];
        if (state != null) snapshot[missing[i]] = state;
      }
    }
    if (!snapshot.keys.any((k) => k != _appliedKey)) return false;

    snapshot[_appliedKey] = {'httpPort': httpPort, 'socksPort': socksPort};
    backupFile.parent.createSync(recursive: true);
    backupFile.writeAsStringSync(jsonEncode(snapshot));

    var applied = false;
    for (final service in services) {
      final web = await _ok(['-setwebproxy', service, _host, '$httpPort']);
      final secure = await _ok([
        '-setsecurewebproxy',
        service,
        _host,
        '$httpPort',
      ]);
      final socks = await _ok([
        '-setsocksfirewallproxy',
        service,
        _host,
        '$socksPort',
      ]);
      await _ok(['-setproxybypassdomains', service, ...bypassDomains]);
      if (web || secure || socks) applied = true;
    }
    return applied;
  }

  Future<void> disable() async {
    final backup = _readBackup();
    if (backup == null) {
      await _resetUnbackedLeftovers();
      return;
    }

    final appliedMeta = backup[_appliedKey];
    final appliedHttpPort = appliedMeta is Map
        ? (appliedMeta['httpPort'] as num?)?.toInt()
        : null;
    final appliedSocksPort = appliedMeta is Map
        ? (appliedMeta['socksPort'] as num?)?.toInt()
        : null;

    for (final MapEntry(key: service, value: raw) in backup.entries) {
      if (service == _appliedKey || raw is! Map) continue;
      await _restoreService(
        service,
        raw.cast<String, Object?>(),
        httpPort: appliedHttpPort,
        socksPort: appliedSocksPort,
      );
    }

    try {
      backupFile.deleteSync();
    } on FileSystemException {
      // Already removed.
    }
  }

  @visibleForTesting
  Future<List<String>> listActiveServices() async {
    final r = await run(_tool, const ['-listallnetworkservices']);
    if (r == null || r.exitCode != 0) return const [];
    final out = <String>[];
    for (final rawLine in '${r.stdout}'.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('An asterisk') || line.startsWith('*')) continue;
      out.add(line);
    }
    return out;
  }

  Future<Map<String, Object?>?> _readService(String service) async {
    final results = await Future.wait([
      _readProxy('-getwebproxy', service),
      _readProxy('-getsecurewebproxy', service),
      _readProxy('-getsocksfirewallproxy', service),
    ]);
    final web = results[0];
    final secure = results[1];
    final socks = results[2];
    if (web == null && secure == null && socks == null) return null;
    final bypass = await _readBypassDomains(service);
    return {'web': ?web, 'secure': ?secure, 'socks': ?socks, 'bypass': ?bypass};
  }

  Future<Map<String, Object?>?> _readProxy(String flag, String service) async {
    final r = await run(_tool, [flag, service]);
    if (r == null || r.exitCode != 0) return null;
    var enabled = false;
    var server = '';
    var port = 0;
    for (final rawLine in '${r.stdout}'.split('\n')) {
      final colon = rawLine.indexOf(':');
      if (colon <= 0) continue;
      final key = rawLine.substring(0, colon).trim().toLowerCase();
      final value = rawLine.substring(colon + 1).trim();
      switch (key) {
        case 'enabled':
          enabled = value.toLowerCase() == 'yes';
        case 'server':
          server = value;
        case 'port':
          port = int.tryParse(value) ?? 0;
      }
    }
    return {'enabled': enabled, 'server': server, 'port': port};
  }

  Future<List<String>?> _readBypassDomains(String service) async {
    final r = await run(_tool, ['-getproxybypassdomains', service]);
    if (r == null || r.exitCode != 0) return null;
    final text = '${r.stdout}'.trim();
    if (text.isEmpty || text.startsWith("There aren't any")) {
      return const [];
    }
    return text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  static bool _isOurs(Map<String, Object?>? proxy, int? expectedPort) {
    if (proxy == null || proxy['enabled'] != true || proxy['server'] != _host) {
      return false;
    }
    if (expectedPort == null) return true;
    return (proxy['port'] as num?)?.toInt() == expectedPort;
  }

  Future<void> _restoreService(
    String service,
    Map<String, Object?> saved, {
    int? httpPort,
    int? socksPort,
  }) async {
    final current = await Future.wait([
      _readProxy('-getwebproxy', service),
      _readProxy('-getsecurewebproxy', service),
      _readProxy('-getsocksfirewallproxy', service),
    ]);
    final webOurs = _isOurs(current[0], httpPort);
    final secureOurs = _isOurs(current[1], httpPort);
    final socksOurs = _isOurs(current[2], socksPort);

    if (webOurs) {
      await _restoreSingle(
        service,
        saved['web'],
        setFlag: '-setwebproxy',
        stateFlag: '-setwebproxystate',
      );
    }
    if (secureOurs) {
      await _restoreSingle(
        service,
        saved['secure'],
        setFlag: '-setsecurewebproxy',
        stateFlag: '-setsecurewebproxystate',
      );
    }
    if (socksOurs) {
      await _restoreSingle(
        service,
        saved['socks'],
        setFlag: '-setsocksfirewallproxy',
        stateFlag: '-setsocksfirewallproxystate',
      );
    }

    final currentBypass = await _readBypassDomains(service);
    if (currentBypass == null || !_sameList(currentBypass, bypassDomains)) {
      return;
    }
    final bypass = saved['bypass'];
    if (bypass is List) {
      final domains = bypass.whereType<String>().toList();
      await _ok([
        '-setproxybypassdomains',
        service,
        ...(domains.isEmpty ? const ['Empty'] : domains),
      ]);
    }
  }

  Future<void> _restoreSingle(
    String service,
    Object? raw, {
    required String setFlag,
    required String stateFlag,
  }) async {
    if (raw is! Map) return;
    final enabled = raw['enabled'] == true;
    final server = (raw['server'] as String? ?? '').trim();
    final port = (raw['port'] as num?)?.toInt() ?? 0;
    if (enabled && server.isNotEmpty && port > 0) {
      await _ok([setFlag, service, server, '$port']);
      await _ok([stateFlag, service, 'on']);
    } else {
      await _ok([stateFlag, service, 'off']);
    }
  }

  Future<void> _resetUnbackedLeftovers() async {
    final services = await listActiveServices();
    for (final service in services) {
      final current = await Future.wait([
        _readProxy('-getwebproxy', service),
        _readProxy('-getsecurewebproxy', service),
        _readProxy('-getsocksfirewallproxy', service),
      ]);
      final webOurs = _isOurs(current[0], null);
      final secureOurs = _isOurs(current[1], null);
      final socksOurs = _isOurs(current[2], null);
      if (!webOurs && !secureOurs && !socksOurs) continue;
      final bypass = await _readBypassDomains(service);
      if (bypass == null || !_sameList(bypass, bypassDomains)) continue;
      if (webOurs) await _ok(['-setwebproxystate', service, 'off']);
      if (secureOurs) {
        await _ok(['-setsecurewebproxystate', service, 'off']);
      }
      if (socksOurs) await _ok(['-setsocksfirewallproxystate', service, 'off']);
      await _ok(['-setproxybypassdomains', service, 'Empty']);
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

  Future<bool> _ok(List<String> args) async {
    final r = await run(_tool, args);
    return r != null && r.exitCode == 0;
  }

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static Future<ProcessResult?> _runTool(String exe, List<String> args) async {
    try {
      return await Process.run(exe, args);
    } on ProcessException {
      return null;
    }
  }
}
