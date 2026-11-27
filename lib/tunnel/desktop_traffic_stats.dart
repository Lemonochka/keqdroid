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
  _ClashTrafficFeed? _activeClashFeed;
  final _liveClashFeeds = <_ClashTrafficFeed>{};

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
    final feeds = _liveClashFeeds.toList();
    _statsHttpClient = null;
    _activeClashFeed = null;
    _liveClashFeeds.clear();
    for (final feed in feeds) {
      feed.close();
    }
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

  // /traffic шлёт по 60 байт раз в секунду вместо полного списка /connections; токен обязателен
  Future<({int down, int up})?> queryClashTraffic(
    int port, {
    String secret = '',
  }) async {
    final poll = ConnectionsPollStats.instance.begin();
    var ok = false;
    var chars = 0;
    try {
      var feed = _activeClashFeed;
      if (feed == null ||
          feed.isClosed ||
          feed.port != port ||
          feed.secret != secret) {
        feed = _ClashTrafficFeed(
          port,
          secret,
          onDone: (self) {
            _liveClashFeeds.remove(self);
            if (identical(_activeClashFeed, self)) _activeClashFeed = null;
          },
        );
        _activeClashFeed = feed;
        _liveClashFeeds.add(feed);
      }
      final sample = await feed.next(() => statsHttp, connectionsBodyTimeout);
      if (sample == null) {
        resetStatsHttp();
        return null;
      }
      chars = sample.chars;
      ok = true;
      return (down: sample.down, up: sample.up);
    } catch (_) {
      resetStatsHttp();
      return null;
    } finally {
      if (!statsPollingEnabled) resetStatsHttp();
      ConnectionsPollStats.instance.end(poll, ok: ok, bodyChars: chars);
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

typedef _ClashTrafficSample = ({int down, int up, int chars});

class _ClashTrafficFeed {
  _ClashTrafficFeed(this.port, this.secret, {required this.onDone});

  final int port;
  final String secret;
  final void Function(_ClashTrafficFeed self) onDone;

  StreamSubscription<String>? _sub;
  _ClashTrafficSample? _unread;
  final _waiters = <Completer<_ClashTrafficSample?>>[];
  bool _closed = false;
  Future<void>? _opening;

  bool get isClosed => _closed;

  Future<_ClashTrafficSample?> next(
    HttpClient Function() client,
    Duration bodyTimeout,
  ) async {
    if (_closed) return null;
    final buffered = _unread;
    if (buffered != null) {
      _unread = null;
      return buffered;
    }
    final waiter = Completer<_ClashTrafficSample?>();
    _waiters.add(waiter);
    _opening ??= _open(client);
    try {
      return await waiter.future.timeout(bodyTimeout);
    } on TimeoutException {
      _waiters.remove(waiter);
      rethrow;
    }
  }

  Future<void> _open(HttpClient Function() client) async {
    try {
      final req = await client()
          .get('127.0.0.1', port, '/traffic')
          .timeout(const Duration(seconds: 2));
      if (secret.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }
      final resp = await req.close().timeout(const Duration(seconds: 2));
      if (_closed) {
        unawaited(resp.drain<void>().catchError((_) {}));
        return;
      }
      if (resp.statusCode != 200) {
        await resp.drain<void>();
        close();
        return;
      }
      _sub = resp
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            _onLine,
            onError: (_) => close(),
            onDone: close,
            cancelOnError: true,
          );
    } catch (_) {
      close();
    }
  }

  void _onLine(String line) {
    if (_closed || line.trim().isEmpty) return;
    try {
      final json = jsonDecode(line) as Map<String, dynamic>;
      final down =
          ((json['downTotal'] ?? json['downloadTotal']) as num?)?.toInt() ?? 0;
      final up =
          ((json['upTotal'] ?? json['uploadTotal']) as num?)?.toInt() ?? 0;
      final sample = (down: down, up: up, chars: line.length);
      if (_waiters.isEmpty) {
        _unread = sample;
        return;
      }
      final pending = _waiters.toList();
      _waiters.clear();
      for (final w in pending) {
        if (!w.isCompleted) w.complete(sample);
      }
    } catch (_) {
      close();
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _unread = null;
    final sub = _sub;
    _sub = null;
    if (sub != null) unawaited(sub.cancel().catchError((_) {}));
    final pending = _waiters.toList();
    _waiters.clear();
    for (final w in pending) {
      if (!w.isCompleted) w.complete(null);
    }
    onDone(this);
  }
}
