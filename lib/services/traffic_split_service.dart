import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../core/connections_poll_stats.dart';
import '../models/traffic_split.dart';
import '../utils/mihomo_config_gen.dart';

enum TrafficChannel {
  vpn,

  direct,

  blocked,

  unknown,
}

class ConnectionTraffic {
  final String id;
  final List<String> chains;
  final int download;
  final int upload;

  const ConnectionTraffic({
    required this.id,
    required this.chains,
    required this.download,
    required this.upload,
  });
}

class ConnectionsSnapshot {
  final List<ConnectionTraffic> connections;
  final int coreDownload;
  final int coreUpload;

  const ConnectionsSnapshot({
    required this.connections,
    required this.coreDownload,
    required this.coreUpload,
  });
}

class TrafficSplitSource {
  TrafficSplitSource._();

  static HttpClient? _client;

  static HttpClient get _http =>
      _client ??= HttpClient()..connectionTimeout = const Duration(seconds: 2);

  // поле обнуляем до закрытия, иначе рекурсия через catch рвущихся запросов
  static void _reset() {
    final client = _client;
    _client = null;
    client?.close(force: true);
  }

  static Future<ConnectionsSnapshot?> fetch({
    required int port,
    required String secret,
  }) async {
    final poll = ConnectionsPollStats.instance.begin();
    var chars = 0;
    ConnectionsSnapshot? snapshot;
    try {
      final req = await _http
          .get('127.0.0.1', port, '/connections')
          .timeout(const Duration(seconds: 2));
      if (secret.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }
      final resp = await req.close().timeout(const Duration(seconds: 2));
      if (resp.statusCode != 200) {
        await resp.drain<void>();
        return null;
      }
      final body = await resp
          .transform(utf8.decoder)
          .join()
          .timeout(connectionsBodyTimeout);
      chars = body.length;
      return snapshot = parseSnapshot(body);
    } catch (_) {
      _reset();
      return null;
    } finally {
      ConnectionsPollStats.instance.end(
        poll,
        ok: snapshot != null,
        bodyChars: chars,
        connections: snapshot?.connections.length,
      );
    }
  }

  @visibleForTesting
  static ConnectionsSnapshot? parseSnapshot(String body) {
    final dynamic json = jsonDecode(body);
    if (json is! Map) return null;
    final raw = json['connections'];
    if (raw is! List) return null;

    final out = <ConnectionTraffic>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final id = item['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      // соединение звена цепочки везёт тот же трафик второй раз
      final meta = item['metadata'];
      if (meta is Map && meta['type'] == 'Inner') continue;
      final chains = item['chains'];
      out.add(ConnectionTraffic(
        id: id,
        chains: chains is List
            ? [for (final c in chains) c.toString()]
            : const <String>[],
        download: (item['download'] as num?)?.toInt() ?? 0,
        upload: (item['upload'] as num?)?.toInt() ?? 0,
      ));
    }
    return ConnectionsSnapshot(
      connections: out,
      coreDownload: (json['downloadTotal'] as num?)?.toInt() ?? 0,
      coreUpload: (json['uploadTotal'] as num?)?.toInt() ?? 0,
    );
  }
}

// DIRECT ищем по всей цепочке: с группами из yaml рядом стоит имя группы, а порядок у версий ядра разный
TrafficChannel channelOfChains(List<String> chains) {
  if (chains.isEmpty || chains.any(MihomoConfigGen.isChainHop)) {
    return TrafficChannel.unknown;
  }
  for (final raw in chains) {
    final tag = raw.trim().toUpperCase();
    if (tag == 'DIRECT') return TrafficChannel.direct;
    if (tag.startsWith('REJECT')) return TrafficChannel.blocked;
  }
  return TrafficChannel.vpn;
}

class TrafficSplitTracker {
  final Map<String, ConnectionTraffic> _prev = {};
  String? _session;
  bool _baselineTaken = false;

  // разница за время закрытого приложения идёт в объём, в скорость нет:
  // часы на один такт дали бы гигабайты в секунду
  bool _gapPending = false;
  int _vpnDown = 0;
  int _vpnUp = 0;
  int _directDown = 0;
  int _directUp = 0;

  TrafficSplit add(
    Iterable<ConnectionTraffic> connections, {
    required String session,
  }) {
    if (_session != session) {
      _session = session;
      _vpnDown = 0;
      _vpnUp = 0;
      _directDown = 0;
      _directUp = 0;
      reset();
    }

    var vpnDown = 0, vpnUp = 0, directDown = 0, directUp = 0;
    final seen = <String, ConnectionTraffic>{};

    for (final c in connections) {
      final channel = channelOfChains(c.chains);
      // без маршрута не запоминаем: иначе всё, что соединение унесло до цепочки, пропадёт
      if (channel == TrafficChannel.unknown) continue;
      seen[c.id] = c;
      if (!_baselineTaken) continue;

      final prev = _prev[c.id];
      // новое соединение отдаёт весь счётчик: короткие запросы живут меньше секунды
      final down = prev == null
          ? c.download
          : math.max(0, c.download - prev.download);
      final up = prev == null ? c.upload : math.max(0, c.upload - prev.upload);

      switch (channel) {
        case TrafficChannel.vpn:
          vpnDown += down;
          vpnUp += up;
        case TrafficChannel.direct:
          directDown += down;
          directUp += up;
        case TrafficChannel.blocked:
        case TrafficChannel.unknown:
          break;
      }
    }

    _prev
      ..clear()
      ..addAll(seen);
    // первый снимок только отметка, иначе весь объём сессии показался бы скоростью
    if (!_baselineTaken) {
      _baselineTaken = true;
      return _snapshot(0, 0, 0, 0);
    }
    _vpnDown += vpnDown;
    _vpnUp += vpnUp;
    _directDown += directDown;
    _directUp += directUp;
    if (_gapPending) {
      _gapPending = false;
      return _snapshot(0, 0, 0, 0);
    }
    return _snapshot(vpnDown, vpnUp, directDown, directUp);
  }

  TrafficSplitState? stateFor({
    required int coreDownload,
    required int coreUpload,
  }) {
    final session = _session;
    if (session == null) return null;
    return TrafficSplitState(
      session: session,
      coreDownload: coreDownload,
      coreUpload: coreUpload,
      vpnDownload: _vpnDown,
      vpnUpload: _vpnUp,
      directDownload: _directDown,
      directUpload: _directUp,
      connections: {
        for (final e in _prev.entries) e.key: (e.value.download, e.value.upload)
      },
    );
  }

  // звать вместо первого add, иначе add сочтёт счёт чужим и обнулит
  void restore(TrafficSplitState stored) {
    _session = stored.session;
    _vpnDown = stored.vpnDownload;
    _vpnUp = stored.vpnUpload;
    _directDown = stored.directDownload;
    _directUp = stored.directUpload;
    _prev
      ..clear()
      ..addEntries(stored.connections.entries.map(
        (e) => MapEntry(
          e.key,
          ConnectionTraffic(
            id: e.key,
            chains: const [],
            download: e.value.$1,
            upload: e.value.$2,
          ),
        ),
      ));
    _baselineTaken = true;
    _gapPending = true;
  }

  TrafficSplit _snapshot(int vpnDown, int vpnUp, int directDown, int directUp) =>
      TrafficSplit(
        vpn: ChannelTraffic(
          downloadSpeed: vpnDown,
          uploadSpeed: vpnUp,
          totalDownload: _vpnDown,
          totalUpload: _vpnUp,
        ),
        direct: ChannelTraffic(
          downloadSpeed: directDown,
          uploadSpeed: directUp,
          totalDownload: _directDown,
          totalUpload: _directUp,
        ),
      );

  void reset() {
    _prev.clear();
    _baselineTaken = false;
    _gapPending = false;
  }
}
