import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../core/connections_poll_stats.dart';
import '../models/connection_entry.dart';
import '../platform/vpn_native_bridge.dart';
import '../tunnel/linux_tunnel_backend.dart';
import '../tunnel/windows_tunnel_backend.dart';
import '../utils/mihomo_api_session.dart';
import '../utils/mihomo_config_gen.dart';
import 'connections_tracker.dart';
import 'debug_log_service.dart';
import 'xray_route_decisions.dart';

class ConnectionsService {
  ConnectionsService._();

  static const _androidLogLines = 1200;

  static final ConnectionsTracker _tracker = ConnectionsTracker();

  static void resetTracker() {
    _tracker.reset();
    _appNames.clear();
  }

  static Future<ConnectionsSnapshot> snapshot() async {
    final raw = await _rawSnapshot();
    return _tracker.merge(raw, sessionToken: _sessionToken(raw));
  }

  static Future<ConnectionsSnapshot> _rawSnapshot() async {
    if (Platform.isWindows || Platform.isLinux) {
      final api = await _fromClashApi();
      if (api.source == ConnectionsSource.coreApi) return api;
      final log = await _fromAccessLog();
      return log.entries.isEmpty ? api : log;
    }
    if (Platform.isAndroid) {
      if (MihomoApiSession().isActive) {
        final api = await _fromClashApi();
        if (api.source == ConnectionsSource.coreApi) {
          return _withAndroidAppNamesFromSource(api);
        }
        return api;
      }
      return _fromAccessLog();
    }
    return const ConnectionsSnapshot(
      entries: [],
      source: ConnectionsSource.unavailable,
      note: 'Connections view is not supported on this platform.',
    );
  }

  static String _sessionToken(ConnectionsSnapshot snapshot) =>
      '${snapshot.source.name}:${activeClashPort() ?? ''}';

  static bool get supportsProcessNames =>
      Platform.isWindows || Platform.isLinux || Platform.isAndroid;

  static int? activeClashPort() {
    if (Platform.isWindows) return WindowsTunnelBackend.activeInstance?.clashApiPort;
    if (Platform.isLinux) return LinuxTunnelBackend.activeInstance?.clashApiPort;
    if (Platform.isAndroid) return MihomoApiSession().port;
    return null;
  }

  static String activeClashSecret() => Platform.isLinux
      ? LinuxTunnelBackend.activeInstance?.clashApiSecret ?? ''
      : MihomoApiSession().secret;

  static Future<ConnectionsSnapshot> _fromClashApi() async {
    final port = activeClashPort();
    if (port == null) {
      return const ConnectionsSnapshot(
        entries: [],
        source: ConnectionsSource.unavailable,
        note: 'No active core session.',
      );
    }

    final poll = ConnectionsPollStats.instance.begin();
    var ok = false;
    var chars = 0;
    int? connections;
    try {
      final req = await _http
          .get('127.0.0.1', port, '/connections')
          .timeout(const Duration(seconds: 3));
      final secret = activeClashSecret();
      if (secret.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }
      final resp = await req.close().timeout(const Duration(seconds: 3));
      if (resp.statusCode != 200) {
        await resp.drain<void>();
        return ConnectionsSnapshot(
          entries: const [],
          source: ConnectionsSource.unavailable,
          note: 'Core API answered HTTP ${resp.statusCode}.',
        );
      }
      final body = await resp
          .transform(utf8.decoder)
          .join()
          .timeout(connectionsBodyTimeout);
      chars = body.length;
      poll.stop();
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic>) {
        return const ConnectionsSnapshot(
          entries: [],
          source: ConnectionsSource.unavailable,
          note: 'Unexpected core API payload.',
        );
      }
      final raw = json['connections'];
      if (raw is List) connections = raw.length;
      ok = true;
      final entries = <ConnectionEntry>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is! Map) continue;
          final entry = entryFromClashJson(item.cast<String, dynamic>());
          if (entry != null) entries.add(entry);
        }
      }
      entries.sort((a, b) {
        final at = a.startedAt, bt = b.startedAt;
        if (at == null || bt == null) return 0;
        return bt.compareTo(at);
      });

      // у mihomo правило в ответе уже настоящее, а аутбаунд тоже зовётся proxy:
      // через _resolveEngineVerdicts оно затёрлось бы
      final needsEngineVerdicts = !MihomoApiSession().isActive;
      final resolved =
          needsEngineVerdicts ? _resolveEngineVerdicts(entries) : entries;
      return ConnectionsSnapshot(
        entries: resolved,
        source: ConnectionsSource.coreApi,
        // ни одного решения за сессию при соединениях через движок: ядро их не
        // печатает, уровень логов ниже Info
        ruleInfoAvailable: !resolved.any((e) => e.decidedByCore) ||
            !XrayRouteDecisions.isEmpty,
      );
    } catch (e) {
      _resetHttp();
      return ConnectionsSnapshot(
        entries: const [],
        source: ConnectionsSource.unavailable,
        note: 'Core API unreachable: $e',
      );
    } finally {
      ConnectionsPollStats.instance
          .end(poll, ok: ok, bodyChars: chars, connections: connections);
    }
  }

  static const _engineOutboundTag = 'proxy';

  static List<ConnectionEntry> _resolveEngineVerdicts(
    List<ConnectionEntry> entries,
  ) {
    return [
      for (final entry in entries)
        if (entry.outbound.toLowerCase() != _engineOutboundTag)
          entry
        else
          _applyDecision(entry),
    ];
  }

  static ConnectionEntry _applyDecision(ConnectionEntry entry) {
    final decision = XrayRouteDecisions.forTarget(
      XrayAccessLogParser.targetKeyFor(
        entry.network,
        entry.host,
        entry.destPort,
      ),
    );
    if (decision == null || decision.outbound.isEmpty) {
      return entry.withRouting(
        rule: '',
        outbound: entry.outbound,
        decidedByCore: true,
      );
    }
    return entry.withRouting(
      rule: decision.rule,
      outbound: decision.outbound,
      decidedByCore: false,
    );
  }

  static HttpClient? _httpClient;

  static HttpClient get _http => _httpClient ??= HttpClient()
    ..connectionTimeout = const Duration(seconds: 2)
    ..idleTimeout = const Duration(seconds: 15);

  // поле обнуляем до закрытия, иначе рекурсия через catch рвущихся запросов
  static void _resetHttp() {
    final client = _httpClient;
    _httpClient = null;
    client?.close(force: true);
  }

  @visibleForTesting
  static ConnectionEntry? entryFromClashJson(Map<String, dynamic> json) {
    final meta = json['metadata'];
    if (meta is! Map) return null;
    final m = meta.cast<String, dynamic>();

    String str(String key) => m[key]?.toString().trim() ?? '';
    final destIp = str('destinationIP');
    final host = str('host').isNotEmpty ? str('host') : destIp;
    if (host.isEmpty) return null;

    final chains = (json['chains'] is List)
        ? (json['chains'] as List).map((e) => e.toString()).toList()
        : const <String>[];
    // у xray звенья цепочки в журнал не пишутся, у mihomo это его собственное соединение к следующему узлу
    if (chains.any(MihomoConfigGen.isChainHop)) return null;

    final ruleType = json['rule']?.toString().trim() ?? '';
    final rulePayload = json['rulePayload']?.toString().trim() ?? '';
    final rule = switch (ruleType.toLowerCase()) {
      '' || 'final' || 'match' => '',
      _ => rulePayload.isEmpty ? ruleType : '$ruleType($rulePayload)',
    };

    final id = json['id']?.toString() ??
        '${str('sourceIP')}:${str('sourcePort')}>$host:${str('destinationPort')}';

    return ConnectionEntry(
      id: id,
      network: str('network').isEmpty ? 'tcp' : str('network'),
      host: host,
      destPort: int.tryParse(str('destinationPort')) ?? 0,
      destIp: destIp == host ? '' : destIp,
      source: str('sourceIP').isEmpty
          ? ''
          : '${str('sourceIP')}:${str('sourcePort')}',
      process: str('processPath'),
      inbound: str('type'),
      // chains идут от внешнего аутбаунда к внутреннему, нужен первый
      outbound: chains.isEmpty ? '' : chains.first,
      rule: rule,
      startedAt: DateTime.tryParse(json['start']?.toString() ?? '')?.toLocal(),
      upload: (json['upload'] as num?)?.toInt(),
      download: (json['download'] as num?)?.toInt(),
    );
  }

  static Future<ConnectionsSnapshot> _fromAccessLog() async {
    final text = await DebugLogService.getXrayLogs(maxLines: _androidLogLines);
    if (text.trim().isEmpty) {
      return const ConnectionsSnapshot(
        entries: [],
        source: ConnectionsSource.unavailable,
        note: 'Core log is empty. Connect first.',
      );
    }
    final snapshot = XrayAccessLogParser.parse(text);
    if (!Platform.isAndroid) return snapshot;
    return _withAndroidAppNamesFromSource(snapshot);
  }

  static Future<ConnectionsSnapshot> _withAndroidAppNamesFromSource(
    ConnectionsSnapshot snapshot,
  ) async =>
      withAppNamesFromSource(
        snapshot,
        resolve: VpnNativeBridge.resolveConnectionOwners,
        cache: _appNames,
      );

  @visibleForTesting
  static Future<ConnectionsSnapshot> withAppNamesFromSource(
    ConnectionsSnapshot snapshot, {
    required Future<List<String>> Function(List<Map<String, Object?>>) resolve,
    Map<String, String>? cache,
  }) async {
    final entries = [...snapshot.entries];
    final indexes = <int>[];
    final requests = <Map<String, Object?>>[];
    var fromCache = false;
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final known = cache?[entry.id];
      if (known != null && known.isNotEmpty) {
        entries[i] = entry.withProcess(known);
        fromCache = true;
        continue;
      }
      if (entry.closed) continue;
      final source = _splitHostPort(entry.source);
      if (source == null) continue;
      final ip = entry.destIp.isNotEmpty ? entry.destIp : entry.host;
      if (ip.isEmpty) continue;
      indexes.add(i);
      requests.add({
        'protocol': entry.network,
        'srcIp': source.host,
        'srcPort': source.port,
        'dstIp': ip,
        'dstPort': entry.destPort,
      });
    }
    if (requests.isEmpty && !fromCache) {
      return entries.isEmpty ? snapshot : _withoutAppNames(snapshot);
    }
    final names = requests.isEmpty
        ? const <String>[]
        : await resolve(requests);
    for (var i = 0; i < indexes.length && i < names.length; i++) {
      final name = names[i];
      if (name.isEmpty) continue;
      final index = indexes[i];
      entries[index] = entries[index].withProcess(name);
      if (cache != null) {
        cache[entries[index].id] = name;
        while (cache.length > _appNamesLimit) {
          cache.remove(cache.keys.first);
        }
      }
    }
    return ConnectionsSnapshot(
      entries: entries,
      source: snapshot.source,
      note: snapshot.note,
      ruleInfoAvailable: snapshot.ruleInfoAvailable,
      appNamesAvailable: snapshot.appNamesAvailable,
    );
  }

  static ({String host, int port})? _splitHostPort(String value) {
    final colon = value.lastIndexOf(':');
    if (colon <= 0) return null;
    final port = int.tryParse(value.substring(colon + 1));
    if (port == null || port <= 0) return null;
    return (host: value.substring(0, colon), port: port);
  }

  static ConnectionsSnapshot _withoutAppNames(ConnectionsSnapshot s) =>
      ConnectionsSnapshot(
        entries: s.entries,
        source: s.source,
        note: s.note,
        ruleInfoAvailable: s.ruleInfoAvailable,
        appNamesAvailable: false,
      );

  static final Map<String, String> _appNames = {};
  static const _appNamesLimit = 300;

}

class XrayAccessLogParser {
  XrayAccessLogParser._();

  // -> правило сработало, >> дефолтный аутбаунд, ==> тег навязан платформой
  static final _access = RegExp(
    r'from\s+(\S+)\s+(accepted|rejected)\s+([a-z0-9]+):(.+?):(\d+)'
    r'(?:\s+\[([^\]]*)\])?',
    caseSensitive: false,
  );

  // tool/patches/xray-desktop-process.patch, последним: в пути бывают пробелы
  static final _process = RegExp(r'\sprocess:\s(.+)$');

  static final _detour = RegExp(
    r'(?:Hit route rule:\s*\[([^\]]*)\]\s*so\s*)?taking detour\s*'
    r'\[([^\]]*)\]\s*for\s*\[([a-z0-9]+):(.+?):(\d+)\]',
    caseSensitive: false,
  );

  static final _defaultRoute = RegExp(
    r'default route for\s+([a-z0-9]+):(.+?):(\d+)',
    caseSensitive: false,
  );

  static final _timestamp = RegExp(
    r'(\d{4})/(\d{2})/(\d{2})\s+(\d{2}):(\d{2}):(\d{2})',
  );

  static final _deviceTimestamp = RegExp(
    r'^(\d{2})-(\d{2})\s+(\d{2}):(\d{2}):(\d{2})\s',
  );

  static final _sessionLine = RegExp(r'\[Info\]\s*\[(\d+)\]\s*(.+)$');

  static final _sessionDest = RegExp(
    r'(?:TCP Connect request to|establishing new connection for)\s+'
    r'([a-z0-9]+):(.+?):(\d+)\s*$',
    caseSensitive: false,
  );

  static final _sessionClient = RegExp(
    r'client UDP connection from\s+(\S+)',
    caseSensitive: false,
  );

  static final _sessionTun = RegExp(
    r'processing from\s+(\S+)\s+to\s+([a-z0-9]+):(.+?):(\d+)\s*$',
    caseSensitive: false,
  );

  // в access-строку SNI не попадает: инбаунд пишет назначение раньше сниффера
  static final _sessionSniffed = RegExp(
    r'sniffed domain:\s*(\S+)',
    caseSensitive: false,
  );

  static final _sessionEnded = RegExp(
    r'connection ends',
    caseSensitive: false,
  );

  static Map<String, XrayRouteDecision> parseRouteDecisions(String log) {
    final byTarget = <String, XrayRouteDecision>{};
    for (final line in log.split('\n')) {
      final detour = _detour.firstMatch(line);
      if (detour != null) {
        final target =
            _targetKey(detour.group(3), detour.group(4), detour.group(5));
        byTarget[target] = XrayRouteDecision(
          rule: detour.group(1)?.trim() ?? '',
          outbound: detour.group(2)?.trim() ?? '',
        );
        continue;
      }
      final fallback = _defaultRoute.firstMatch(line);
      if (fallback != null) {
        final target = _targetKey(
          fallback.group(1),
          fallback.group(2),
          fallback.group(3),
        );
        byTarget[target] = XrayRouteDecision(
          rule: _defaultRouteMarker,
          outbound: byTarget[target]?.outbound ?? '',
        );
      }
    }
    return byTarget;
  }

  static Map<String, XraySessionTrace> parseSessions(String log) {
    final sessions = <String, XraySessionTrace>{};
    for (final raw in log.split('\n')) {
      final match = _sessionLine.firstMatch(raw.trimRight());
      if (match == null) continue;
      final trace = sessions.putIfAbsent(
        match.group(1)!,
        XraySessionTrace.new,
      );
      final rest = match.group(2)!;

      if (_sessionEnded.hasMatch(rest)) {
        trace.closed = true;
        continue;
      }
      final sniffed = _sessionSniffed.firstMatch(rest);
      if (sniffed != null) {
        trace.domain = sniffed.group(1)!.trim();
        continue;
      }
      final tun = _sessionTun.firstMatch(rest);
      if (tun != null) {
        trace.clientKey = tun.group(1)!.trim().toLowerCase();
        trace.destKey = _targetKey(tun.group(2), tun.group(3), tun.group(4));
        continue;
      }
      final client = _sessionClient.firstMatch(rest);
      if (client != null) {
        trace.clientKey = client.group(1)!.trim().toLowerCase();
        continue;
      }
      final dest = _sessionDest.firstMatch(rest);
      if (dest != null) {
        trace.destKey =
            _targetKey(dest.group(1), dest.group(2), dest.group(3));
        continue;
      }
      final detour = _detour.firstMatch(rest);
      if (detour != null) {
        trace.rule = detour.group(1)?.trim() ?? '';
        trace.outbound = detour.group(2)?.trim() ?? '';
        continue;
      }
      if (_defaultRoute.hasMatch(rest)) trace.rule = _defaultRouteMarker;
    }
    return sessions;
  }

  static ConnectionsSnapshot parse(String log) {
    final decisions = parseRouteDecisions(log);
    final sawRoutingLines = decisions.isNotEmpty;
    final rulesByTarget = {
      for (final e in decisions.entries)
        if (e.value.rule.isNotEmpty) e.key: e.value.rule,
    };
    final outboundByTarget = {
      for (final e in decisions.entries)
        if (e.value.outbound.isNotEmpty) e.key: e.value.outbound,
    };

    // k-я access-строка получает k-ю сессию: при выигрыше последней закрытие одного соединения вешалось на все
    final sessions = parseSessions(log);
    final byClient = <String, XraySessionTrace>{};
    final byDest = <String, List<XraySessionTrace>>{};
    for (final trace in sessions.values) {
      if (trace.clientKey.isNotEmpty) byClient[trace.clientKey] = trace;
      if (trace.destKey.isNotEmpty) {
        byDest.putIfAbsent(trace.destKey, () => []).add(trace);
      }
    }
    final destCursor = <String, int>{};

    final lines = log.split('\n');

    final entries = <String, ConnectionEntry>{};
    for (final line in lines) {
      final m = _access.firstMatch(line);
      if (m == null) continue;

      final source = m.group(1)!.trim();
      final rejected = m.group(2)!.toLowerCase() == 'rejected';
      final network = m.group(3)!.toLowerCase();
      final host = m.group(4)!.trim();
      final port = int.tryParse(m.group(5)!) ?? 0;
      if (host.isEmpty) continue;

      final detourField = m.group(6)?.trim() ?? '';
      final (inbound, outbound) = _splitDetour(detourField);
      final target = _targetKey(network, host, '$port');
      final trace = byClient[source.toLowerCase()] ??
          _nextTraceForDest(byDest[target], target, destCursor);

      final domain = trace?.domain ?? '';
      final id = '$source>$network:$host:$port';
      entries[id] = ConnectionEntry(
        id: id,
        network: network,
        host: domain.isNotEmpty ? domain : host,
        destPort: port,
        destIp: domain.isNotEmpty ? host : '',
        source: _plainAddress(source),
        process: _process.firstMatch(line)?.group(1)?.trim() ?? '',
        inbound: inbound,
        outbound: outbound.isNotEmpty
            ? outbound
            : (trace?.outbound.isNotEmpty ?? false)
                ? trace!.outbound
                : (outboundByTarget[target] ?? ''),
        rule: (trace?.rule.isNotEmpty ?? false)
            ? trace!.rule
            : (rulesByTarget[target] ?? ''),
        startedAt: _parseTimestamp(line),
        rejected: rejected,
        closed: trace?.closed ?? false,
      );
    }

    final seen = entries.values.toList().reversed;
    final list = [
      ...seen.where((e) => !e.closed),
      ...seen.where((e) => e.closed),
    ];
    return ConnectionsSnapshot(
      entries: list,
      source: ConnectionsSource.coreLog,
      ruleInfoAvailable: sawRoutingLines,
    );
  }

  static XraySessionTrace? _nextTraceForDest(
    List<XraySessionTrace>? traces,
    String target,
    Map<String, int> cursor,
  ) {
    if (traces == null || traces.isEmpty) return null;
    final index = cursor.update(target, (v) => v + 1, ifAbsent: () => 0);
    return index < traces.length ? traces[index] : traces.last;
  }

  static const _defaultRouteMarker = '*';

  static String targetKeyFor(String network, String host, int port) =>
      _targetKey(network, host, '$port');

  static const _finalRuleTag = 'final';

  static bool isDefaultRoute(String rule) =>
      rule == _defaultRouteMarker || rule == _finalRuleTag;

  static String _targetKey(String? network, String? host, String? port) =>
      '${network?.toLowerCase()}:${host?.trim().toLowerCase()}:$port';

  // приставку сети xray дописывает сам, а система ищет владельца по голому адресу
  static String _plainAddress(String address) =>
      address.replaceFirst(RegExp(r'^(tcp|udp):', caseSensitive: false), '');

  static (String inbound, String outbound) _splitDetour(String raw) {
    if (raw.isEmpty) return ('', '');
    for (final sep in const [' ==> ', ' -> ', ' >> ']) {
      final idx = raw.indexOf(sep);
      if (idx >= 0) {
        return (
          raw.substring(0, idx).trim(),
          raw.substring(idx + sep.length).trim(),
        );
      }
    }
    return ('', raw.trim());
  }

  static DateTime? _parseTimestamp(String line) {
    final xray = _timestamp.firstMatch(line);
    // штамп xray в UTC, префикс от forkexec.c в местном времени, год берём из штампа
    final device = _deviceTimestamp.firstMatch(line);
    try {
      if (device != null) {
        return DateTime(
          xray != null ? int.parse(xray.group(1)!) : DateTime.now().year,
          int.parse(device.group(1)!),
          int.parse(device.group(2)!),
          int.parse(device.group(3)!),
          int.parse(device.group(4)!),
          int.parse(device.group(5)!),
        );
      }
      if (xray == null) return null;
      return DateTime(
        int.parse(xray.group(1)!),
        int.parse(xray.group(2)!),
        int.parse(xray.group(3)!),
        int.parse(xray.group(4)!),
        int.parse(xray.group(5)!),
        int.parse(xray.group(6)!),
      );
    } catch (_) {
      return null;
    }
  }
}

class XraySessionTrace {
  String destKey = '';

  String clientKey = '';

  String domain = '';

  String rule = '';
  String outbound = '';

  bool closed = false;
}


class XrayRouteDecision {
  const XrayRouteDecision({required this.rule, required this.outbound});

  final String rule;

  final String outbound;
}
