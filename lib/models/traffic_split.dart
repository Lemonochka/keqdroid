/// Показатели одного канала: скорость сейчас и объём с начала сессии.
class ChannelTraffic {
  /// Байты за такт опроса, и такт секундный: та же единица, что у общей
  /// скорости в `VpnState`. Не «байты в секунду по настоящему интервалу»:
  /// делить на реальный интервал было бы точнее, но тогда разбивка и общая
  /// цифра говорили бы на разных языках.
  final int downloadSpeed;
  final int uploadSpeed;

  /// Прошло по этому каналу за сессию, в обе стороны.
  ///
  /// Обе стороны вместе, хотя чип общего объёма показывал только принятое:
  /// вопрос к этой полосе — «сколько ушло этим маршрутом», и на прогоне
  /// отдачи (тот же спидтест) счётчик одного приёма стоит на месте, из чего
  /// читается, что маршрут не работает.
  final int totalDownload;
  final int totalUpload;

  int get total => totalDownload + totalUpload;

  const ChannelTraffic({
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.totalDownload,
    required this.totalUpload,
  });

  static const zero = ChannelTraffic(
    downloadSpeed: 0,
    uploadSpeed: 0,
    totalDownload: 0,
    totalUpload: 0,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChannelTraffic &&
          downloadSpeed == other.downloadSpeed &&
          uploadSpeed == other.uploadSpeed &&
          totalDownload == other.totalDownload &&
          totalUpload == other.totalUpload;

  @override
  int get hashCode =>
      Object.hash(downloadSpeed, uploadSpeed, totalDownload, totalUpload);

  @override
  String toString() =>
      'ChannelTraffic(${downloadSpeed}B/s down, ${uploadSpeed}B/s up, '
      '$total B total)';
}

/// Трафик, разложенный по тому, куда его отправило ядро.
///
/// Существует ради одного вопроса: работает ли раздельная маршрутизация. Одна
/// общая цифра на него не отвечает — по ней не видно, ушло ли хоть что-то мимо
/// туннеля, и не видно обратного: что «прямые» правила молчат и в туннель
/// уезжает всё подряд.
class TrafficSplit {
  /// То, что ядро отправило в туннель.
  final ChannelTraffic vpn;

  /// То, что ядро увело мимо туннеля своими правилами Direct.
  ///
  /// Это не «весь трафик мимо VPN»: приложения, исключённые из туннеля
  /// раздельным туннелированием, до ядра вообще не доходят и здесь не видны.
  final ChannelTraffic direct;

  const TrafficSplit({required this.vpn, required this.direct});

  /// Источник есть, но разницы между снимками ещё нет — первый такт сессии.
  ///
  /// Отдельное значение, а не `null`: `null` означает «ядро разбивку не
  /// отдаёт» и переключает полосу на общие цифры. Показать его на одном такте
  /// — значит дёрнуть высотой шапки на ровном месте.
  static const zero = TrafficSplit(
    vpn: ChannelTraffic.zero,
    direct: ChannelTraffic.zero,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrafficSplit && vpn == other.vpn && direct == other.direct;

  @override
  int get hashCode => Object.hash(vpn, direct);

  @override
  String toString() => 'TrafficSplit(vpn: $vpn, direct: $direct)';
}

/// Счёт разбивки, снятый с трекера, чтобы пережить перезапуск приложения.
///
/// На Android ядро живёт своим процессом и переживает уничтожение
/// Flutter-движка: приложение смахнули из недавних — туннель работает дальше,
/// а весь Dart вместе с накопленным объёмом начинается заново. Общий чип рядом
/// этого не замечает (его цифру ведёт нативный сервис), а разбивка обнулялась
/// на каждое такое закрытие.
class TrafficSplitState {
  /// Метка сессии ядра: чужой счёт подхватывать нельзя.
  final String session;

  /// Общие суммы ядра на момент записи.
  ///
  /// Ядро считает их со своего старта и только вверх, поэтому цифра меньше
  /// сохранённой означает, что ядро с тех пор перезапускалось. Это
  /// единственная защита от реконнекта из плитки: он поднимает ядро на том же
  /// конфиге, то есть с тем же портом и токеном, и метка сессии совпадает.
  final int coreDownload;
  final int coreUpload;

  final int vpnDownload;
  final int vpnUpload;
  final int directDownload;
  final int directUpload;

  /// Счётчики живых соединений на момент записи: id → (принято, отдано).
  ///
  /// Без них весь трафик, прошедший по этим соединениям до записи, посчитался
  /// бы заново: счётчики у ядра накопительные за жизнь соединения. С ними всё
  /// наоборот — при восстановлении в объём попадает и то, что эти соединения
  /// унесли, пока приложение было закрыто.
  final Map<String, (int, int)> connections;

  const TrafficSplitState({
    required this.session,
    required this.coreDownload,
    required this.coreUpload,
    required this.vpnDownload,
    required this.vpnUpload,
    required this.directDownload,
    required this.directUpload,
    required this.connections,
  });

  /// Относится ли сохранённый счёт к идущей сейчас сессии ядра.
  bool belongsTo({
    required String session,
    required int coreDownload,
    required int coreUpload,
  }) =>
      this.session == session &&
      coreDownload >= this.coreDownload &&
      coreUpload >= this.coreUpload;

  Map<String, Object?> toJson() => {
        'v': 1,
        'session': session,
        'core': [coreDownload, coreUpload],
        'vpn': [vpnDownload, vpnUpload],
        'direct': [directDownload, directUpload],
        'conns': {
          for (final e in connections.entries) e.key: [e.value.$1, e.value.$2],
        },
      };

  /// Разбор записи. `null` — файл не от этой версии формата или порван.
  ///
  /// Порванная запись здесь не исключение, а рядовой случай: файл пишется на
  /// живом туннеле, и процесс могут убить в любой момент. Счёт начнётся с
  /// нуля — то, что было до появления файла.
  static TrafficSplitState? fromJson(Object? json) {
    if (json is! Map) return null;
    if (json['v'] != 1) return null;
    final session = json['session'];
    if (session is! String || session.isEmpty) return null;

    (int, int)? pair(Object? raw) {
      if (raw is! List || raw.length != 2) return null;
      final a = raw[0], b = raw[1];
      if (a is! num || b is! num) return null;
      return (a.toInt(), b.toInt());
    }

    final core = pair(json['core']);
    final vpn = pair(json['vpn']);
    final direct = pair(json['direct']);
    if (core == null || vpn == null || direct == null) return null;

    final rawConns = json['conns'];
    if (rawConns is! Map) return null;
    final conns = <String, (int, int)>{};
    for (final e in rawConns.entries) {
      final counters = pair(e.value);
      if (counters == null) return null;
      conns[e.key.toString()] = counters;
    }

    return TrafficSplitState(
      session: session,
      coreDownload: core.$1,
      coreUpload: core.$2,
      vpnDownload: vpn.$1,
      vpnUpload: vpn.$2,
      directDownload: direct.$1,
      directUpload: direct.$2,
      connections: conns,
    );
  }
}
