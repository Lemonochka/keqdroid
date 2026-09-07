/// Скорость трафика, разложенная по тому, куда ядро его отправило.
///
/// Существует ради одного вопроса: работает ли раздельная маршрутизация. Одна
/// общая цифра на него не отвечает — по ней не видно, ушло ли хоть что-то мимо
/// туннеля, и не видно обратного: что «прямые» правила молчат и в туннель
/// уезжает всё подряд.
///
/// Числа — байты за такт опроса, и такт секундный: ровно та же единица, что у
/// общей скорости в `VpnState`. Не «байты в секунду, посчитанные по настоящему
/// интервалу»: делить на реальный интервал было бы точнее, но тогда разбивка и
/// общая цифра под ней жили бы в разных единицах и переставали сходиться.
class TrafficSplit {
  /// То, что ядро отправило в туннель.
  final int vpnDownload;
  final int vpnUpload;

  /// То, что ядро увело мимо туннеля своими правилами Direct.
  ///
  /// Это НЕ «весь трафик мимо VPN»: приложения, исключённые из туннеля
  /// раздельным туннелированием, до ядра вообще не доходят и здесь не видны.
  final int directDownload;
  final int directUpload;

  const TrafficSplit({
    required this.vpnDownload,
    required this.vpnUpload,
    required this.directDownload,
    required this.directUpload,
  });

  /// Источник есть, но разницы между снимками ещё нет — первый такт сессии.
  ///
  /// Отдельное значение, а не `null`: `null` означает «ядро разбивку не
  /// отдаёт» и переключает полосу на однострочный вид. Показать его на одном
  /// такте — значит дёрнуть высотой шапки на ровном месте.
  static const zero = TrafficSplit(
    vpnDownload: 0,
    vpnUpload: 0,
    directDownload: 0,
    directUpload: 0,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrafficSplit &&
          vpnDownload == other.vpnDownload &&
          vpnUpload == other.vpnUpload &&
          directDownload == other.directDownload &&
          directUpload == other.directUpload;

  @override
  int get hashCode =>
      Object.hash(vpnDownload, vpnUpload, directDownload, directUpload);

  @override
  String toString() => 'TrafficSplit(vpn: $vpnDownload/$vpnUpload, '
      'direct: $directDownload/$directUpload)';
}
