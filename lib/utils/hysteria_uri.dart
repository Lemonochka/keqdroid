/// parses hysteria / hysteria2 / hy2 share links for config and ping.
class HysteriaLinkParams {
  final String obfsType;
  final String obfsPassword;
  final String sni;
  final String alpn;
  final String pinSha256;
  final String up;
  final String down;
  final String mport;
  final String hopInterval;

  const HysteriaLinkParams({
    this.obfsType = '',
    this.obfsPassword = '',
    this.sni = '',
    this.alpn = '',
    this.pinSha256 = '',
    this.up = '',
    this.down = '',
    this.mport = '',
    this.hopInterval = '',
  });

  /// Ссылка первой версии Hysteria — той, что мы не поддерживаем.
  ///
  /// Схема `hysteria://` одна на обе версии, поэтому решают параметры. Эти
  /// бывают только у первой: полосу она называет `upmbps`/`downmbps`, имя
  /// сертификата — `peer`, а `protocol`, `auth_str` и `obfsParam` во второй
  /// версии не существуют вовсе.
  ///
  /// Ссылку без этих признаков считаем второй версией намеренно: часть панелей
  /// выдаёт hysteria2 под старой схемой, и отбрасывать её значило бы терять
  /// рабочие серверы. Проверять по признакам, а не по схеме, — единственный
  /// способ различить их вообще.
  static bool isV1(String config) {
    final trimmed = config.trim();
    if (!trimmed.toLowerCase().startsWith('hysteria://')) return false;
    final Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (_) {
      return false;
    }
    final params = uri.queryParameters;
    if (params['version']?.trim() == '1') return true;
    return const ['upmbps', 'downmbps', 'peer', 'obfsParam', 'protocol', 'auth_str']
        .any((key) => (params[key] ?? '').trim().isNotEmpty);
  }

  bool get hasSalamanderObfs =>
      obfsType.toLowerCase() == 'salamander' && obfsPassword.isNotEmpty;

  static HysteriaLinkParams fromConfig(String config) {
    try {
      final uri = Uri.parse(config.trim());
      String q(String key, [List<String> aliases = const []]) {
        final v = uri.queryParameters[key];
        if (v != null && v.trim().isNotEmpty) return v.trim();
        for (final a in aliases) {
          final av = uri.queryParameters[a];
          if (av != null && av.trim().isNotEmpty) return av.trim();
        }
        return '';
      }

      return HysteriaLinkParams(
        obfsType: q('obfs'),
        obfsPassword: q('obfs-password', ['obfs_password', 'obfspassword']),
        sni: q('sni', ['host', 'peer']),
        alpn: q('alpn'),
        pinSha256: q('pinSHA256', ['pinsha256', 'pin']),
        up: q('up', ['upmbps']),
        down: q('down', ['downmbps']),
        mport: q('mport', ['ports']),
        hopInterval: q('hop-interval', ['hop_interval', 'hopinterval']),
      );
    } catch (_) {
      return const HysteriaLinkParams();
    }
  }

  /// xray finalmask.udp for salamander obfs.
  Map<String, dynamic>? buildFinalmask() {
    if (!hasSalamanderObfs) return null;
    return {
      'udp': [
        {
          'type': 'salamander',
          'settings': {'password': obfsPassword},
        },
      ],
    };
  }

  static String? formatBandwidth(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return null;
    if (RegExp(r'[a-zA-Z]').hasMatch(v)) return v;
    return '${v}mbps';
  }
}
