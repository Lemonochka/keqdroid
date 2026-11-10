import '../models/traffic_route.dart';
import '../tunnel/connection_mode.dart';
import 'process_name_utils.dart';
import 'route_servers.dart';
import 'split_tunneling_entries.dart';
import 'traffic_routes.dart';

// одно правило на экран и на подключение. владельца соединения ядро узнаёт только у своего туннеля
bool appRoutesRun(ConnectionMode mode) => mode == ConnectionMode.tun;

class RouteAppRules {
  const RouteAppRules({
    required this.tag,
    required this.apps,
    required this.target,
    this.serverTag = '',
    this.allTraffic = false,
    this.entries = '',
    this.listDomains = const [],
    this.network = RouteNetwork.any,
    this.ports = const [],
    this.ownOrder = false,
  });

  final String tag;

  // пусто у маршрута всех приложений (routeProtocolRules): ни TUN, ни поиска процесса ему не надо
  final List<String> apps;

  final RouteTarget target;

  // пусто, если выхода нет (сервер пропал, совпал с активным, не встаёт в ядро): тогда через VPN
  final String serverTag;

  final bool allTraffic;

  final String entries;

  final List<String> listDomains;

  final RouteNetwork network;

  final List<(int, int)> ports;

  // генератор ставит такое правило по месту в списке, а не на ступень его цели
  final bool ownOrder;

  bool get forAllApps => apps.isEmpty;

  bool get hasProtocol => network != RouteNetwork.any || ports.isNotEmpty;

  RouteAppRules copyWith({String? entries, List<String>? listDomains}) =>
      RouteAppRules(
        tag: tag,
        apps: apps,
        target: target,
        serverTag: serverTag,
        allTraffic: allTraffic,
        entries: entries ?? this.entries,
        listDomains: listDomains ?? this.listDomains,
        network: network,
        ports: ports,
        ownOrder: ownOrder,
      );
}

// маршрут всех приложений, который едет своим правилом, а не в трёх списках: с протоколом, а при своём
// порядке любой, кроме блокировки. с неверными портами в ядро не идёт: ошибку показывает его карточка
List<RouteAppRules> routeProtocolRules({
  required List<TrafficRoute> routes,
  required List<RouteServerOutbound> outbounds,
}) {
  final tagOf = {for (final o in outbounds) o.serverId: o.tag};
  final ownOrder = routesHaveOwnOrder(routes);
  final out = <RouteAppRules>[];
  for (final route in orderedRoutes(routes)) {
    if (!route.enabled || !route.allApps) continue;
    final placed = ownOrder && route.target != RouteTarget.block;
    if (!placed && !routeHasProtocol(route)) continue;
    final ports = routePortRanges(route.ports);
    if (ports == null || routeIsEmpty(route)) continue;
    final allTraffic = route.content == RouteContent.allTraffic;
    // весь трафик без протокола это строка «Всё остальное», маршрутом он ничего не значит
    if (allTraffic && !routeHasProtocol(route)) continue;
    out.add(RouteAppRules(
      tag: routeHasProtocol(route)
          ? 'keq-proto-${out.length}'
          : 'keq-route-${out.length}',
      apps: const [],
      target: route.target,
      serverTag: route.target == RouteTarget.server
          ? tagOf[route.serverId] ?? ''
          : '',
      allTraffic: allTraffic,
      entries: routeEntriesText(route).trim(),
      network: route.network,
      ports: ports,
      ownOrder: placed,
    ));
  }
  return out;
}

List<RouteAppRules> routeAppRules({
  required List<TrafficRoute> routes,
  required List<RouteServerOutbound> outbounds,
  bool? windows,
}) {
  final tagOf = {for (final o in outbounds) o.serverId: o.tag};
  final out = <RouteAppRules>[];
  for (final route in orderedRoutes(routes)) {
    if (!route.enabled || route.allApps || routeIsEmpty(route)) continue;
    final ports = routePortRanges(route.ports);
    if (ports == null) continue;
    // повторы без учёта регистра: так сравнивает и ядро
    final seen = <String>{};
    final apps = [
      for (final app in route.apps)
        if (isProcessPathEntry(app))
          normalizeProcessPath(app, windows: windows)
        else
          normalizeProcessName(app, windows: windows),
    ].where((e) => e.isNotEmpty && seen.add(e.toLowerCase())).toList();
    if (apps.isEmpty) continue;
    out.add(RouteAppRules(
      tag: 'keq-app-${out.length}',
      apps: apps,
      target: route.target,
      serverTag: route.target == RouteTarget.server
          ? tagOf[route.serverId] ?? ''
          : '',
      allTraffic: route.content == RouteContent.allTraffic,
      entries: routeEntriesText(route).trim(),
      network: route.network,
      ports: ports,
    ));
  }
  return out;
}

// сомнение в пользу маршрута: имя без пути при только выбранных с путём того же имени считается пропущенным
List<String> appsOutsideSplit(
  List<String> apps, {
  required Set<String> include,
  required Set<String> exclude,
  bool? windows,
}) {
  if (include.isNotEmpty) {
    final selection = SplitSelection(include, windows: windows);
    final names = {for (final e in include) splitNameKey(e, windows: windows)};
    return [
      for (final app in apps)
        if (!selection.covers(splitStubForEntry(app, windows: windows)) &&
            (isProcessPathEntry(app) ||
                !names.contains(splitNameKey(app, windows: windows))))
          app,
    ];
  }
  if (exclude.isNotEmpty) {
    final selection = SplitSelection(exclude, windows: windows);
    return [
      for (final app in apps)
        if (selection.covers(splitStubForEntry(app, windows: windows))) app,
    ];
  }
  return const [];
}
