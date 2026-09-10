/// Разобранная ссылка Mieru (`mierus://`, со «s» на конце — так в формате).
///
/// Особенность, из-за которой у неё отдельный файл: одна ссылка описывает
/// **несколько** серверов. Порт и транспорт приходят парами повторяющихся
/// параметров (`?port=2999&protocol=TCP&port=3000&protocol=UDP`), и ядро делает
/// из такой ссылки несколько прокси. У нас «одна ссылка — один сервер», поэтому
/// на импорте она раскладывается — см. [expand].
///
/// Разбор сверен с `common/convert/converter.go` mihomo.
class MieruLink {
  const MieruLink({
    required this.host,
    required this.username,
    required this.password,
    required this.port,
    required this.portRange,
    required this.transport,
    required this.multiplexing,
    required this.handshakeMode,
    required this.trafficPattern,
  });

  final String host;
  final String username;
  final String password;

  /// Один порт; пусто — значит порт задан диапазоном.
  final int? port;

  /// Диапазон портов (`20000-20050`) — у ядра под него своё поле.
  final String portRange;

  /// `transport` у ядра: TCP или UDP. В ссылке зовётся `protocol`.
  final String transport;

  final String multiplexing;
  final String handshakeMode;
  final String trafficPattern;

  static bool looksLikeUri(String config) =>
      config.trimLeft().toLowerCase().startsWith('mierus://');

  /// Ссылка с одной парой порт/транспорт. Ссылку с несколькими сюда не
  /// передают — её сначала разбирает [expand].
  static MieruLink? tryParse(String link) {
    if (!looksLikeUri(link)) return null;
    final Uri uri;
    try {
      uri = Uri.parse(link.trim());
    } catch (_) {
      return null;
    }
    if (uri.host.isEmpty) return null;

    final ports = uri.queryParametersAll['port'] ?? const [];
    final protocols = uri.queryParametersAll['protocol'] ?? const [];
    if (ports.isEmpty || ports.length != protocols.length) return null;

    final port = ports.first.trim();
    final userInfo = uri.userInfo;
    final split = userInfo.indexOf(':');
    String param(String key) => (uri.queryParameters[key] ?? '').trim();

    return MieruLink(
      host: uri.host,
      username: Uri.decodeComponent(
        split >= 0 ? userInfo.substring(0, split) : userInfo,
      ),
      password:
          split >= 0 ? Uri.decodeComponent(userInfo.substring(split + 1)) : '',
      port: port.contains('-') ? null : int.tryParse(port),
      portRange: port.contains('-') ? port : '',
      transport: protocols.first.trim(),
      multiplexing: param('multiplexing'),
      handshakeMode: param('handshake-mode'),
      trafficPattern: param('traffic-pattern'),
    );
  }

  /// Ссылка на каждый порт, который она описывает.
  ///
  /// Не mieru, одна пара или ссылка, которую не удалось прочесть, — вернётся
  /// она сама: решать про такую не здесь, о неполной паре скажет генератор.
  ///
  /// Имя узла собирается как у ядра — `имя:порт/транспорт`, — иначе в списке
  /// оказалось бы несколько серверов с одним именем и различить их было бы
  /// нечем.
  static List<String> expand(String link) {
    if (!looksLikeUri(link)) return [link];
    final Uri uri;
    try {
      uri = Uri.parse(link.trim());
    } catch (_) {
      return [link];
    }
    final ports = uri.queryParametersAll['port'] ?? const [];
    final protocols = uri.queryParametersAll['protocol'] ?? const [];
    if (ports.length < 2 || ports.length != protocols.length) return [link];

    var baseName = uri.fragment.trim();
    if (baseName.isEmpty) baseName = (uri.queryParameters['profile'] ?? '').trim();
    if (baseName.isEmpty) baseName = uri.host;

    final rest = Map<String, String>.from(uri.queryParameters)
      ..remove('port')
      ..remove('protocol');

    return [
      for (var i = 0; i < ports.length; i++)
        Uri(
          scheme: uri.scheme,
          userInfo: uri.userInfo,
          host: uri.host,
          queryParameters: {
            ...rest,
            'port': ports[i],
            'protocol': protocols[i],
          },
          fragment: '$baseName:${ports[i]}/${protocols[i]}',
        ).toString(),
    ];
  }
}
