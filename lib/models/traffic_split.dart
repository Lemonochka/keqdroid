/// Показатели одного канала: скорость сейчас и объём с начала сессии.
class ChannelTraffic {
  /// Байты за такт опроса, и такт секундный: ровно та же единица, что у общей
  /// скорости в `VpnState`. Не «байты в секунду по настоящему интервалу»:
  /// делить на реальный интервал было бы точнее, но тогда разбивка и общая
  /// цифра говорили бы на разных языках.
  final int downloadSpeed;
  final int uploadSpeed;

  /// Прошло по этому каналу за сессию, в обе стороны.
  ///
  /// Обе стороны вместе, хотя чип общего объёма показывал только принятое:
  /// вопрос к этой полосе — «сколько ушло ЭТИМ маршрутом», и на прогоне
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
  /// Это НЕ «весь трафик мимо VPN»: приложения, исключённые из туннеля
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
