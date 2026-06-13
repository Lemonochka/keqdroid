// Routing lists are now mixed: a single field may contain domains, IP/CIDR
// ranges and prefixed rules (geosite:/geoip:/full:/regexp:). This helper splits
// a parsed list into the domain-shaped tokens and the ip-shaped tokens so the
// xray / sing-box config generators can emit the right rule kind for each.

final _ipV4 = RegExp(r'^(\d{1,3}\.){3}\d{1,3}(/\d{1,2})?$');
final _ipV6 = RegExp(r'^[0-9a-fA-F:]+(/\d{1,3})?$');

/// True for an IPv4/IPv6 address or CIDR range.
bool looksLikeIpOrCidr(String value) {
  final v = value.trim();
  if (v.isEmpty) return false;
  if (_ipV4.hasMatch(v)) return true;
  // ipv6 must contain a colon to avoid matching bare hostnames/labels.
  if (v.contains(':') && _ipV6.hasMatch(v)) return true;
  return false;
}

/// Splits raw routing entries into domain-shaped and ip-shaped tokens.
///
/// - `geoip:*` tokens go to [ips] (xray matches them as ip rules).
/// - IPv4/IPv6 addresses and CIDR ranges go to [ips].
/// - everything else (bare hosts, `.suffix`, `domain:`/`full:`/`regexp:`/
///   `geosite:`) goes to [domains] and is normalized downstream.
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
