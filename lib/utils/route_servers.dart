import '../models/server_item.dart';
import '../models/traffic_route.dart';
import '../tunnel/vpn_backend.dart';
import 'custom_clash_config.dart';
import 'custom_xray_config.dart';
import 'proxy_chain.dart';
import 'traffic_routes.dart';
import 'vpn_core_support.dart';

// из готового конфига в маршрут идут только его выходы: правила и DNS автора в чужую сессию не вставить.
// цепочку берёт только mihomo: у xray сервер маршрута из ссылки собирается одним outbound (config_gen.dart)
bool routeServerSupported(String config, VpnBackend core) =>
    switch (detectServerFormat(config)) {
      ServerFormat.link => backendsForLink(config).contains(core),
      ServerFormat.amneziaWg => core == VpnBackend.mihomo,
      ServerFormat.chain => core == VpnBackend.mihomo && _mihomoChain(config),
      ServerFormat.xrayJson => core == VpnBackend.xray &&
          CustomXrayConfig.tryParse(config)?.routeOutbounds(_probeTag) != null,
      ServerFormat.clashYaml => core == VpnBackend.mihomo &&
          CustomClashConfig.tryParse(config)?.routeNodes(_probeTag) != null,
      _ => false,
    };

const _probeTag = 'keq-srv-probe';

bool _mihomoChain(String config) {
  final chain = ProxyChainConfig.tryParse(config);
  return chain != null && chainBackends(chain).contains(VpnBackend.mihomo);
}

// один на сервер, сколько бы маршрутов на него ни вело
class RouteServerOutbound {
  const RouteServerOutbound({
    required this.tag,
    required this.serverId,
    required this.config,
    required this.address,
    required this.entries,
    this.listDomains = const [],
  });

  final String tag;
  final String serverId;
  final String config;

  final String address;

  final String entries;

  final List<String> listDomains;

  RouteServerOutbound copyWith({String? entries, List<String>? listDomains}) =>
      RouteServerOutbound(
        tag: tag,
        serverId: serverId,
        config: config,
        address: address,
        entries: entries ?? this.entries,
        listDomains: listDomains ?? this.listDomains,
      );
}

// маршрут без выхода (сервер пропал, совпал с активным, не встаёт в ядро) при свёртке уходит через VPN.
// маршруты приложений получают выход только при withApps, их сайты в entries не попадают: у них свои правила
List<RouteServerOutbound> routeServerOutbounds({
  required List<TrafficRoute> routes,
  required List<ServerItem> servers,
  required String? activeServerId,
  required VpnBackend core,
  bool withApps = false,
}) {
  final byId = {for (final s in servers) s.id: s};
  final entries = <String, List<String>>{};
  for (final route in orderedRoutes(routes)) {
    if (!route.enabled || (!route.allApps && !withApps)) continue;
    if (route.target != RouteTarget.server) continue;
    final server = byId[route.serverId];
    if (server == null || server.id == activeServerId) continue;
    if (!routeServerSupported(server.config, core)) continue;
    if (route.allApps) {
      final text = routeEntriesText(route).trim();
      if (text.isEmpty) continue;
      entries.putIfAbsent(server.id, () => []).add(text);
    } else if (!routeIsEmpty(route) &&
        route.apps.any((app) => app.trim().isNotEmpty)) {
      entries.putIfAbsent(server.id, () => []);
    }
  }
  var index = 0;
  return [
    for (final MapEntry(key: id, value: texts) in entries.entries)
      RouteServerOutbound(
        tag: 'keq-srv-${index++}',
        serverId: id,
        config: byId[id]!.config,
        address: byId[id]!.address,
        entries: texts.join('\n'),
      ),
  ];
}
