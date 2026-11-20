// Куда xray отправит соединение: первое совпавшее правило, а при
// IPIfNonMatch второй проход с адресом из резолва, как pickRouteInternal в
// app/router/router.go. Понимает поля, которые пишут наши генераторы;
// geosite и geoip не совпадают никогда.
library;

import 'dart:io' show InternetAddress;

class XrayConn {
  const XrayConn({
    this.inbound = 'tun-in',
    this.process = '',
    this.host = '',
    this.ip = '',
    this.resolvesTo = '',
    this.port = 443,
    this.network = 'tcp',
  });

  final String inbound;
  final String process;
  final String host;
  final String ip;
  final String resolvesTo;
  final int port;
  final String network;
}

/// Тег выхода первого совпавшего правила; ни одно не совпало — первый выход,
/// как default route у ядра.
String? simulateXray(Map<String, dynamic> config, XrayConn conn) {
  final fallback = ((config['outbounds'] as List).first as Map)['tag'] as String?;
  final routing = config['routing'] as Map;
  final rules = [
    for (final r in routing['rules'] as List) (r as Map).cast<String, dynamic>(),
  ];
  for (final rule in rules) {
    if (_matches(rule, conn, conn.ip)) return rule['outboundTag'] as String?;
  }
  final strategy = routing['domainStrategy'] ?? 'AsIs';
  if (strategy != 'IPIfNonMatch' || conn.host.isEmpty) return fallback;
  for (final rule in rules) {
    if (_matches(rule, conn, conn.resolvesTo)) return rule['outboundTag'] as String?;
  }
  return fallback;
}

bool _matches(Map<String, dynamic> rule, XrayConn conn, String ip) {
  final known = {
    'type', 'ruleTag', 'outboundTag', 'inboundTag', 'network', 'port',
    'domain', 'ip', 'process', 'source',
  };
  for (final key in rule.keys) {
    if (!known.contains(key)) {
      throw UnsupportedError('симулятор не знает поля $key');
    }
  }
  if (rule['inboundTag'] case final List<Object?> tags when !tags.contains(conn.inbound)) {
    return false;
  }
  if (rule['source'] != null) return false;
  if (rule['network'] case final String n
      when !n.split(',').map((e) => e.trim()).contains(conn.network)) {
    return false;
  }
  if (rule['port'] case final Object p when !_portMatches('$p', conn.port)) {
    return false;
  }
  if (rule['ip'] case final List<Object?> ips
      when ip.isEmpty || !ips.any((e) => _ipMatches('$e', ip))) {
    return false;
  }
  if (rule['domain'] case final List<Object?> domains
      when conn.host.isEmpty || !domains.any((e) => _domainMatches('$e', conn.host))) {
    return false;
  }
  if (rule['process'] case final List<Object?> names when !names.contains(conn.process)) {
    return false;
  }
  return true;
}

bool _portMatches(String spec, int port) {
  for (final part in spec.split(',')) {
    final range = part.trim().split('-');
    final lo = int.parse(range.first);
    final hi = int.parse(range.last);
    if (port >= lo && port <= hi) return true;
  }
  return false;
}

bool _domainMatches(String rule, String host) {
  final h = host.toLowerCase();
  if (rule.startsWith('geosite:')) return false;
  if (rule.startsWith('regexp:')) return RegExp(rule.substring(7)).hasMatch(h);
  if (rule.startsWith('full:')) return h == rule.substring(5).toLowerCase();
  if (rule.startsWith('domain:')) {
    final d = rule.substring(7).toLowerCase();
    return h == d || h.endsWith('.$d');
  }
  if (rule.startsWith('keyword:')) return h.contains(rule.substring(8));
  return h.contains(rule.toLowerCase());
}

bool _ipMatches(String rule, String ip) {
  if (rule.startsWith('geoip:')) return false;
  final slash = rule.indexOf('/');
  final net = InternetAddress.tryParse(slash < 0 ? rule : rule.substring(0, slash));
  final addr = InternetAddress.tryParse(ip);
  if (net == null || addr == null || net.type != addr.type) return false;
  final bits = slash < 0 ? net.rawAddress.length * 8 : int.parse(rule.substring(slash + 1));
  for (var i = 0; i < bits; i++) {
    final mask = 0x80 >> (i % 8);
    if ((addr.rawAddress[i ~/ 8] & mask) != (net.rawAddress[i ~/ 8] & mask)) {
      return false;
    }
  }
  return true;
}
