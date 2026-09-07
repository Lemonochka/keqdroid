import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/traffic_split.dart';

/// Куда ядро отправило соединение.
enum TrafficChannel {
  /// В туннель — то есть в прокси, каким бы длинным ни была цепочка.
  vpn,

  /// Мимо туннеля, правилом Direct.
  direct,

  /// Отброшено правилом. В разбивку не идёт: байт по такому соединению нет,
  /// а третья строка в полосе ради постоянного нуля — только шум.
  blocked,

  /// Цепочка пустая: ядро ещё не решило, куда отправить. Не приписываем ни
  /// одной стороне — выдумывать здесь хуже, чем недосчитать.
  unknown,
}

/// Счётчики одного соединения из ответа `/connections`.
///
/// `download`/`upload` у mihomo накопительные — за всю жизнь соединения, а не
/// за интервал опроса.
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

/// Ответ `/connections` целиком.
///
/// Кроме списка соединений ядро отдаёт свои общие суммы — накопительные с его
/// старта и только растущие. Разложить их по каналам нечем, и полоса их не
/// показывает; нужны они ради одного: по ним видно, то же это ядро или уже
/// перезапущенное (см. [TrafficSplitState.belongsTo]).
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

/// Разбивка живёт только там, где ядро само ведёт список соединений и пишет
/// против каждого, куда оно ушло. Это mihomo и его RESTful API.
///
/// Остальные пути дают только общую сумму, и это не недоделка, а устройство:
/// на Android скорость снимается с системного счётчика приложения (он не знает
/// про маршруты), в TUN на десктопе — со счётчиков адаптера (в адаптер входит
/// всё), а в связке sing-box + вшитый xray API честно отвечает «ушло в proxy»
/// про весь трафик, потому что sing-box отдаёт движку всё целиком и настоящее
/// решение принимается слоем ниже. Там разбивку взять негде — и полоса
/// показывает обычные общие цифры.
class TrafficSplitSource {
  TrafficSplitSource._();

  static HttpClient? _client;

  static HttpClient get _http =>
      _client ??= HttpClient()..connectionTimeout = const Duration(seconds: 2);

  static void _reset() {
    _client?.close(force: true);
    _client = null;
  }

  /// Снимок счётчиков всех живых соединений. `null` — API не ответил.
  static Future<ConnectionsSnapshot?> fetch({
    required int port,
    required String secret,
  }) async {
    try {
      final req = await _http
          .get('127.0.0.1', port, '/connections')
          .timeout(const Duration(seconds: 2));
      if (secret.isNotEmpty) {
        // Схема из `hub/route/server.go`: заголовок ровно `Bearer <secret>`,
        // всё остальное — 401 и вечные нули на экране.
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }
      final resp = await req.close().timeout(const Duration(seconds: 2));
      if (resp.statusCode != 200) {
        await resp.drain<void>();
        return null;
      }
      return parseSnapshot(await resp.transform(utf8.decoder).join());
    } catch (_) {
      _reset();
      return null;
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

/// Куда ушло соединение с такой цепочкой аутбаундов.
///
/// Ищем по всей цепочке, а не по её концу: у голого конфига в ней ровно один
/// элемент, но пользовательский yaml вправе завести группы, и тогда рядом с
/// `DIRECT` в цепочке стоит имя группы. Порядок элементов при этом у разных
/// версий ядра разный — а `DIRECT` в цепочке означает «ушло мимо туннеля» при
/// любом порядке.
TrafficChannel channelOfChains(List<String> chains) {
  if (chains.isEmpty) return TrafficChannel.unknown;
  for (final raw in chains) {
    final tag = raw.trim().toUpperCase();
    if (tag == 'DIRECT') return TrafficChannel.direct;
    // REJECT, REJECT-DROP.
    if (tag.startsWith('REJECT')) return TrafficChannel.blocked;
  }
  return TrafficChannel.vpn;
}

/// Превращает накопительные счётчики соединений в показатели каналов.
///
/// Считает по разнице двух снимков, потому что своих «скоростей» ядро не
/// отдаёт вовсе — только сколько всего набежало по каждому соединению.
///
/// Объём канала — сумма этих разниц за сессию, и он чуть занижен: соединение,
/// закрывшееся между опросами, недодаёт то, что успело унести после
/// последнего снимка, а совсем короткое может целиком уместиться между двумя
/// снимками и не попасть в счёт вовсе. Общий объём ядро отдаёт точной цифрой,
/// но одной на всё — разложить её по каналам нечем, а показывать точный общий
/// рядом с двумя измеренными значило бы поставить в полосу три числа, которые
/// не сходятся.
///
/// Отсюда же требование к вызывающему: опрашивать НЕПРЕРЫВНО, пока держится
/// сессия. Каждая пауза — дыра в объёме, и закрыть её потом можно лишь
/// наполовину: у соединений, переживших паузу, счётчики так и лежат в ядре
/// накопленными (на этом стоит [restore] после перезапуска приложения), а от
/// закрывшихся не осталось ничего.
class TrafficSplitTracker {
  final Map<String, ConnectionTraffic> _prev = {};
  String? _session;
  bool _baselineTaken = false;

  /// Следующая разница накрывает всё время, пока приложение было закрыто.
  /// В объём она идёт, в скорость — нет: часы, поделённые на один такт, дали
  /// бы в полосе гигабайты в секунду.
  bool _gapPending = false;
  int _vpnDown = 0;
  int _vpnUp = 0;
  int _directDown = 0;
  int _directUp = 0;

  /// Показатели каналов по снимку счётчиков.
  ///
  /// [session] — метка сессии ядра. Другая сессия означает другой набор
  /// идентификаторов, и старые счётчики к ним отношения не имеют.
  TrafficSplit add(
    Iterable<ConnectionTraffic> connections, {
    required String session,
  }) {
    if (_session != session) {
      _session = session;
      // Объём копится за сессию: у новой он начинается с нуля, как и у чипа
      // общего объёма рядом.
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
      // Соединение, которому ядро ещё не назначило маршрут, не запоминаем
      // вовсе: запомнив, мы приняли бы его счётчик за уже учтённый, и всё,
      // что оно унесло до появления цепочки, пропало бы из разбивки.
      if (channel == TrafficChannel.unknown) continue;
      seen[c.id] = c;
      if (!_baselineTaken) continue;

      final prev = _prev[c.id];
      // Соединения, которого на прошлом снимке не было, родилось внутри
      // интервала — весь его счётчик и есть трафик за этот интервал.
      // Отбрасывать его нельзя: короткие запросы (тот же DNS-over-HTTPS)
      // живут меньше секунды и иначе не попали бы в разбивку никогда.
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
    // Первый снимок — только отметка. Счётчики в нём накоплены до того, как мы
    // начали смотреть, и приняв их за разницу, полоса на одном такте показала
    // бы всё, что скачалось за сессию, как «скорость».
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

  /// Счёт для хранилища. `null` — сессии ещё не было, писать нечего.
  ///
  /// Общие суммы ядра идут из того же ответа `/connections`, что и последний
  /// [add]: только вместе с ними по записи видно, что ядро с тех пор не
  /// перезапускалось.
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

  /// Продолжить счёт, начатый прошлым запуском приложения.
  ///
  /// Зовётся вместо первого [add] — то есть до него и по той же сессии, иначе
  /// [add] сочтёт счёт чужим и обнулит его. Восстановленные счётчики
  /// соединений заменяют собой базовую отметку: соединение, пережившее
  /// закрытие приложения, отдаст в объём всё, что унесло за это время, а не с
  /// момента, когда мы снова начали смотреть.
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
            // Куда ушло соединение, спрашиваем у свежего снимка: цепочка в
            // ядре дописывается по ходу, и вчерашняя была бы хуже сегодняшней.
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

  /// Забыть базовую отметку: следующий снимок станет новой.
  ///
  /// Накопленный объём при этом сохраняется — он про сессию ядра, а не про
  /// опрос. Опрос не прерывается вовсе, пока держится подключение: разница со
  /// снимком получасовой давности схлопнула бы полчаса в одну секунду, а
  /// пропущенное за эти полчаса всё равно не вернулось бы — счётчики
  /// закрывшихся соединений ядро не хранит.
  void reset() {
    _prev.clear();
    _baselineTaken = false;
    // Прошлого снимка больше нет — и разницы, которую надо было спрятать от
    // строки скорости, тоже.
    _gapPending = false;
  }
}
