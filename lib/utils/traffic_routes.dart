import '../models/app_settings.dart';
import '../models/routing_rule.dart';
import '../models/traffic_route.dart';
import 'routing_presets.dart';
import 'rule_lists.dart';

// порядок разделов это порядок проверки в ядре: блокировка везде, отдельные приложения раньше общих
enum RouteSection { block, apps, allApps }

RouteSection sectionOf(TrafficRoute route) {
  if (route.target == RouteTarget.block) return RouteSection.block;
  return route.allApps ? RouteSection.allApps : RouteSection.apps;
}

// у приложений сайты и списки выше всего трафика: Chrome YouTube на Германию решает раньше Chrome всё на Нидерланды.
// у всех приложений напрямую, другой сервер, через VPN, как стояли прежние списки, чтобы у обновившихся ничего не переставилось
List<TrafficRoute> routesIn(RouteSection section, List<TrafficRoute> routes) {
  final inSection = [
    for (final r in routes)
      if (sectionOf(r) == section) r,
  ];
  if (section == RouteSection.allApps) return _allAppsOrder(inSection);
  int rank(TrafficRoute r) => switch (section) {
        RouteSection.apps => r.content == RouteContent.allTraffic ? 1 : 0,
        _ => 0,
      };
  // List.sort устойчивость не обещает, поэтому ступени собираются по очереди
  final ranks = {for (final r in inSection) rank(r)}.toList()..sort();
  return [
    for (final k in ranks)
      for (final r in inSection)
        if (rank(r) == k) r,
  ];
}

int _targetRank(TrafficRoute r) => switch (r.target) {
      RouteTarget.direct => 0,
      RouteTarget.server => 1,
      _ => 2,
    };

// перетащенные стоят по своим местам, остальные встают за последним маршрутом своей цели или целей выше.
// без единого места это прежняя сортировка по цели
List<TrafficRoute> _allAppsOrder(List<TrafficRoute> inSection) {
  final placed = [
    for (final r in inSection)
      if (r.order != null) r,
  ];
  final out = <TrafficRoute>[];
  for (final place in {for (final r in placed) r.order!}.toList()..sort()) {
    out.addAll(placed.where((r) => r.order == place));
  }
  for (final r in inSection) {
    if (r.order != null) continue;
    final after = out.lastIndexWhere((o) => _targetRank(o) <= _targetRank(r));
    out.insert(after + 1, r);
  }
  return out;
}

bool routesHaveOwnOrder(List<TrafficRoute> routes) => routes.any(
      (r) => r.order != null && sectionOf(r) == RouteSection.allApps,
    );

// места получают все маршруты раздела: с одним местом у перетащенного соседи остались бы стоять по цели
List<TrafficRoute> withAllAppsMoved(
  List<TrafficRoute> routes,
  int from,
  int to,
) {
  final shown = routesIn(RouteSection.allApps, routes);
  if (from < 0 || from >= shown.length) return routes;
  final moved = [...shown];
  moved.insert(to.clamp(0, shown.length - 1), moved.removeAt(from));
  final place = {for (var i = 0; i < moved.length; i++) moved[i].id: i};
  return [
    for (final r in routes)
      place.containsKey(r.id) ? r.copyWith(order: place[r.id]) : r,
  ];
}

List<TrafficRoute> orderedRoutes(List<TrafficRoute> routes) => [
      for (final s in RouteSection.values) ...routesIn(s, routes),
    ];

RoutingPreset? presetById(String id) {
  for (final p in RoutingPresets.all) {
    if (p.id == id) return p;
  }
  return null;
}

// пусто у всего трафика и у пресета, которого больше нет
String routeEntriesText(TrafficRoute route) => switch (route.content) {
      RouteContent.sites => route.sites,
      RouteContent.preset => (presetById(route.presetId)?.values ?? const [])
          .join(', '),
      RouteContent.allTraffic => '',
    };

const _runetZones = {'ru', 'su', 'рф', 'xn--p1ai'};

bool routeSendsRunetDirect(TrafficRoute route) {
  if (route.target != RouteTarget.direct) return false;
  for (final entry in routingEntries(routeEntriesText(route))) {
    var v = entry.toLowerCase();
    if (v == 'geosite:category-ru' || v == 'geoip:ru') return true;
    if (v.startsWith('domain:')) v = v.substring('domain:'.length);
    if (v.startsWith('.')) v = v.substring(1);
    if (_runetZones.contains(v)) return true;
  }
  return false;
}

bool routeIsEmpty(TrafficRoute route) =>
    route.content != RouteContent.allTraffic &&
    routingEntries(routeEntriesText(route)).isEmpty;

// null, если набранное не порты: 0, больше 65535, перевёрнутый диапазон, буквы. пусто значит все порты
List<(int, int)>? routePortRanges(String text) {
  final out = <(int, int)>[];
  for (final part in text.split(RegExp(r'[\s,;/]+'))) {
    if (part.isEmpty) continue;
    final m = RegExp(r'^(\d{1,5})(?:-(\d{1,5}))?$').firstMatch(part);
    if (m == null) return null;
    final from = int.parse(m.group(1)!);
    final to = int.parse(m.group(2) ?? m.group(1)!);
    if (from < 1 || to > 65535 || from > to) return null;
    out.add((from, to));
  }
  return out;
}

bool routeHasProtocol(TrafficRoute route) =>
    route.network != RouteNetwork.any || route.ports.trim().isNotEmpty;

// маршрут с протоколом в общие списки не сворачивается: там у правила нет ни сети, ни порта
bool _foldable(TrafficRoute route) =>
    route.enabled && route.allApps && !routeHasProtocol(route);

// маршруты отдельных приложений сюда не попадают: в общих списках их сайты достались бы всем.
// не едет на свой сервер, значит через VPN: связь важнее, причину покажет карточка.
// при своём порядке сворачивается только блокировка: у трёх списков порядок один, остальные едут правилами (routeProtocolRules)
AppSettings foldRoutes(
  AppSettings settings,
  List<TrafficRoute> routes, {
  bool Function(TrafficRoute route) serverUsable = _never,
}) {
  final direct = <String>[];
  final proxy = <String>[];
  final blocked = <String>[];
  final ownOrder = routesHaveOwnOrder(routes);
  for (final route in orderedRoutes(routes)) {
    if (!_foldable(route)) continue;
    if (ownOrder && route.target != RouteTarget.block) continue;
    final text = routeEntriesText(route).trim();
    if (text.isEmpty) continue;
    switch (route.target) {
      case RouteTarget.direct:
        direct.add(text);
      case RouteTarget.block:
        blocked.add(text);
      case RouteTarget.vpn:
        proxy.add(text);
      case RouteTarget.server:
        if (!serverUsable(route)) proxy.add(text);
    }
  }
  return settings.copyWith(
    directRules: direct.join('\n'),
    proxyRules: proxy.join('\n'),
    blockedRules: blocked.join('\n'),
  );
}

bool _never(TrafficRoute _) => false;

List<String> routeListUrls(List<TrafficRoute> routes) => {
      for (final r in routes)
        if (r.content == RouteContent.sites) ...ruleListUrls(r.sites),
    }.toList();

// правило по процессу становится маршрутом, но выключенным: раньше такие правила не применялись нигде,
// и включить их молча значило бы поменять маршрутизацию при обновлении
List<TrafficRoute> routesFromLegacy(
  AppSettings settings,
  List<RoutingRule> rules, {
  String Function()? newId,
}) {
  TrafficRoute make({
    List<String> apps = const [],
    RouteContent content = RouteContent.sites,
    String sites = '',
    required RouteTarget target,
    bool enabled = true,
  }) {
    final fresh = TrafficRoute.create(
      apps: apps,
      content: content,
      sites: sites,
      target: target,
      enabled: enabled,
    );
    if (newId == null) return fresh;
    return TrafficRoute(
      id: newId(),
      enabled: fresh.enabled,
      apps: fresh.apps,
      content: fresh.content,
      sites: fresh.sites,
      target: fresh.target,
    );
  }

  RouteTarget targetOf(RuleAction a) => switch (a) {
        RuleAction.direct => RouteTarget.direct,
        RuleAction.proxy => RouteTarget.vpn,
        RuleAction.block => RouteTarget.block,
      };

  final routes = <TrafficRoute>[
    for (final (text, target) in [
      (settings.blockedRules, RouteTarget.block),
      (settings.directRules, RouteTarget.direct),
      (settings.proxyRules, RouteTarget.vpn),
    ])
      if (routingEntries(text).isNotEmpty)
        make(sites: text.trim(), target: target),
  ];

  for (final rule in rules) {
    final values = [
      for (final v in rule.values)
        if (v.trim().isNotEmpty) v.trim(),
    ];
    if (values.isEmpty) continue;
    if (rule.type == RuleType.processName) {
      routes.add(make(
        apps: values,
        content: RouteContent.allTraffic,
        target: targetOf(rule.action),
        enabled: false,
      ));
      continue;
    }
    final tokens = switch (rule.type) {
      RuleType.geoip => [
          for (final v in values)
            v.toLowerCase().startsWith('geoip:') ? v : 'geoip:$v',
        ],
      RuleType.geosite => [
          for (final v in values)
            v.toLowerCase().startsWith('geosite:') ? v : 'geosite:$v',
        ],
      _ => values,
    };
    routes.add(make(
      sites: tokens.join(', '),
      target: targetOf(rule.action),
      enabled: rule.enabled,
    ));
  }
  return routes;
}

// нетронутые значения по умолчанию подсказки не стоят
bool legacyRoutingCustomized(AppSettings settings, List<RoutingRule> rules) =>
    rules.isNotEmpty ||
    settings.directRules.trim() != RoutingPresets.defaultDirectRules ||
    settings.proxyRules.trim() != RoutingPresets.defaultProxyRules ||
    settings.blockedRules.trim() != RoutingPresets.defaultBlockedRules;
