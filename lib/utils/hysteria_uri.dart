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

  /// Список портов, записанный прямо в адресе: `hy2://pwd@host:20000-20050,443`.
  ///
  /// Такую ссылку `Uri.parse` не берёт вовсе — порт у неё не число, — и до сих
  /// пор она разваливалась целиком, вместе со всеми остальными параметрами.
  /// Возвращает ссылку, где в адресе оставлен первый порт (её уже можно
  /// разобрать), и сам список; список пуст — значит адрес был обычный.
  ///
  /// Разбор повторяет `splitHysteria2Ports` ядра (`common/convert/v.go`),
  /// включая отказ трогать IPv6-адрес в скобках: там двоеточий и без того
  /// хватает.
  static (String link, String ports) splitPorts(String config) {
    final line = config.trim();
    final schemeEnd = line.indexOf('://');
    if (schemeEnd < 0) return (line, '');
    final head = line.substring(0, schemeEnd + 3);
    final rest = line.substring(schemeEnd + 3);

    var authority = rest;
    var tail = '';
    final cut = rest.indexOf(RegExp(r'[/?#]'));
    if (cut >= 0) {
      authority = rest.substring(0, cut);
      tail = rest.substring(cut);
    }
    var userInfo = '';
    final at = authority.lastIndexOf('@');
    if (at >= 0) {
      userInfo = authority.substring(0, at + 1);
      authority = authority.substring(at + 1);
    }
    if (authority.contains(']')) return (line, '');

    final colon = authority.lastIndexOf(':');
    if (colon < 0) return (line, '');
    final host = authority.substring(0, colon);
    final ports = authority.substring(colon + 1);
    if (!ports.contains(',') && !ports.contains('-')) return (line, '');

    final firstEnd = ports.indexOf(RegExp(r'[,-]'));
    final first = firstEnd >= 0 ? ports.substring(0, firstEnd) : ports;
    if (first.isEmpty) return (line, '');
    return ('$head$userInfo$host:$first$tail', ports);
  }

  bool get hasSalamanderObfs =>
      obfsType.toLowerCase() == 'salamander' && obfsPassword.isNotEmpty;

  static HysteriaLinkParams fromConfig(String config) {
    try {
      // Список портов из адреса вынимаем до разбора: с ним `Uri.parse` падает
      // и терялись бы заодно все остальные параметры ссылки.
      final (normalized, addressPorts) = splitPorts(config);
      final uri = Uri.parse(normalized);
      // Пин сертификата — base64 с `+` и `/`. Разбор запроса по правилам
      // HTML-формы читает `+` как пробел, и пин приезжает испорченным; ядру
      // это неотличимо от неверного отпечатка.
      String raw(String key) {
        for (final pair in uri.query.split('&')) {
          final eq = pair.indexOf('=');
          if (eq < 0) continue;
          if (Uri.decodeComponent(pair.substring(0, eq)) != key) continue;
          final value = Uri.decodeComponent(pair.substring(eq + 1)).trim();
          if (value.isNotEmpty) return value;
        }
        return '';
      }

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
        pinSha256: raw('pinSHA256').isNotEmpty
            ? raw('pinSHA256')
            : (raw('pinsha256').isNotEmpty ? raw('pinsha256') : raw('pin')),
        up: q('up', ['upmbps']),
        down: q('down', ['downmbps']),
        mport: q('mport', ['ports']).isNotEmpty
            ? q('mport', ['ports'])
            : addressPorts,
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
