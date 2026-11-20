// одна ссылка описывает несколько серверов (пары port/protocol), на импорте раскладываем;
// разбор сверен с converter.go mihomo
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

  final int? port;

  final String portRange;

  final String transport;

  final String multiplexing;
  final String handshakeMode;
  final String trafficPattern;

  static bool looksLikeUri(String config) =>
      config.trimLeft().toLowerCase().startsWith('mierus://');

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

  // имя как у ядра, имя:порт/транспорт, иначе серверы не различить
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
