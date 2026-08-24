import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'connection_mode.dart';
import 'tunnel_state.dart';

/// Счётчики трафика десктопных бэкендов: секундный опрос, тоталы, скорости.
///
/// Windows и Linux вели этот код двумя дословными копиями — вместе с
/// комментариями. Каждое общее изменение приходилось вносить дважды, и забытая
/// вторая копия ничем себя не выдавала: расхождение всплывало только на другой
/// ОС, которую разработчик в этот момент обычно не запускает.
///
/// Сюда переехало только то, что у обеих ОС совпадало посимвольно. Всё, что
/// отличается по делу, осталось в бэкендах и объявлено здесь абстрактным:
/// источники счётчиков разные (sysfs tun / MethodChannel / clash_api /
/// wireproxy), и порядок их перебора тоже.
///
/// Состояние ниже помечено [protected] и объявлено без подчёркивания намеренно:
/// [pollTrafficStats] живёт в бэкендах, то есть в других библиотеках, а
/// приватные члены mixin'а видны только внутри его собственной. Публичность
/// здесь — цена совместного состояния, а не приглашение трогать эти поля извне.
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

  /// false = окно скрыто (трей/свёрнуто): секундный опрос счётчиков приостановлен.
  @protected
  bool statsPollingEnabled = true;

  /// Базовая отметка счётчиков снята. Отдельный флаг, а не «prev == 0»:
  /// 0 — легитимное значение на старте сессии, и с паузой опроса такое
  /// кодирование теряло бы весь скрытый период из тоталов.
  @protected
  bool statsBaselineTaken = false;

  /// Первый опрос после паузы: скрытый период целиком попадает в тоталы, но как
  /// «скорость» его не показываем — иначе на секунду вспыхивает гигантское значение.
  @protected
  bool resumeBaselinePending = false;

  /// Один keep-alive клиент на сессию вместо нового HttpClient (сокет+закрытие)
  /// на каждый секундный опрос clash_api/wireproxy.
  HttpClient? _statsHttpClient;

  @protected
  HttpClient get statsHttp =>
      _statsHttpClient ??= HttpClient()
        ..connectionTimeout = const Duration(seconds: 2);

  /// Отдать состояние наружу. У каждого бэкенда свой контроллер потока.
  @protected
  void emit(VpnState state);

  /// Режим текущей сессии, либо null если сессии нет. Живёт в бэкендах вместе с
  /// остальным лайфсайклом — сюда нужен только чтобы возобновить опрос после
  /// разворачивания окна.
  @protected
  ConnectionMode? get activeMode;

  /// Снять счётчики. Источники и порядок их перебора у Windows и Linux разные —
  /// это и есть причина, по которой метод не переехал сюда.
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
      // Окно скрыто (сессия из хоткея/автостарта в трее): цикл не заводим, но
      // снимаем базовую отметку счётчиков — иначе трафик скрытого периода не
      // попал бы в тоталы при возобновлении опроса.
      unawaited(takeHiddenBaseline(mode));
    }
  }

  Future<void> takeHiddenBaseline(ConnectionMode mode) async {
    final startedAt = sessionStartedAt;
    for (var i = 0; i < 5; i++) {
      // Сессия сменилась/остановилась, опрос возобновился или база уже снята —
      // дальше не наше дело.
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
      unawaited(pollTrafficStats(mode));
    });
    unawaited(pollTrafficStats(mode));
  }

  void setTrafficStatsPollingEnabled(bool enabled) {
    if (statsPollingEnabled == enabled) return;
    statsPollingEnabled = enabled;
    if (!enabled) {
      // Только глушим таймер; сессионные поля (тоталы, started) не трогаем —
      // при возобновлении кумулятивные счётчики ядра дадут корректные тоталы.
      statsTimer?.cancel();
      statsTimer = null;
      _statsHttpClient?.close(force: true);
      _statsHttpClient = null;
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
    _statsHttpClient?.close(force: true);
    _statsHttpClient = null;
  }

  void resetStatsHttp() {
    _statsHttpClient?.close(force: true);
    _statsHttpClient = null;
  }

  Future<({int rx, int tx})?> queryWireproxyMetrics(int port) async {
    try {
      final req = await statsHttp
          .get('127.0.0.1', port, '/metrics')
          .timeout(const Duration(seconds: 2));
      final resp = await req.close().timeout(const Duration(seconds: 2));
      if (resp.statusCode != 200) {
        await resp.drain<void>();
        return null;
      }
      final body = await resp.transform(utf8.decoder).join();
      var rx = 0;
      var tx = 0;
      for (final line in const LineSplitter().convert(body)) {
        final i = line.indexOf('=');
        if (i < 0) continue;
        final key = line.substring(0, i).trim();
        final value = int.tryParse(line.substring(i + 1).trim());
        if (value == null) continue;
        if (key == 'rx_bytes') {
          rx += value;
        } else if (key == 'tx_bytes') {
          tx += value;
        }
      }
      return (rx: rx, tx: tx);
    } catch (_) {
      resetStatsHttp();
      return null;
    }
  }

  /// [secret] — токен RESTful API. У keqrnel его нет (API слушает петлю), у
  /// mihomo он обязателен: без заголовка ядро отвечает 401, и счётчики молча
  /// остаются нулями.
  Future<({int down, int up})?> queryClashTraffic(
    int port, {
    String secret = '',
  }) async {
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
      final body = await resp.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final down = (json['downloadTotal'] as num?)?.toInt() ?? 0;
      final up = (json['uploadTotal'] as num?)?.toInt() ?? 0;
      return (down: down, up: up);
    } catch (_) {
      resetStatsHttp();
      return null;
    }
  }

  void emitConnectedTelemetry(
    ConnectionMode? mode, {
    int? downloadSpeed,
    int? uploadSpeed,
  }) {
    emit(buildConnectedState(
      mode,
      downloadSpeed: downloadSpeed,
      uploadSpeed: uploadSpeed,
    ));
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
