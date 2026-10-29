import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/traffic_route.dart';
import 'package:keqdroid/tunnel/vpn_backend.dart';
import 'package:keqdroid/utils/route_servers.dart';
import 'package:keqdroid/utils/rule_lists.dart';
import 'package:keqdroid/utils/traffic_routes.dart';

const _vless = 'vless://00000000-0000-4000-8000-000000000000@de.example:443'
    '?type=tcp&security=tls&sni=de.example#DE';
const _tuic = 'tuic://00000000-0000-4000-8000-000000000000:pw@fi.example:443'
    '?sni=fi.example#FI';
const _xrayJson =
    '{"outbounds":[{"protocol":"vless","tag":"proxy","settings":{}}]}';
const _clashYaml = '''
proxies:
  - {name: NL, type: trojan, server: nl.example, port: 443, password: password}
proxy-groups:
  - name: Proxy
    type: select
    proxies: [NL]
''';

ServerItem _server(String id, String config) =>
    ServerItem(id: id, type: ServerItemType.manual, config: config);

TrafficRoute _route(
  String id,
  String server, {
  String sites = 'youtube.com',
  bool enabled = true,
  List<String> apps = const [],
}) =>
    TrafficRoute(
      id: id,
      sites: sites,
      target: RouteTarget.server,
      serverId: server,
      enabled: enabled,
      apps: apps,
    );

void main() {
  group('какой сервер встаёт в маршрут', () {
    test('ссылка — у ядра, которое её берёт', () {
      expect(routeServerSupported(_vless, VpnBackend.xray), isTrue);
      expect(routeServerSupported(_vless, VpnBackend.mihomo), isTrue);
      // tuic у xray нет вовсе.
      expect(routeServerSupported(_tuic, VpnBackend.xray), isFalse);
      expect(routeServerSupported(_tuic, VpnBackend.mihomo), isTrue);
    });

    test('готовый JSON — только у xray, YAML — только у mihomo', () {
      expect(routeServerSupported(_xrayJson, VpnBackend.xray), isTrue);
      expect(routeServerSupported(_xrayJson, VpnBackend.mihomo), isFalse);
      expect(routeServerSupported(_clashYaml, VpnBackend.mihomo), isTrue);
      expect(routeServerSupported(_clashYaml, VpnBackend.xray), isFalse);
    });

    test('JSON, у которого dialerProxy ведёт мимо его выходов, — нет', () {
      const broken = '{"outbounds":[{"protocol":"vless","tag":"proxy",'
          '"streamSettings":{"sockopt":{"dialerProxy":"fragment"}}}]}';
      expect(routeServerSupported(broken, VpnBackend.xray), isFalse);
    });

    test('YAML, чьи группы набирает само ядро, — нет', () {
      for (final key in [
        'include-all: true',
        'use: [remote]',
        // фильтр сверяется с именами, а в маршруте они наши
        'exclude-filter: NL',
      ]) {
        final yaml = _clashYaml.replaceFirst('type: select', 'type: select\n    $key');
        expect(routeServerSupported(yaml, VpnBackend.mihomo), isFalse,
            reason: key);
      }
      for (final key in ['include-all: false', 'use: []', 'filter: NL']) {
        final yaml = _clashYaml.replaceFirst('type: select', 'type: select\n    $key');
        expect(routeServerSupported(yaml, VpnBackend.mihomo), isTrue,
            reason: key);
      }
      final unknown = _clashYaml.replaceFirst('[NL]', '[NL, Missing]');
      expect(routeServerSupported(unknown, VpnBackend.mihomo), isFalse);
    });
  });

  group('выходы', () {
    final servers = [
      _server('de', _vless),
      _server('fi', _tuic),
      _server('active', _vless),
    ];

    test('один выход на сервер, записи маршрутов вместе', () {
      final out = routeServerOutbounds(
        routes: [
          _route('a', 'de', sites: 'youtube.com'),
          _route('b', 'de', sites: 'googlevideo.com'),
        ],
        servers: servers,
        activeServerId: 'active',
        core: VpnBackend.mihomo,
      );
      expect(out, hasLength(1));
      expect(out.single.tag, 'keq-srv-0');
      expect(out.single.address, 'de.example');
      expect(routingEntries(out.single.entries), [
        'youtube.com',
        'googlevideo.com',
      ]);
    });

    test('пропавший, активный, чужой ядру и выключенный — без выхода', () {
      final out = routeServerOutbounds(
        routes: [
          _route('gone', 'missing'),
          _route('same', 'active'),
          _route('tuic', 'fi'),
          _route('off', 'de', enabled: false),
        ],
        servers: servers,
        activeServerId: 'active',
        core: VpnBackend.xray,
      );
      expect(out, isEmpty);
    });

    // Её решение: маршрут без выхода идёт через текущий сервер, а не
    // теряется. Свёртка и выходы обязаны договориться об одном и том же.
    test('маршрут без выхода свёртка отправляет через VPN', () {
      final routes = [
        _route('ok', 'de', sites: 'youtube.com'),
        _route('tuic', 'fi', sites: 'twitch.tv'),
      ];
      final out = routeServerOutbounds(
        routes: routes,
        servers: servers,
        activeServerId: 'active',
        core: VpnBackend.xray,
      );
      final folded = foldRoutes(
        const AppSettings(),
        routes,
        serverUsable: (r) => out.any((o) => o.serverId == r.serverId),
      );
      expect(routingEntries(folded.proxyRules), ['twitch.tv']);
      expect(out.single.entries, 'youtube.com');
    });

    test('маршрут отдельных приложений здесь не участвует', () {
      final out = routeServerOutbounds(
        routes: [_route('app', 'de', apps: ['chrome'])],
        servers: servers,
        activeServerId: 'active',
        core: VpnBackend.mihomo,
      );
      expect(out, isEmpty);
    });
  });
}
