final _ipV4 = RegExp(r'^(\d{1,3}\.){3}\d{1,3}(/\d{1,2})?$');
final _ipV6 = RegExp(r'^[0-9a-fA-F:]+(/\d{1,3})?$');

bool looksLikeIpOrCidr(String value) {
  final v = value.trim();
  if (v.isEmpty) return false;
  if (_ipV4.hasMatch(v)) return true;
  // у IPv6 обязательно двоеточие, иначе regex ловил бы голые имена
  if (v.contains(':') && _ipV6.hasMatch(v)) return true;
  return false;
}

// своими адресами не считаем: у многих они в обходе со времён пресета, и стратегия резолва подниматься не должна;
// список общий на оба генератора
const Set<String> kBasePrivateRanges = {
  '0.0.0.0/8', '10.0.0.0/8', '100.64.0.0/10', '127.0.0.0/8',
  '169.254.0.0/16', '172.16.0.0/12', '172.19.0.0/30',
  '192.0.0.0/24', '192.168.0.0/16',
  '198.51.100.0/24', '203.0.113.0/24',
  '::1/128', 'fc00::/7', 'fe80::/10',
};

({List<String> domains, List<String> ips}) splitDomainsAndIps(
  List<String> entries,
) {
  final domains = <String>[];
  final ips = <String>[];
  for (final raw in entries) {
    final v = raw.trim();
    if (v.isEmpty) continue;
    if (v.toLowerCase().startsWith('geoip:')) {
      ips.add(v);
      continue;
    }
    if (looksLikeIpOrCidr(v)) {
      ips.add(v);
      continue;
    }
    domains.add(v);
  }
  return (domains: domains, ips: ips);
}

({List<String> plainIps, List<String> geoipCodes}) splitGeoipTokens(
  List<String> ips,
) {
  final plainIps = <String>[];
  final geoipCodes = <String>[];
  for (final raw in ips) {
    final v = raw.trim();
    if (v.isEmpty) continue;
    final lower = v.toLowerCase();
    if (lower.startsWith('geoip:')) {
      final code = v.substring('geoip:'.length).trim();
      if (code.isNotEmpty) geoipCodes.add(code);
      continue;
    }
    plainIps.add(v);
  }
  return (plainIps: plainIps, geoipCodes: geoipCodes);
}
