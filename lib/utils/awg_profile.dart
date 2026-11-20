import 'dart:convert';

// каждый ключ AWG должен быть в _uapiNames, иначе он тихо потеряется по дороге в ядро
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

  // список закрытый: незнакомый ключ ядро не пропускает, а роняет весь IpcSet (invalid UAPI device key)
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
    for (final rawLine in const LineSplitter().convert(raw)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) {
        continue;
      }
      return line.toLowerCase().startsWith('[interface]');
    }
    return false;
  }

  static AwgProfile parse(String raw, {String? fileName}) {
    final trimmed = raw.trim();
    if (!isAwgConfig(trimmed)) {
      throw ArgumentError(
        'Not an AmneziaWG/WireGuard config (expected [Interface])',
      );
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
      remark:
          leadingRemark ?? (fileName != null ? _stripConfExt(fileName) : null),
      iface: iface,
      peers: parsedPeers,
      rawConf: trimmed,
    );
  }

  String get endpointHost => splitEndpoint(peer.endpoint).$1;

  int get endpointPort => splitEndpoint(peer.endpoint).$2;

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

  // с AWG 3.1 туда пишут диапазон (22-30), плюс off из wg-quick; int.tryParse на обоих терял keepalive,
  // и за NAT туннель рвался
  static String? _keepalive(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    if (value.toLowerCase() == 'off') return '0';
    return _uintRange(value, 'PersistentKeepalive');
  }

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

  // в .conf пишут ещё yes и on, такие профили работали и раньше
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

  // в .conf ключ base64, как у остальных ключей WG, а UAPI ждёт hex
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
    final m = RegExp(
      r'^name\s*[:=]\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(s);
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

  static (String, int) splitEndpoint(String endpoint) {
    final ep = endpoint.trim();
    if (ep.startsWith('[')) {
      final close = ep.indexOf(']');
      if (close > 0) {
        final host = ep.substring(1, close);
        final rest = ep.substring(close + 1);
        final port = rest.startsWith(':')
            ? int.tryParse(rest.substring(1))
            : null;
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

  final String? persistentKeepalive;

  const AwgPeer({
    required this.publicKey,
    required this.presharedKey,
    required this.endpoint,
    required this.allowedIps,
    required this.persistentKeepalive,
  });
}
