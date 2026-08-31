/// Ссылка `wg://` → текст `.conf`.
///
/// Amnezia, Happ и панели раздают AmneziaWG не только файлом, но и одной
/// строкой: `wg://host:port?private_key=…&jc=4&…`. Внутри ровно то же, что в
/// `.conf`, поэтому ссылку разворачиваем прямо на импорте, а дальше по
/// приложению живёт ОДИН формат — `.conf`. Второй пришлось бы учить каждому,
/// кто трогает конфиг сервера: пингу, редактору, генератору wireproxy, сборке
/// UAPI, бэкапу и подписочному диффу.
///
/// Разбор намеренно снисходительный к именам параметров (`private_key`,
/// `privatekey`, `sk` — одно и то же) и строгий к сути: без ключей, адреса и
/// endpoint'а ссылка не конфиг, и лучше сказать об этом на импорте, чем отдать
/// ядру профиль, который не поднимется.
library;

abstract final class AwgUri {
  static const _schemes = ['wg://', 'wireguard://', 'awg://'];

  /// AWG-параметры: имя в ссылке (без `_`/`-`, в нижнем регистре) → ключ
  /// `.conf`. Порядок объявления — порядок строк в готовом конфиге.
  ///
  /// Список закрытый по той же причине, что и таблица UAPI в `AwgProfile`:
  /// незнакомый ключ в `[Interface]` ядро не игнорирует, а роняет им весь
  /// профиль. Чего здесь нет — в конфиг не попадает.
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

  /// Адреса в таких ссылках разделяют то запятой, то дефисом
  /// (`172.16.0.2/32-2606:4700::2/128`) — дефис безопасен: ни в IPv4, ни в
  /// IPv6, ни в маске его быть не может.
  static final _listSeparator = RegExp(r'[,\-]');

  static bool looksLikeUri(String raw) {
    final lower = raw.trimLeft().toLowerCase();
    return _schemes.any(lower.startsWith);
  }

  /// Разворачивает ссылку в `.conf`. Бросает [ArgumentError] с человеческой
  /// причиной — её показывает импорт.
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
    // Uri отдаёт IPv6-хост без скобок, а Endpoint без них не разобрать.
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
    // AllowedIPs в ссылках обычно нет вовсе, а пустой список — это туннель,
    // который поднялся и не пропускает ничего.
    final allowedIps = _list(_first(q, const ['allowedips', 'allowedip']));
    // Ссылки почти никогда не несут keepalive, а WG за NAT без него замолкает
    // через минуту тишины; 25 секунд — то же значение, что пишет в `.conf`
    // сама Amnezia.
    final keepalive =
        _first(q, const ['persistentkeepalive', 'keepalive']) ?? '25';

    final conf = StringBuffer();
    final name = uri.fragment.trim();
    if (name.isNotEmpty) {
      // Имя сервера приложение берёт из ведущего комментария .conf.
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

  /// `enable_amnezia=false` — ссылка на обычный WireGuard, и обфускация из неё
  /// (если её вообще положили) в конфиг идти не должна.
  static bool _amneziaEnabled(Map<String, String> q) {
    final raw = _first(q, const ['enableamnezia', 'enableamneziawg', 'amnezia']);
    if (raw == null) return true;
    return !const ['false', '0', 'no', 'off'].contains(raw.trim().toLowerCase());
  }

  /// Отрезает `userInfo` (ключ до `@`) сам, до `Uri.parse`.
  ///
  /// В части ссылок приватный ключ кладут в userInfo как есть, а base64 с `/`
  /// и `=` в авторити не живёт: `Uri` обрывает хост по первому же слэшу, и
  /// ключа не видит вовсе — ссылка выглядит как «нет private_key». Ищем
  /// последний `@` до `?`/`#` и вырезаем всё до него.
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

  /// Разбор query руками, а не через `uri.queryParameters`: тот декодирует
  /// значения как form-urlencoded и превращает `+` в пробел — а `+` есть
  /// ровно в каждом втором base64-ключе WireGuard, и ключ молча портится.
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

  /// `%`-декодирование там, где оно есть. Значение может приехать и уже
  /// разобранным (`Uri.userInfo`), и битым — на битом декодировать нечего,
  /// отдаём как есть, а причину назовёт разбор `.conf`.
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
