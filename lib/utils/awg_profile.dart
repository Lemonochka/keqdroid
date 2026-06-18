import 'dart:convert';

/// Parsed WireGuard / AmneziaWG `.conf` profile.
///
/// Хранится в [ServerItem.config] как сырой текст `.conf`. AmneziaWG-параметры
/// обфускации (Jc/Jmin/Jmax, S1..S4, H1..H4, I1..I5) пробрасываются как есть —
/// версия протокола (1.0/1.5/2.0) определяется ядром и набором этих ключей.
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

  /// Канонические ключи обфускации AmneziaWG (без учёта регистра в `.conf`).
  static final RegExp _awgKey =
      RegExp(r'^(jc|jmin|jmax|s[1-4]|h[1-4]|i[1-5])$', caseSensitive: false);

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
        if (_awgKey.hasMatch(key)) {
          awgParams[key.toLowerCase()] = value;
        } else {
          interfaceKv[key.toLowerCase()] = value;
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
        persistentKeepalive: int.tryParse(p['persistentkeepalive'] ?? ''),
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
  String get endpointHost => _splitEndpoint(peer.endpoint).$1;

  /// Порт сервера из `Endpoint` первого пира.
  int get endpointPort => _splitEndpoint(peer.endpoint).$2;

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
  String toUapi() {
    final sb = StringBuffer();
    sb.writeln('private_key=${_b64ToHex(iface.privateKey)}');
    // Параметры обфускации AmneziaWG — на уровне device, до пиров.
    for (final entry in iface.awgParams.entries) {
      sb.writeln('${entry.key}=${entry.value}');
    }
    sb.writeln('replace_peers=true');
    for (final p in peers) {
      sb.writeln('public_key=${_b64ToHex(p.publicKey)}');
      if (p.presharedKey != null && p.presharedKey!.isNotEmpty) {
        sb.writeln('preshared_key=${_b64ToHex(p.presharedKey!)}');
      }
      sb.writeln('endpoint=${p.endpoint}');
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

  static (String, int) _splitEndpoint(String endpoint) {
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

  /// Параметры обфускации AmneziaWG в lowercase: jc/jmin/jmax/s1..s4/h1..h4/i1..i5.
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
  final int? persistentKeepalive;

  const AwgPeer({
    required this.publicKey,
    required this.presharedKey,
    required this.endpoint,
    required this.allowedIps,
    required this.persistentKeepalive,
  });
}
