import 'raw_share_uri.dart';

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

  // схема одна на обе версии, решают параметры. без признаков считаем второй: часть панелей так выдаёт hysteria2
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

  // без порта 443 (Hysteria 2 URI Scheme). явный :0 оставляем, как v2rayN: Uri его от пропуска не отличает
  static int port(String config) {
    final raw = RawShareUri.parse(splitPorts(config).$1);
    if (raw == null || raw.port.isEmpty) return 443;
    return int.tryParse(raw.port) ?? 0;
  }

  // как splitHysteria2Ports ядра (common/convert/v.go), IPv6 в скобках не трогаем
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
      final (normalized, addressPorts) = splitPorts(config);
      final uri = Uri.parse(normalized);
      // пин base64 с +, разбор по правилам формы читает + как пробел
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
