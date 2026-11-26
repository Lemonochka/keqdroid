import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/app_logger.dart';
import '../core/connections_poll_stats.dart';
import 'connection_mode.dart';
import 'tunnel_state.dart';
import 'xray_desktop_config.dart';

// без подчёркивания намеренно: pollTrafficStats живёт в бэкендах,
// а приватное у mixin видно только в своей библиотеке
mixin DesktopTrafficStats {
  @protected
  Timer? statsTimer;
  @protected
  DateTime? sessionStartedAt;
  @protected
  int prevInOctets = 0;
  @protected
  int prevOutOctets = 0;
  @protected
  int totalDownload = 0;
  @protected
  int totalUpload = 0;

  @protected
  bool statsPollingEnabled = true;

  // отдельный флаг: 0 законное значение на старте, и с паузой опроса терялся бы скрытый период
  @protected
  bool statsBaselineTaken = false;

  @protected
  bool resumeBaselinePending = false;

  HttpClient? _statsHttpClient;

  @protected
  HttpClient get statsHttp =>
      _statsHttpClient ??= HttpClient()
        ..connectionTimeout = const Duration(seconds: 2);

  @protected
  void emit(VpnState state);

  @protected
  ConnectionMode? get activeMode;

  @protected
  Future<void> pollTrafficStats(ConnectionMode mode, {bool force = false});

  void startStatsLoop(ConnectionMode mode) {
    stopStatsLoop();
    sessionStartedAt = DateTime.now();
    prevInOctets = 0;
    prevOutOctets = 0;
    totalDownload = 0;
    totalUpload = 0;
    statsBaselineTaken = false;
    if (statsPollingEnabled) {
      startStatsTimer(mode);
    } else {
      // окно скрыто: цикл не заводим, но базу снимаем, иначе скрытый период не попадёт в тоталы
      unawaited(takeHiddenBaseline(mode));
    }
  }

  Future<void> takeHiddenBaseline(ConnectionMode mode) async {
    final startedAt = sessionStartedAt;
    for (var i = 0; i < 5; i++) {
      if (!identical(sessionStartedAt, startedAt) ||
          statsPollingEnabled ||
          statsBaselineTaken) {
        return;
      }
      await pollTrafficStats(mode, force: true);
      if (statsBaselineTaken) return;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  void startStatsTimer(ConnectionMode mode) {
    statsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_pollStatsOnce(mode));
    });
    unawaited(_pollStatsOnce(mode));
  }

  bool _statsPollInFlight = false;

  // прошлый опрос в пути: второй вдогонку растил очередь к медленному ядру
  Future<void> _pollStatsOnce(ConnectionMode mode) async {
    if (_statsPollInFlight) return;
    _statsPollInFlight = true;
    try {
      await pollTrafficStats(mode);
    } finally {
      _statsPollInFlight = false;
    }
  }

  void setTrafficStatsPollingEnabled(bool enabled, {String? reason}) {
    if (statsPollingEnabled == enabled) return;
    statsPollingEnabled = enabled;
    final detail = reason ?? (enabled ? 'window shown' : 'window hidden');
    AppLogger.instance.info(
      'traffic polling ${enabled ? 'resumed' : 'paused'}: $detail',
    );
    if (!enabled) {
      statsTimer?.cancel();
      statsTimer = null;
      resetStatsHttp();
      return;
    }
    final mode = activeMode;
    if (mode != null && sessionStartedAt != null && statsTimer == null) {
      resumeBaselinePending = true;
      startStatsTimer(mode);
    }
  }

  void stopStatsLoop() {
    statsTimer?.cancel();
    statsTimer = null;
    sessionStartedAt = null;
    prevInOctets = 0;
    prevOutOctets = 0;
    totalDownload = 0;
    totalUpload = 0;
    resumeBaselinePending = false;
    statsBaselineTaken = false;
    resetStatsHttp();
  }

  // сначала отцепляем, потом закрываем: каждый оборванный запрос зовёт сброс,
  // и пока поле указывает на закрываемый клиент, это рекурсия до переполнения стека
  void resetStatsHttp() {
    final client = _statsHttpClient;
    _statsHttpClient = null;
    client?.close(force: true);
  }

  Future<({int down, int up})?> queryXrayTraffic(int port) async {
    final poll = ConnectionsPollStats.instance.begin();
    var ok = false;
    var chars = 0;
    try {
      final req = await statsHttp
          .get('127.0.0.1', port, '/debug/vars')
          .timeout(const Duration(seconds: 2));
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
      final totals = xrayInboundTotals(
        jsonDecode(body) as Map<String, dynamic>,
      );
      ok = true;
      return totals;
    } catch (_) {
      resetStatsHttp();
      return null;
    } finally {
      ConnectionsPollStats.instance.end(poll, ok: ok, bodyChars: chars);
    }
  }

  // у mihomo токен обязателен: без него 401, и счётчики молча нули
  Future<({int down, int up})?> queryClashTraffic(
    int port, {
    String secret = '',
  }) async {
    final poll = ConnectionsPollStats.instance.begin();
    var ok = false;
    var chars = 0;
    int? connections;
    try {
      final req = await statsHttp
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
      final json = jsonDecode(body) as Map<String, dynamic>;
      connections = (json['connections'] as List?)?.length;
      final down = (json['downloadTotal'] as num?)?.toInt() ?? 0;
      final up = (json['uploadTotal'] as num?)?.toInt() ?? 0;
      ok = true;
      return (down: down, up: up);
    } catch (_) {
      resetStatsHttp();
      return null;
    } finally {
      ConnectionsPollStats.instance.end(
        poll,
        ok: ok,
        bodyChars: chars,
        connections: connections,
      );
    }
  }

  void emitConnectedTelemetry(
    ConnectionMode? mode, {
    int? downloadSpeed,
    int? uploadSpeed,
  }) {
    emit(
      buildConnectedState(
        mode,
        downloadSpeed: downloadSpeed,
        uploadSpeed: uploadSpeed,
      ),
    );
  }

  VpnState buildConnectedState(
    ConnectionMode? mode, {
    int? downloadSpeed,
    int? uploadSpeed,
  }) {
    final started = sessionStartedAt;
    return VpnState(
      status: VpnStatus.connected,
      activeMode: mode,
      downloadSpeed: downloadSpeed,
      uploadSpeed: uploadSpeed,
      totalDownload: totalDownload > 0 ? totalDownload : null,
      totalUpload: totalUpload > 0 ? totalUpload : null,
      duration: started != null ? DateTime.now().difference(started) : null,
    );
  }
}
