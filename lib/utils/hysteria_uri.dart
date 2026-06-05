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
