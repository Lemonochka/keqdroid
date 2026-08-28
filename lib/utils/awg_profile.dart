import 'dart:convert';

/// Parsed WireGuard / AmneziaWG `.conf` profile.
///
/// Хранится в [ServerItem.config] как сырой текст `.conf`. Версию протокола
/// (1.0/1.5/2.0/3.1) никто не объявляет — её задаёт набор ключей в
/// `[Interface]`: обфускация пакетов (Jc/Jmin/Jmax, S1..S4, H1..H4, I1..I5) и,
/// с AWG 3.1, защита уже поднятого туннеля (`HeaderProtectionKey`,
/// `ContentPaddingAddition`, таймеры, `RandomTrailers`, `DisableCookies`).
///
/// На десктопе `.conf` уезжает в wireproxy как есть, и ключи разбирает он сам;
/// на Android ядро принимает только UAPI, поэтому каждый ключ должен быть
/// назван в [_uapiNames] — иначе он тихо потеряется по дороге.
class AwgProfile {
  final String? remark;
  final AwgInterface iface;
  final List<AwgPeer> peers;
  final String rawConf;

  const AwgProfile({
    required this.remark,
    required this.iface,
    required this.peers,
    required this.rawConf,
  });

  AwgPeer get peer => peers.first;

  /// Ключи AmneziaWG в `[Interface]` (lowercase) → имя того же параметра в UAPI.
  ///
  /// Список закрытый, и это принципиально: незнакомый ключ ядро не пропускает
  /// мимо, а роняет весь `IpcSet` («invalid UAPI device key»), то есть туннель
  /// не поднимается вовсе. Всё, чего здесь нет, остаётся обычной строкой
  /// `.conf` и до UAPI не доезжает — так же, как `Address` или `MTU`.
  ///
  /// Первая половина — обфускация пакетов (AWG 1.5/2.0), там имя совпадает с
  /// ключом в нижнем регистре. Вторая — AWG 3.1, и вот там имена РАЗНЫЕ:
  /// в конфиге слова, в UAPI snake_case, поэтому нужна таблица, а не
  /// `toLowerCase()`.
  static const _uapiNames = <String, String>{
    'jc': 'jc',
    'jmin': 'jmin',
    'jmax': 'jmax',
    's1': 's1',
    's2': 's2',
    's3': 's3',
    's4': 's4',
    'h1': 'h1',
    'h2': 'h2',
    'h3': 'h3',
    'h4': 'h4',
    'i1': 'i1',
    'i2': 'i2',
    'i3': 'i3',
    'i4': 'i4',
    'i5': 'i5',
    // AWG 3.1: шифрование заголовков, добор длины и разброс таймеров.
    'headerprotectionkey': 'header_protection_key',
    'contentpaddingaddition': 'content_padding_addition',
    'rekeyaftertime': 'rekey_after_time',
    'rekeytimeout': 'rekey_timeout',
    'rejectaftertime': 'reject_after_time',
    'keepalivetimeout': 'keepalive_timeout',
    'maxhandshakeattempts': 'max_handshake_attempts',
    'randomtrailers': 'random_trailers',
    'disablecookies': 'disable_cookies',
  };

  static bool isAwgConfig(String raw) {
    // первая значимая строка (без ведущих комментариев/пустых) — [Interface]
    for (final rawLine in const LineSplitter().convert(raw)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) continue;
      return line.toLowerCase().startsWith('[interface]');
    }
    return false;
  }

  static AwgProfile parse(String raw, {String? fileName}) {
    final trimmed = raw.trim();
    if (!isAwgConfig(trimmed)) {
      throw ArgumentError('Not an AmneziaWG/WireGuard config (expected [Interface])');
    }

    String? leadingRemark;
    final interfaceKv = <String, String>{};
    final awgParams = <String, String>{};
    final peers = <Map<String, String>>[];
    Map<String, String>? currentPeer;
    String section = '';

    for (final rawLine in const LineSplitter().convert(trimmed)) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#') || line.startsWith(';')) {
        // первый комментарий до секций — человекочитаемое имя
        leadingRemark ??= _extractRemark(line);
        continue;
      }
      if (line.startsWith('[') && line.endsWith(']')) {
        section = line.substring(1, line.length - 1).trim().toLowerCase();
        if (section == 'peer') {
          currentPeer = <String, String>{};
          peers.add(currentPeer);
        }
        continue;
      }

      final eq = line.indexOf('=');
      if (eq < 0) continue;
      final key = line.substring(0, eq).trim();
      final value = line.substring(eq + 1).trim();
      if (key.isEmpty) continue;

      if (section == 'interface') {
        final lower = key.toLowerCase();
        if (_uapiNames.containsKey(lower)) {
          awgParams[lower] = value;
        } else {
          interfaceKv[lower] = value;
        }
      } else if (section == 'peer' && currentPeer != null) {
        currentPeer[key.toLowerCase()] = value;
      }
    }

    if (peers.isEmpty) {
      throw ArgumentError('AmneziaWG config: [Peer] section is required');
    }

    final privateKey = interfaceKv['privatekey']?.trim() ?? '';
    if (privateKey.isEmpty) {
      throw ArgumentError('AmneziaWG config: Interface.PrivateKey is required');
    }

    // Значения проверяем здесь, а не в [toUapi]: на импорте ошибка видна в
    // диалоге и рядом с местом, где конфиг правят, а на подключении — только
    // как отказ ядра поднять устройство, одинаковый для любой опечатки.
    for (final entry in awgParams.entries) {
      _uapiValue(entry.key, entry.value);
    }

    final iface = AwgInterface(
      privateKey: privateKey,
      addresses: _splitCsv(interfaceKv['address']),
      dns: _splitCsv(interfaceKv['dns']),
      mtu: int.tryParse(interfaceKv['mtu'] ?? ''),
      awgParams: awgParams,
    );

    final parsedPeers = peers.map((p) {
      final endpoint = p['endpoint']?.trim() ?? '';
      final publicKey = p['publickey']?.trim() ?? '';
      if (publicKey.isEmpty) {
        throw ArgumentError('AmneziaWG config: Peer.PublicKey is required');
      }
      if (endpoint.isEmpty) {
        throw ArgumentError('AmneziaWG config: Peer.Endpoint is required');
      }
      return AwgPeer(
        publicKey: publicKey,
        presharedKey: p['presharedkey']?.trim(),
        endpoint: endpoint,
        allowedIps: _splitCsv(p['allowedips']),
        persistentKeepalive: _keepalive(p['persistentkeepalive']),
      );
    }).toList();

    return AwgProfile(
      remark: leadingRemark ?? (fileName != null ? _stripConfExt(fileName) : null),
      iface: iface,
      peers: parsedPeers,
      rawConf: trimmed,
    );
  }

  /// Хост сервера из `Endpoint` первого пира (для пинга и direct-исключения).
  String get endpointHost => splitEndpoint(peer.endpoint).$1;

  /// Порт сервера из `Endpoint` первого пира.
  int get endpointPort => splitEndpoint(peer.endpoint).$2;

  /// Имя туннеля для Windows-сервиса: безопасный slug (буквы/цифры/`_-`).
  String tunnelName() {
    final base = (remark != null && remark!.trim().isNotEmpty)
        ? remark!.trim()
        : endpointHost;
    final slug = base.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    final trimmed = slug.replaceAll(RegExp(r'^_+|_+$'), '');
    final name = trimmed.isEmpty ? 'awg' : trimmed;
    return name.length > 32 ? name.substring(0, 32) : name;
  }

  /// UAPI-строка для amneziawg-go (Android `wgTurnOn`). Ключи WG в `.conf` —
  /// base64, UAPI требует hex. AWG-параметры идут на уровне устройства.
  ///
  /// [endpointOverrides] — подмена `Endpoint` по его исходной строке из
  /// `.conf`: UAPI ядра принимает endpoint только как литеральный IP:port
  /// (netip.ParseAddrPort, без DNS), так что доменные endpoint'ы вызывающий
  /// код обязан отрезолвить заранее.
  String toUapi({Map<String, String> endpointOverrides = const {}}) {
    final sb = StringBuffer();
    sb.writeln('private_key=${_b64ToHex(iface.privateKey)}');
    // Параметры AmneziaWG — на уровне device, до пиров.
    for (final entry in iface.awgParams.entries) {
      final name = _uapiNames[entry.key];
      // Ключ не из таблицы в UAPI не отдаём ни при каких условиях: ядро
      // отвечает на него ошибкой и не поднимает устройство целиком.
      if (name == null) continue;
      sb.writeln('$name=${_uapiValue(entry.key, entry.value)}');
    }
    sb.writeln('replace_peers=true');
    for (final p in peers) {
      sb.writeln('public_key=${_b64ToHex(p.publicKey)}');
      if (p.presharedKey != null && p.presharedKey!.isNotEmpty) {
        sb.writeln('preshared_key=${_b64ToHex(p.presharedKey!)}');
      }
      sb.writeln('endpoint=${endpointOverrides[p.endpoint] ?? p.endpoint}');
      if (p.persistentKeepalive != null) {
        sb.writeln('persistent_keepalive_interval=${p.persistentKeepalive}');
      }
      sb.writeln('replace_allowed_ips=true');
      for (final ip in p.allowedIps) {
        sb.writeln('allowed_ip=$ip');
      }
    }
    return sb.toString();
  }

  /// Значение параметра в той форме, какую ждёт UAPI. Бросает [ArgumentError],
  /// если значение не той формы: ядру такое отдавать нельзя, оно откажется
  /// поднимать устройство и заодно потеряет все остальные параметры.
  static String _uapiValue(String key, String raw) {
    switch (key) {
      case 'headerprotectionkey':
        return _keyToHex(raw, 'HeaderProtectionKey');
      case 'contentpaddingaddition':
        return _uintRange(raw, 'ContentPaddingAddition');
      case 'rekeyaftertime':
        return _uintRange(raw, 'RekeyAfterTime');
      case 'rekeytimeout':
        return _uintRange(raw, 'RekeyTimeout');
      case 'rejectaftertime':
        return _uintRange(raw, 'RejectAfterTime');
      case 'keepalivetimeout':
        return _uintRange(raw, 'KeepaliveTimeout');
      case 'maxhandshakeattempts':
        return _uintRange(raw, 'MaxHandshakeAttempts');
      case 'randomtrailers':
        return _boolFlag(raw, 'RandomTrailers');
      case 'disablecookies':
        return _boolFlag(raw, 'DisableCookies');
      default:
        return raw;
    }
  }

  /// `PersistentKeepalive` из `.conf` в значение для UAPI.
  ///
  /// С AWG 3.1 это уже не число, а диапазон (`22-30`): ядро выбирает внутри
  /// него случайное значение, чтобы keepalive не шёл ровно по метроному. Плюс
  /// `off` из wg-quick, которого в UAPI нет вовсе. Разбор через `int.tryParse`
  /// давал на обоих `null` — ключ уходил из UAPI целиком, и туннель молча
  /// оставался без keepalive (за NAT это разрыв через минуту тишины).
  static String? _keepalive(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    if (value.toLowerCase() == 'off') return '0';
    return _uintRange(value, 'PersistentKeepalive');
  }

  /// Диапазон AWG 3.1: `a` или `a-b`, обе границы в uint32 и `a <= b`.
  static String _uintRange(String raw, String name) {
    final value = raw.trim();
    final m = RegExp(r'^(\d{1,10})(?:-(\d{1,10}))?$').firstMatch(value);
    if (m != null) {
      final lo = int.parse(m.group(1)!);
      final hi = m.group(2) == null ? lo : int.parse(m.group(2)!);
      if (lo <= hi && hi <= 0xFFFFFFFF) return value;
    }
    throw ArgumentError(
      'AmneziaWG config: $name must be a number or a range "a-b" '
      'within 0..4294967295, got "$raw"',
    );
  }

  /// Флаг AWG 3.1. В UAPI это `strconv.ParseBool`, а в `.conf` пишут ещё и
  /// `yes`/`on` — их понимает ini-разбор wireproxy, так что на десктопе такой
  /// конфиг работает, и отдать Android'у меньше было бы расхождением ядер.
  static String _boolFlag(String raw, String name) {
    switch (raw.trim().toLowerCase()) {
      case 'true':
      case 't':
      case '1':
      case 'yes':
      case 'on':
        return 'true';
      case 'false':
      case 'f':
      case '0':
      case 'no':
      case 'off':
        return 'false';
    }
    throw ArgumentError(
      'AmneziaWG config: $name must be true or false, got "$raw"',
    );
  }

  /// 32-байтный ключ base64 → hex. В `.conf` `HeaderProtectionKey` записан так
  /// же, как остальные ключи WG (его печатает `awg genkey`), а UAPI ждёт hex.
  static String _keyToHex(String raw, String name) {
    final value = raw.trim();
    try {
      if (base64.decode(base64.normalize(value)).length != 32) {
        throw const FormatException('wrong key length');
      }
    } on FormatException {
      throw ArgumentError(
        'AmneziaWG config: $name must be a 32-byte base64 key',
      );
    }
    return _b64ToHex(value);
  }

  static String? _extractRemark(String commentLine) {
    var s = commentLine.replaceFirst(RegExp(r'^[#;]+'), '').trim();
    // поддержка "# Name = Foo" / "# Name: Foo"
    final m = RegExp(r'^name\s*[:=]\s*(.+)$', caseSensitive: false).firstMatch(s);
    if (m != null) s = m.group(1)!.trim();
    return s.isEmpty ? null : s;
  }

  static String _stripConfExt(String fileName) {
    final base = fileName.split(RegExp(r'[\\/]')).last;
    return base.replaceFirst(RegExp(r'\.conf$', caseSensitive: false), '');
  }

  static List<String> _splitCsv(String? value) {
    if (value == null) return const [];
    return value
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// `host:port` / `[v6]:port` → (host, port). Публичный: нужен бэкендам,
  /// чтобы резолвить доменные endpoint'ы каждого пира перед [toUapi].
  static (String, int) splitEndpoint(String endpoint) {
    final ep = endpoint.trim();
    // IPv6 в скобках: [::1]:51820
    if (ep.startsWith('[')) {
      final close = ep.indexOf(']');
      if (close > 0) {
        final host = ep.substring(1, close);
        final rest = ep.substring(close + 1);
        final port = rest.startsWith(':') ? int.tryParse(rest.substring(1)) : null;
        return (host, port ?? 51820);
      }
    }
    final idx = ep.lastIndexOf(':');
    if (idx < 0) return (ep, 51820);
    final host = ep.substring(0, idx);
    final port = int.tryParse(ep.substring(idx + 1)) ?? 51820;
    return (host, port);
  }

  static String _b64ToHex(String b64) {
    final bytes = base64.decode(base64.normalize(b64.trim()));
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}

class AwgInterface {
  final String privateKey;
  final List<String> addresses;
  final List<String> dns;
  final int? mtu;

  /// Параметры AmneziaWG, ключи в lowercase как в `.conf`: обфускация пакетов
  /// (jc/jmin/jmax, s1..s4, h1..h4, i1..i5) и AWG 3.1 (headerprotectionkey,
  /// contentpaddingaddition, таймеры, randomtrailers, disablecookies). Что
  /// именно допустимо и как зовётся в ядре — [AwgProfile._uapiNames].
  final Map<String, String> awgParams;

  const AwgInterface({
    required this.privateKey,
    required this.addresses,
    required this.dns,
    required this.mtu,
    required this.awgParams,
  });
}

class AwgPeer {
  final String publicKey;
  final String? presharedKey;
  final String endpoint;
  final List<String> allowedIps;

  /// Секунды в форме, готовой для UAPI: `25`, диапазон `22-30` (AWG 3.1) или
  /// `0` (в `.conf` он же `off`). Не число: диапазон в int не влезает.
  final String? persistentKeepalive;

  const AwgPeer({
    required this.publicKey,
    required this.presharedKey,
    required this.endpoint,
    required this.allowedIps,
    required this.persistentKeepalive,
  });
}
