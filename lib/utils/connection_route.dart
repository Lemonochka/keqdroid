import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../models/connection_entry.dart';
import '../models/traffic_route.dart';
import '../services/xray_access_log_parser.dart';
import 'app_routes.dart';
import 'geo_asset_index.dart';
import 'geo_dat_reader.dart';
import 'process_name_utils.dart';
import 'routing_entry.dart';
import 'routing_presets.dart';
import 'rule_lists.dart';
import 'traffic_routes.dart';

enum ListMatch { hit, miss, unknown }

abstract interface class GeoLookup {
  // null, если кода нет в базе
  bool? siteHas(String code, String domain);
  bool? ipIn(String code, String ip);
}

sealed class RouteExplanation {
  const RouteExplanation();
}

final class ByRoute extends RouteExplanation {
  const ByRoute(this.route);
  final TrafficRoute route;
}

final class ByFinal extends RouteExplanation {
  const ByFinal();
}

final class Unexplained extends RouteExplanation {
  const Unexplained();
}

class ConnectionTarget {
  ConnectionTarget._(this.domain, this.ip);

  factory ConnectionTarget.of(ConnectionEntry entry) {
    final host = entry.host.trim().toLowerCase();
    final hostIsIp = InternetAddress.tryParse(host) != null;
    final ip = entry.destIp.isNotEmpty
        ? entry.destIp
        : hostIsIp
        ? host
        : null;
    final domain = hostIsIp || host.isEmpty
        ? null
        : host.endsWith('.')
        ? host.substring(0, host.length - 1)
        : host;
    return ConnectionTarget._(domain, ip);
  }

  final String? domain;
  final String? ip;
}

bool? matchToken(String token, ConnectionTarget target, GeoLookup geo) {
  final raw = token.trim();
  final lower = raw.toLowerCase();
  if (lower.isEmpty) return false;
  final domain = target.domain;
  final ip = target.ip;
  if (lower.startsWith('geosite:')) {
    if (domain == null) return false;
    return geo.siteHas(lower.substring('geosite:'.length).trim(), domain);
  }
  if (lower.startsWith('geoip:')) {
    if (ip == null) return false;
    return geo.ipIn(lower.substring('geoip:'.length).trim(), ip);
  }
  if (looksLikeIpOrCidr(raw)) return ip != null && ipInCidr(ip, raw);
  // содержимое списка по ссылке здесь не читается
  if (isRuleListUrl(raw)) return null;
  if (domain == null) return false;
  if (lower.startsWith('full:')) return domain == lower.substring(5);
  if (lower.startsWith('regexp:')) {
    try {
      return RegExp(raw.substring(7)).hasMatch(domain);
    } on FormatException {
      return false;
    }
  }
  if (lower.startsWith('keyword:')) return domain.contains(lower.substring(8));
  var suffix = lower;
  if (suffix.startsWith('domain:')) suffix = suffix.substring(7);
  if (suffix.startsWith('*.')) suffix = suffix.substring(2);
  if (suffix.startsWith('.')) suffix = suffix.substring(1);
  return domain == suffix || domain.endsWith('.$suffix');
}

ListMatch matchTokens(
  Iterable<String> tokens,
  ConnectionTarget target,
  GeoLookup geo,
) {
  var unknown = false;
  for (final token in tokens) {
    switch (matchToken(token, target, geo)) {
      case true:
        return ListMatch.hit;
      case null:
        unknown = true;
      case false:
    }
  }
  return unknown ? ListMatch.unknown : ListMatch.miss;
}

bool ipInCidr(String ip, String cidr) {
  final slash = cidr.indexOf('/');
  final base = InternetAddress.tryParse(
    (slash < 0 ? cidr : cidr.substring(0, slash)).trim(),
  );
  final addr = InternetAddress.tryParse(ip.trim());
  if (base == null || addr == null || base.type != addr.type) return false;
  final a = addr.rawAddress;
  final b = base.rawAddress;
  final bits = slash < 0
      ? a.length * 8
      : int.tryParse(cidr.substring(slash + 1).trim()) ?? -1;
  if (bits < 0 || bits > a.length * 8) return false;
  for (var i = 0; i < bits; i++) {
    final mask = 0x80 >> (i % 8);
    if ((a[i ~/ 8] & mask) != (b[i ~/ 8] & mask)) return false;
  }
  return true;
}

// приложения маршрута: пакет на Android, имя или путь процесса на ПК. null, если владельца не знаем
bool? routeAppsMatch(
  List<String> apps, {
  required String process,
  Set<String> packages = const {},
  bool? windows,
}) {
  if (process.trim().isEmpty) return null;
  final name = normalizeProcessName(process, windows: windows).toLowerCase();
  final path = normalizeProcessPath(process, windows: windows).toLowerCase();
  for (final app in apps) {
    final a = app.trim();
    if (a.isEmpty) continue;
    final lower = a.toLowerCase();
    if (packages.any((p) => p.toLowerCase() == lower)) return true;
    if (isProcessPathEntry(a)) {
      if (normalizeProcessPath(a, windows: windows).toLowerCase() == path) {
        return true;
      }
    } else if (normalizeProcessName(a, windows: windows).toLowerCase() ==
        name) {
      return true;
    }
  }
  return false;
}

final _generatedTag = RegExp(r'keq-(route|proto|app)-(\d+)');
final _xraySiteRule = RegExp(r'^user-(direct|proxy|block)-');
final _clashRule = RegExp(r'^([A-Za-z0-9-]+)(?:\((.*)\))?$');
const _clashSiteRules = {
  'geosite',
  'domainsuffix',
  'domain',
  'domainkeyword',
  'domainregex',
  'geoip',
  'ipcidr',
  'ipcidr6',
  'ruleset',
  'subrules',
  'and',
  'or',
};

bool _targetAgrees(RouteTarget target, ConnectionVerdict verdict) =>
    switch (verdict) {
      ConnectionVerdict.direct => target == RouteTarget.direct,
      ConnectionVerdict.blocked => target == RouteTarget.block,
      ConnectionVerdict.proxied =>
        target == RouteTarget.vpn || target == RouteTarget.server,
      _ => false,
    };

bool _protocolAgrees(TrafficRoute route, ConnectionEntry entry) {
  final network = entry.network.toLowerCase();
  if (route.network == RouteNetwork.tcp && network != 'tcp') return false;
  if (route.network == RouteNetwork.udp && network != 'udp') return false;
  final ports = routePortRanges(route.ports);
  if (ports == null) return false;
  if (ports.isEmpty) return true;
  return ports.any((p) => entry.destPort >= p.$1 && entry.destPort <= p.$2);
}

// тот же разбор, что у генератора: по метке keq-* маршрут находится точно, по остальным по совпадению с адресом
RouteExplanation explainRoute({
  required ConnectionEntry entry,
  required List<TrafficRoute> routes,
  required bool ruleInfoAvailable,
  required GeoLookup geo,
  Map<String, bool?> appMatch = const {},
}) {
  if (entry.decidedByCore) return const Unexplained();
  final rule = entry.rule.trim();

  final tagged = _generatedTag.firstMatch(rule);
  if (tagged != null) {
    final tag = tagged.group(0)!;
    final generated = tagged.group(1) == 'app'
        ? routeAppRules(routes: routes, outbounds: const [])
        : routeProtocolRules(routes: routes, outbounds: const []);
    final id = generated.where((r) => r.tag == tag).firstOrNull?.routeId;
    final route = routes.where((r) => r.id == id).firstOrNull;
    return route == null ? const Unexplained() : ByRoute(route);
  }

  if (XrayAccessLogParser.isDefaultRoute(rule) ||
      (rule.isEmpty && ruleInfoAvailable && entry.outbound.isNotEmpty)) {
    return const ByFinal();
  }

  final clash = _clashRule.firstMatch(rule);
  final clashType = clash?.group(1)?.toLowerCase();
  final siteRule =
      _xraySiteRule.hasMatch(rule) || _clashSiteRules.contains(clashType);
  if (!siteRule) return const Unexplained();

  // у xray списки user-* собраны только из маршрутов всех приложений без протокола (foldRoutes)
  final folded = _xraySiteRule.hasMatch(rule);
  final candidates = [
    for (final route in orderedRoutes(routes))
      if (route.enabled &&
          !routeIsEmpty(route) &&
          _targetAgrees(route.target, entry.verdict) &&
          _protocolAgrees(route, entry) &&
          (route.allApps || appMatch[route.id] == true) &&
          (!folded || (route.allApps && !routeHasProtocol(route))))
        route,
  ];

  final payload = clash?.group(2)?.trim() ?? '';
  final forms = _clashTokenForms(clashType ?? '', payload);
  if (forms.isNotEmpty) {
    for (final route in candidates) {
      final entries = routingEntries(
        routeEntriesText(route),
      ).map((e) => e.trim().toLowerCase());
      if (entries.any(forms.contains)) return ByRoute(route);
    }
  }

  final target = ConnectionTarget.of(entry);
  for (final route in candidates) {
    if (route.content == RouteContent.allTraffic) {
      if (!route.allApps || routeHasProtocol(route)) return ByRoute(route);
      continue;
    }
    final tokens = routingEntries(routeEntriesText(route));
    if (matchTokens(tokens, target, geo) == ListMatch.hit) {
      return ByRoute(route);
    }
  }
  return const Unexplained();
}

// как генератор mihomo записал строку маршрута, так она и вернётся в ответе ядра
Set<String> _clashTokenForms(String type, String payload) {
  final p = payload.toLowerCase();
  if (p.isEmpty) return const {};
  return switch (type) {
    'geosite' => {'geosite:$p'},
    'geoip' => {'geoip:$p'},
    'domainsuffix' => {p, 'domain:$p', '.$p', '*.$p'},
    'domain' => {'full:$p'},
    'domainregex' => {'regexp:$p'},
    'ipcidr' || 'ipcidr6' => {
      p,
      if (p.endsWith('/32')) p.substring(0, p.length - 3),
      if (p.endsWith('/128')) p.substring(0, p.length - 4),
    },
    _ => const {},
  };
}

Map<String, ListMatch> presetMatches(ConnectionTarget target, GeoLookup geo) =>
    {
      for (final preset in RoutingPresets.all)
        preset.id: matchTokens(preset.values, target, geo),
    };

class PreloadedGeoLookup implements GeoLookup {
  PreloadedGeoLookup({
    Map<String, List<GeoDomain>> sites = const {},
    Map<String, List<String>> ips = const {},
  }) : _sites = {
         for (final e in sites.entries) e.key.toLowerCase(): _SiteSet(e.value),
       },
       _ips = {for (final e in ips.entries) e.key.toLowerCase(): e.value};

  final Map<String, _SiteSet> _sites;
  final Map<String, List<String>> _ips;

  @override
  bool? siteHas(String code, String domain) =>
      _sites[code.toLowerCase()]?.has(domain);

  @override
  bool? ipIn(String code, String ip) =>
      _ips[code.toLowerCase()]?.any((c) => ipInCidr(ip, c));

  static Future<PreloadedGeoLookup> load(
    String dir, {
    required Set<String> siteCodes,
    required Set<String> ipCodes,
  }) async {
    Future<Map<String, T>> read<T>(
      File file,
      Set<String> codes,
      T Function(Uint8List body) parse,
    ) async {
      final out = <String, T>{};
      if (codes.isEmpty) return out;
      final records = {
        for (final r in await GeoDatReader.records(file)) r.code: r,
      };
      for (final code in codes) {
        final record = records[code];
        if (record == null) continue;
        final body = await GeoDatReader.bodyAt(file, record);
        if (body != null) out[code] = parse(body);
      }
      return out;
    }

    return PreloadedGeoLookup(
      sites: await read(
        File(GeoAssetIndex.geositePath(dir)),
        siteCodes,
        GeoDatReader.parseDomains,
      ),
      ips: await read(
        File(GeoAssetIndex.geoipPath(dir)),
        ipCodes,
        GeoDatReader.parseCidrs,
      ),
    );
  }
}

({Set<String> sites, Set<String> ips}) geoCodesIn(Iterable<String> tokens) {
  final sites = <String>{};
  final ips = <String>{};
  for (final token in tokens) {
    final lower = token.trim().toLowerCase();
    if (lower.startsWith('geosite:')) {
      sites.add(lower.substring('geosite:'.length).trim());
    } else if (lower.startsWith('geoip:')) {
      ips.add(lower.substring('geoip:'.length).trim());
    }
  }
  return (sites: sites, ips: ips);
}

class _SiteSet {
  _SiteSet(List<GeoDomain> domains) {
    for (final d in domains) {
      final v = d.value.toLowerCase();
      switch (d.type) {
        case GeoDomainType.full:
          _full.add(v);
        case GeoDomainType.domain:
          _suffix.add(v);
        case GeoDomainType.plain:
          _plain.add(v);
        case GeoDomainType.regex:
          try {
            _regex.add(RegExp(d.value));
          } on FormatException {
            // такое правило ядро тоже не примет
          }
      }
    }
  }

  final _full = <String>{};
  final _suffix = <String>{};
  final _plain = <String>[];
  final _regex = <RegExp>[];

  bool has(String domain) {
    if (_full.contains(domain)) return true;
    var rest = domain;
    while (true) {
      if (_suffix.contains(rest)) return true;
      final dot = rest.indexOf('.');
      if (dot < 0) break;
      rest = rest.substring(dot + 1);
    }
    if (_plain.any(domain.contains)) return true;
    return _regex.any((r) => r.hasMatch(domain));
  }
}

class ConnectionInsight {
  const ConnectionInsight({required this.route, required this.lists});

  final RouteExplanation route;
  final Map<String, ListMatch> lists;
}

Future<ConnectionInsight> inspectConnection({
  required ConnectionEntry entry,
  required List<TrafficRoute> routes,
  required bool ruleInfoAvailable,
  required String? geoDir,
  Map<String, bool?> appMatch = const {},
}) =>
    // коды читаются из базы целиком, поэтому в отдельном изоляте и без кэша в памяти приложения
    Isolate.run(() async {
      final codes = geoCodesIn([
        for (final preset in RoutingPresets.all) ...preset.values,
        for (final route in routes)
          if (route.enabled) ...routingEntries(routeEntriesText(route)),
      ]);
      final GeoLookup geo = geoDir == null
          ? const _NoGeo()
          : await PreloadedGeoLookup.load(
              geoDir,
              siteCodes: codes.sites,
              ipCodes: codes.ips,
            );
      return ConnectionInsight(
        route: explainRoute(
          entry: entry,
          routes: routes,
          ruleInfoAvailable: ruleInfoAvailable,
          geo: geo,
          appMatch: appMatch,
        ),
        lists: presetMatches(ConnectionTarget.of(entry), geo),
      );
    });

class _NoGeo implements GeoLookup {
  const _NoGeo();

  @override
  bool? siteHas(String code, String domain) => null;

  @override
  bool? ipIn(String code, String ip) => null;
}
