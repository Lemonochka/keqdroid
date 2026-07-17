/// Разобранная вручную share-ссылка (vless:// / trojan:// / ss:// / hy2://).
///
/// Разбираем строку сами, а не через Uri.parse: акцессоры Uri декодируют
/// компоненты, и пересборка меняла бы percent-encoding нетронутых частей
/// (userInfo, fragment, незнакомые query-параметры). GUI-редактор конфига
/// правит только управляемые параметры, всё остальное возвращается байт в байт.
class RawShareUri {
  final String scheme;
  String userInfo; // сырой, без хвостового '@'; '' если нет
  String host; // сырой, IPv6 — в скобках '[..]'
  String port; // строкой; '' если не указан
  final String path; // с ведущим '/', обычно ''
  final List<RawQueryToken> query;
  final String fragment; // сырой, после '#'
  final bool hasFragment;

  RawShareUri({
    required this.scheme,
    required this.userInfo,
    required this.host,
    required this.port,
    required this.path,
    required this.query,
    required this.fragment,
    required this.hasFragment,
  });

  static RawShareUri? parse(String config) {
    final m = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*)://').firstMatch(config);
    if (m == null) return null;
    final scheme = m.group(1)!;
    var rest = config.substring(m.end);

    String fragment = '';
    var hasFragment = false;
    final hashIdx = rest.indexOf('#');
    if (hashIdx >= 0) {
      fragment = rest.substring(hashIdx + 1);
      hasFragment = true;
      rest = rest.substring(0, hashIdx);
    }

    String rawQuery = '';
    final qIdx = rest.indexOf('?');
    if (qIdx >= 0) {
      rawQuery = rest.substring(qIdx + 1);
      rest = rest.substring(0, qIdx);
    }

    String path = '';
    final slashIdx = rest.indexOf('/');
    if (slashIdx >= 0) {
      path = rest.substring(slashIdx);
      rest = rest.substring(0, slashIdx);
    }

    // authority: [userInfo@]host[:port]
    String userInfo = '';
    var hostPort = rest;
    final atIdx = rest.lastIndexOf('@');
    if (atIdx >= 0) {
      userInfo = rest.substring(0, atIdx);
      hostPort = rest.substring(atIdx + 1);
    }

    String host;
    String port = '';
    if (hostPort.startsWith('[')) {
      final closeIdx = hostPort.indexOf(']');
      if (closeIdx < 0) return null;
      host = hostPort.substring(0, closeIdx + 1);
      final tail = hostPort.substring(closeIdx + 1);
      if (tail.startsWith(':')) port = tail.substring(1);
    } else {
      final colonIdx = hostPort.lastIndexOf(':');
      if (colonIdx >= 0) {
        host = hostPort.substring(0, colonIdx);
        port = hostPort.substring(colonIdx + 1);
      } else {
        host = hostPort;
      }
    }
    if (host.isEmpty) return null;

    final tokens = <RawQueryToken>[];
    if (rawQuery.isNotEmpty) {
      for (final tok in rawQuery.split('&')) {
        if (tok.isEmpty) continue;
        final eq = tok.indexOf('=');
        final rawKey = eq >= 0 ? tok.substring(0, eq) : tok;
        String key;
        try {
          key = Uri.decodeQueryComponent(rawKey);
        } catch (_) {
          key = rawKey;
        }
        tokens.add(RawQueryToken(key, tok));
      }
    }

    return RawShareUri(
      scheme: scheme,
      userInfo: userInfo,
      host: host,
      port: port,
      path: path,
      query: tokens,
      fragment: fragment,
      hasFragment: hasFragment,
    );
  }

  /// Забирает первое значение managed-ключа (декодированное) и удаляет все
  /// его вхождения из [query].
  String takeParam(String key) {
    String value = '';
    query.removeWhere((t) {
      if (t.key != key) return false;
      if (value.isEmpty) {
        final eq = t.raw.indexOf('=');
        final rawValue = eq >= 0 ? t.raw.substring(eq + 1) : '';
        try {
          value = Uri.decodeQueryComponent(rawValue);
        } catch (_) {
          value = rawValue;
        }
      }
      return true;
    });
    return value;
  }

  bool hasParam(String key) => query.any((t) => t.key == key);

  /// Пересборка ссылки: оставшиеся (незнакомые) query-токены идут как есть,
  /// затем [managedParams] с непустыми значениями (кодируются заново).
  String build({required List<MapEntry<String, String>> managedParams}) {
    final sb = StringBuffer('$scheme://');
    if (userInfo.isNotEmpty) sb.write('$userInfo@');
    sb.write(host);
    if (port.isNotEmpty) sb.write(':$port');
    sb.write(path);
    final parts = <String>[
      for (final t in query) t.raw,
      for (final p in managedParams)
        if (p.value.isNotEmpty)
          '${Uri.encodeQueryComponent(p.key)}=${Uri.encodeQueryComponent(p.value)}',
    ];
    if (parts.isNotEmpty) sb.write('?${parts.join('&')}');
    if (hasFragment) sb.write('#$fragment');
    return sb.toString();
  }
}

/// query-токен исходной ссылки: [key] — декодированное имя для матчинга,
/// [raw] — сырой токен `key=value`, который для незнакомых параметров
/// возвращается в ссылку без изменений.
class RawQueryToken {
  final String key;
  final String raw;
  const RawQueryToken(this.key, this.raw);
}
