library;

abstract final class AwgUri {
  static const _schemes = ['wg://', 'wireguard://', 'awg://'];

  // список закрытый: незнакомый ключ в [Interface] ядро не пропускает и роняет профиль
  static const _awgParams = <String, String>{
    'jc': 'Jc',
    'jmin': 'Jmin',
    'jmax': 'Jmax',
    's1': 'S1',
    's2': 'S2',
    's3': 'S3',
    's4': 'S4',
    'h1': 'H1',
    'h2': 'H2',
    'h3': 'H3',
    'h4': 'H4',
    'i1': 'I1',
    'i2': 'I2',
    'i3': 'I3',
    'i4': 'I4',
    'i5': 'I5',
    'headerprotectionkey': 'HeaderProtectionKey',
    'contentpaddingaddition': 'ContentPaddingAddition',
    'rekeyaftertime': 'RekeyAfterTime',
    'rekeytimeout': 'RekeyTimeout',
    'rejectaftertime': 'RejectAfterTime',
    'keepalivetimeout': 'KeepaliveTimeout',
    'maxhandshakeattempts': 'MaxHandshakeAttempts',
    'randomtrailers': 'RandomTrailers',
    'disablecookies': 'DisableCookies',
  };

  // адреса разделяют и дефисом: ни в IPv4, ни в IPv6, ни в маске его не бывает
  static final _listSeparator = RegExp(r'[,\-]');

  static bool looksLikeUri(String raw) {
    final lower = raw.trimLeft().toLowerCase();
    return _schemes.any(lower.startsWith);
  }

  static String toConf(String raw) {
    final text = raw.trim();
    if (!looksLikeUri(text)) {
      throw ArgumentError('wg:// link: unsupported scheme');
    }

    final (userInfo, withoutUser) = _cutUserInfo(text);
    final Uri uri;
    try {
      uri = Uri.parse(withoutUser);
    } on FormatException catch (e) {
      throw ArgumentError('wg:// link: ${e.message}');
    }

    final q = _queryParams(uri);

    final privateKey =
        _first(q, const ['privatekey', 'secretkey', 'sk']) ?? userInfo;
    if (privateKey == null || privateKey.isEmpty) {
      throw ArgumentError('wg:// link: private_key is required');
    }
    final publicKey =
        _first(q, const ['publickey', 'peerpublickey', 'pk', 'serverpublickey']);
    if (publicKey == null || publicKey.isEmpty) {
      throw ArgumentError('wg:// link: public_key is required');
    }

    final host = uri.host;
    if (host.isEmpty) {
      throw ArgumentError('wg:// link: endpoint host is required');
    }
    if (!uri.hasPort) {
      throw ArgumentError('wg:// link: endpoint port is required');
    }
    final endpoint =
        host.contains(':') ? '[$host]:${uri.port}' : '$host:${uri.port}';

    final addresses = _list(
      _first(q, const ['localaddress', 'address', 'addresses', 'ip']),
    );
    if (addresses.isEmpty) {
      throw ArgumentError('wg:// link: local_address is required');
    }

    final dns = _list(_first(q, const ['dns', 'dnsservers']));
    final mtu = _first(q, const ['mtu']);
    final presharedKey = _first(q, const ['presharedkey', 'psk']);
    // AllowedIPs в ссылках обычно нет, а с пустым списком туннель не пропускает ничего
    final allowedIps = _list(_first(q, const ['allowedips', 'allowedip']));
    // без keepalive WG за NAT замолкает через минуту тишины, 25 пишет в .conf сама Amnezia
    final keepalive =
        _first(q, const ['persistentkeepalive', 'keepalive']) ?? '25';

    final conf = StringBuffer();
    final name = uri.fragment.trim();
    if (name.isNotEmpty) {
      conf.writeln('# ${name.replaceAll(RegExp(r'\s+'), ' ')}');
    }
    conf
      ..writeln('[Interface]')
      ..writeln('PrivateKey = $privateKey')
      ..writeln('Address = ${addresses.join(', ')}');
    if (dns.isNotEmpty) conf.writeln('DNS = ${dns.join(', ')}');
    if (mtu != null && mtu.isNotEmpty) conf.writeln('MTU = $mtu');
    if (_amneziaEnabled(q)) {
      for (final entry in _awgParams.entries) {
        final value = q[entry.key];
        if (value == null || value.isEmpty) continue;
        conf.writeln('${entry.value} = $value');
      }
    }
    conf
      ..writeln()
      ..writeln('[Peer]')
      ..writeln('PublicKey = $publicKey');
    if (presharedKey != null && presharedKey.isNotEmpty) {
      conf.writeln('PresharedKey = $presharedKey');
    }
    conf
      ..writeln(
        'AllowedIPs = ${allowedIps.isEmpty ? '0.0.0.0/0, ::/0' : allowedIps.join(', ')}',
      )
      ..writeln('Endpoint = $endpoint')
      ..writeln('PersistentKeepalive = $keepalive');

    return conf.toString();
  }

  static bool _amneziaEnabled(Map<String, String> q) {
    final raw = _first(q, const ['enableamnezia', 'enableamneziawg', 'amnezia']);
    if (raw == null) return true;
    return !const ['false', '0', 'no', 'off'].contains(raw.trim().toLowerCase());
  }

  // base64 с / и = в авторити не живёт: Uri обрывает хост по первому слэшу и ключа не видит
  static (String?, String) _cutUserInfo(String text) {
    final schemeEnd = text.indexOf('://') + 3;
    var end = text.length;
    for (final mark in const ['?', '#']) {
      final i = text.indexOf(mark, schemeEnd);
      if (i >= 0 && i < end) end = i;
    }
    final at = text.lastIndexOf('@', end - 1);
    if (at < schemeEnd) return (null, text);
    return (
      _decodeMaybe(text.substring(schemeEnd, at)),
      text.substring(0, schemeEnd) + text.substring(at + 1),
    );
  }

  // руками: queryParameters превращает + в пробел, а + есть в каждом втором ключе WireGuard
  static Map<String, String> _queryParams(Uri uri) {
    final out = <String, String>{};
    for (final pair in uri.query.split('&')) {
      if (pair.isEmpty) continue;
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      final key = _decodeMaybe(pair.substring(0, eq))
          ?.toLowerCase()
          .replaceAll(RegExp(r'[_\-]'), '');
      final value = _decodeMaybe(pair.substring(eq + 1));
      if (key == null || key.isEmpty || value == null) continue;
      out[key] = value.trim();
    }
    return out;
  }

  static String? _first(Map<String, String> q, List<String> keys) {
    for (final key in keys) {
      final value = q[key];
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  static List<String> _list(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    return raw
        .split(_listSeparator)
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static String? _decodeMaybe(String? raw) {
    if (raw == null || !raw.contains('%')) return raw;
    try {
      return Uri.decodeComponent(raw);
    } on ArgumentError {
      return raw;
    } on FormatException {
      return raw;
    }
  }
}
