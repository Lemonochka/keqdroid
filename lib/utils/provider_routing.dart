import 'dart:convert';

import '../models/app_settings.dart';
import '../models/traffic_route.dart';
import 'rule_lists.dart';
import 'traffic_routes.dart';

// профиль Happ: ссылка <схема>://routing/add|onadd/<base64 json> или routing/off, тот же формат у Incy и у нас.
// v2RayTun шлёт в заголовке routing правила xray в base64
sealed class ProviderRouting {
  const ProviderRouting();
}

final class ProviderRoutingOff extends ProviderRouting {
  const ProviderRoutingOff();
}

final class ProviderRoutingRules extends ProviderRouting {
  const ProviderRoutingRules({
    required this.name,
    required this.finalOutbound,
    required this.routes,
  });

  final String? name;
  final String finalOutbound;
  final List<TrafficRoute> routes;
}

final _link = RegExp(
  r'^(?:happ|incy|keqdroid|keqdis)://routing/(add|onadd|off)(?:/(.*))?$',
  caseSensitive: false,
  dotAll: true,
);

final _linkInText = RegExp(
  r'(?<![A-Za-z0-9+.\-])(?:happ|incy|keqdroid|keqdis)://routing/(?:off\b|(?:add|onadd)/[A-Za-z0-9+/=_%\-]+)',
  caseSensitive: false,
);

bool isRoutingLink(String raw) => _link.hasMatch(raw.trim());

ProviderRouting? parseProviderRouting(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  final link = _link.firstMatch(value);
  if (link != null) {
    if (link.group(1)!.toLowerCase() == 'off') return const ProviderRoutingOff();
    final json = _decodeObject(link.group(2) ?? '');
    return json == null ? null : _fromObject(json);
  }
  final json = value.startsWith('{') ? _jsonObject(value) : _decodeObject(value);
  return json == null ? null : _fromObject(json);
}

// Happ берёт ссылку из тела подписки как есть, а тело бывает целиком в base64
ProviderRouting? providerRoutingInBody(String body) {
  final decoded = _decodeText(body.trim());
  for (final text in [body, ?decoded]) {
    for (final m in _linkInText.allMatches(text)) {
      final parsed = parseProviderRouting(m.group(0)!);
      if (parsed != null) return parsed;
    }
  }
  return null;
}

// у 3X-UI выключенная маршрутизация приходит заголовком Routing-Enable: 0, правила рядом могут остаться
ProviderRouting? providerRoutingFromHeaders(
  String? Function(String name) header,
) {
  final enable = header('routing-enable')?.trim().toLowerCase();
  if (enable == '0' || enable == 'false') return const ProviderRoutingOff();
  final value = header('routing');
  return value == null ? null : parseProviderRouting(value);
}

ProviderRouting? _fromObject(Map<String, dynamic> json) {
  if (json['rules'] is List) return _fromXrayRouting(json);
  const happKeys = {
    'Name',
    'GlobalProxy',
    'DirectSites',
    'DirectIp',
    'ProxySites',
    'ProxyIp',
    'BlockSites',
    'BlockIp',
  };
  if (!json.keys.any(happKeys.contains)) return null;

  List<String> list(String key) => [
        for (final e in (json[key] is List ? json[key] as List : const []))
          if (e is String) e,
      ];
  TrafficRoute? route(String id, RouteTarget target, String sites, String ip) {
    final entries = [
      for (final e in [...list(sites), ...list(ip)]) ?_entry(e),
    ];
    if (entries.isEmpty) return null;
    return TrafficRoute(id: id, sites: entries.join('\n'), target: target);
  }

  // DNS, свои geo-базы, FakeDNS и DomainStrategy у нас общие на приложение, в профиль не ложатся.
  // RouteOrder тоже: порядок наш, блок, напрямую, через VPN, совпадает с порядком Happ по умолчанию
  return ProviderRoutingRules(
    name: _name(json['Name']),
    finalOutbound: _isFalse(json['GlobalProxy'])
        ? AppSettings.finalOutboundDirect
        : AppSettings.finalOutboundProxy,
    routes: [
      ?route('provider-block', RouteTarget.block, 'BlockSites', 'BlockIp'),
      ?route('provider-direct', RouteTarget.direct, 'DirectSites', 'DirectIp'),
      ?route('provider-proxy', RouteTarget.vpn, 'ProxySites', 'ProxyIp'),
    ],
  );
}

// правило с портом, протоколом, процессом и прочим не записать маршрутом: расширять его опаснее, чем пропустить
const _xrayRuleKeys = {
  'type',
  'domain',
  'ip',
  'outboundTag',
  'network',
  'enabled',
  'id',
  '__name__',
  'remarks',
  'ruleTag',
};

ProviderRouting _fromXrayRouting(Map<String, dynamic> json) {
  final routes = <TrafficRoute>[];
  var finalOutbound = AppSettings.finalOutboundProxy;
  final rules = json['rules'] as List;
  for (var i = 0; i < rules.length; i++) {
    final rule = rules[i];
    if (rule is! Map<String, dynamic>) continue;
    if (rule['enabled'] == false) continue;
    if (!rule.keys.every(_xrayRuleKeys.contains)) continue;
    final target = switch (rule['outboundTag']) {
      'direct' => RouteTarget.direct,
      'proxy' => RouteTarget.vpn,
      'block' => RouteTarget.block,
      _ => null,
    };
    if (target == null) continue;
    final network = '${rule['network'] ?? 'tcp,udp'}'.toLowerCase();
    if (!network.contains('tcp') || !network.contains('udp')) continue;
    final entries = [
      for (final key in const ['domain', 'ip'])
        for (final e in (rule[key] is List ? rule[key] as List : const []))
          if (e is String) ?_entry(e),
    ];
    if (entries.isEmpty) {
      // правило на весь трафик: всё, что ниже, xray уже не увидит
      finalOutbound = switch (target) {
        RouteTarget.direct => AppSettings.finalOutboundDirect,
        RouteTarget.block => AppSettings.finalOutboundBlock,
        _ => AppSettings.finalOutboundProxy,
      };
      break;
    }
    routes.add(TrafficRoute(
      id: 'provider-$i',
      sites: entries.join('\n'),
      target: target,
    ));
  }
  return ProviderRoutingRules(
    name: _name(json['name']),
    finalOutbound: finalOutbound,
    routes: routes,
  );
}

// keyword: наши генераторы не знают, а regexp без якорей ловит то же. ext: ссылается на чужие .dat, ссылки на
// списки качались бы через туннель по воле провайдера
String? _entry(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return null;
  final lower = v.toLowerCase();
  if (lower.startsWith('keyword:')) {
    final word = v.substring('keyword:'.length).trim();
    return word.isEmpty ? null : 'regexp:${RegExp.escape(word)}';
  }
  if (lower.startsWith('ext:') ||
      lower.startsWith('ext-domain:') ||
      lower.startsWith('ext-ip:') ||
      lower.startsWith('dotless:') ||
      lower.startsWith('http://') ||
      lower.startsWith('https://')) {
    return null;
  }
  return v;
}

String? _name(Object? raw) {
  final name = raw is String ? raw.trim() : '';
  return name.isEmpty ? null : name;
}

bool _isFalse(Object? raw) =>
    raw == false || (raw is String && raw.trim().toLowerCase() == 'false');

Map<String, dynamic>? _decodeObject(String payload) {
  var text = payload.trim();
  if (text.contains('%')) {
    try {
      text = Uri.decodeComponent(text);
    } on FormatException {
      return null;
    }
  }
  final decoded = _decodeText(text);
  return decoded == null ? null : _jsonObject(decoded);
}

Map<String, dynamic>? _jsonObject(String text) {
  try {
    final json = jsonDecode(text);
    return json is Map<String, dynamic> ? json : null;
  } on FormatException {
    return null;
  }
}

String? _decodeText(String input) {
  final compact = input
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll('-', '+')
      .replaceAll('_', '/');
  if (compact.isEmpty) return null;
  final padded = switch (compact.length % 4) {
    2 => '$compact==',
    3 => '$compact=',
    _ => compact,
  };
  try {
    return const Utf8Decoder().convert(base64.decode(base64.normalize(padded)));
  } on Object {
    return null;
  }
}

final _ipEntry = RegExp(
  r'^(geoip:|\d{1,3}(\.\d{1,3}){3}(/\d{1,2})?$|[0-9a-f]*:[0-9a-f:]+(/\d{1,3})?$)',
  caseSensitive: false,
);

// формат Happ не передаёт маршрут по приложениям, через другой сервер, список по ссылке и остальное в блок: они в skipped.
// записи отсеиваются те же, что выбросит разбор у получателя
({String link, int skipped}) routingLinkOf({
  required String name,
  required String finalOutbound,
  required List<TrafficRoute> routes,
}) {
  final sites = <RouteTarget, List<String>>{};
  final ips = <RouteTarget, List<String>>{};
  var skipped = finalOutbound == AppSettings.finalOutboundBlock ? 1 : 0;
  for (final route in routes) {
    if (!route.enabled) continue;
    // протокола в этом формате нет: блок QUIC у YouTube уехал бы блоком всего YouTube
    final all = route.allApps &&
            route.target != RouteTarget.server &&
            !routeHasProtocol(route)
        ? routingEntries(routeEntriesText(route))
        : const <String>[];
    final kept = [for (final e in all) if (_entry(e) != null) e];
    if (kept.isEmpty || kept.length < all.length) skipped++;
    for (final e in kept) {
      (_ipEntry.hasMatch(e) ? ips : sites).putIfAbsent(route.target, () => []).add(e);
    }
  }
  List<String> of(Map<RouteTarget, List<String>> m, RouteTarget t) => m[t] ?? const [];
  final json = {
    'Name': name,
    'GlobalProxy':
        finalOutbound == AppSettings.finalOutboundDirect ? 'false' : 'true',
    'BlockSites': of(sites, RouteTarget.block),
    'BlockIp': of(ips, RouteTarget.block),
    'DirectSites': of(sites, RouteTarget.direct),
    'DirectIp': of(ips, RouteTarget.direct),
    'ProxySites': of(sites, RouteTarget.vpn),
    'ProxyIp': of(ips, RouteTarget.vpn),
  };
  return (
    link: 'keqdroid://routing/add/${base64.encode(utf8.encode(jsonEncode(json)))}',
    skipped: skipped,
  );
}
