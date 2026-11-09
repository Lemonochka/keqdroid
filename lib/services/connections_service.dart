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
import 'xray_access_log_parser.dart';
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
    // звено dialer-proxy из Clash зовётся по-авторски, без нашего префикса, но ядро помечает его Inner (proxydialer.go)
    if (m['type'] == 'Inner') return null;

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
    final text = _desktopConnectionLines() ??
        await DebugLogService.getXrayLogs(maxLines: _androidLogLines);
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

  static String? _desktopConnectionLines() {
    if (Platform.isWindows) {
      return WindowsTunnelBackend.activeInstance?.exportConnectionLines();
    }
    if (Platform.isLinux) {
      return LinuxTunnelBackend.activeInstance?.exportConnectionLines();
    }
    return null;
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
