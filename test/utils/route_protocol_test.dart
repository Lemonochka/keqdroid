import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/traffic_route.dart';
import 'package:keqdroid/tunnel/vpn_backend.dart';
import 'package:keqdroid/utils/app_routes.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';
import 'package:keqdroid/utils/provider_routing.dart';
import 'package:keqdroid/utils/route_servers.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';
import 'package:keqdroid/utils/traffic_routes.dart';

import '../helpers/mihomo_rules_sim.dart';
import '../helpers/xray_rules_sim.dart';

// протокол и порт у маршрута: условие к тому же правилу, ступень та же, что у маршрута без них
const _xrayActive = 'vless://00000000-0000-4000-8000-000000000000@203.0.113.10:443'
    '?type=tcp&security=tls&sni=nl.example#NL';
const _mihomoActive = 'ss://YWVzLTI1Ni1nY206dGVzdHBhc3M@203.0.113.10:8388#nl';
const _de = 'trojan://pw@198.51.100.7:443?security=tls&sni=de.example#DE';

const _base = AppSettings(proxyRules: 'telegram.org');

final _servers = [
  ServerItem(id: 'nl', type: ServerItemType.manual, config: _xrayActive),
  ServerItem(id: 'de', type: ServerItemType.manual, config: _de),
];

// блок QUIC у YouTube: TCP к нему идёт как раньше
const _quic = TrafficRoute(
  id: 'quic',
  sites: 'youtube.com, googlevideo.com',
  target: RouteTarget.block,
  network: RouteNetwork.udp,
  ports: '443',
);
const _ru = TrafficRoute(id: 'ru', sites: 'ru, vk.com', target: RouteTarget.direct);
// весь UDP игр напрямую, но порт только их
const _games = TrafficRoute(
  id: 'games',
  content: RouteContent.allTraffic,
  target: RouteTarget.direct,
  network: RouteNetwork.udp,
  ports: '27000-27050',
);
const _tcpOnly = TrafficRoute(
  id: 'tcp-de',
  sites: 'example.org',
  target: RouteTarget.server,
  serverId: 'de',
  network: RouteNetwork.tcp,
);

({
  AppSettings settings,
  List<RouteServerOutbound> outbounds,
  List<RouteAppRules> apps,
}) _prepare(List<TrafficRoute> routes, VpnBackend core) {
  final outbounds = routeServerOutbounds(
    routes: routes,
    servers: _servers,
    activeServerId: 'nl',
    core: core,
  );
  return (
    settings: foldRoutes(
      _base,
      routes,
      serverUsable: (r) => outbounds.any((o) => o.serverId == r.serverId),
    ),
    outbounds: outbounds,
    apps: routeProtocolRules(routes: routes, outbounds: outbounds),
  );
}

Map<String, dynamic> _xray(List<TrafficRoute> routes, {bool tun = false}) {
  final p = _prepare(routes, VpnBackend.xray);
  return jsonDecode(ConfigGeneratorV2.generateConfig(
    _xrayActive,
    p.settings,
    nativeTunInbound: tun,
    routeServers: p.outbounds,
    appRoutes: p.apps,
  )) as Map<String, dynamic>;
}

Map<String, dynamic> _mihomo(
  List<TrafficRoute> routes, {
  MihomoTunOptions? tun,
}) {
  final p = _prepare(routes, VpnBackend.mihomo);
  return MihomoConfigGen.build(
    _mihomoActive,
    p.settings,
    socksPort: 2080,
    tun: tun,
    routeServers: p.outbounds,
    appRoutes: p.apps,
  );
}

String? _x(Map<String, dynamic> c, String host, {String net = 'tcp', int port = 443}) =>
    simulateXray(c, XrayConn(inbound: 'socks-in', host: host, network: net, port: port));

String _m(Map<String, dynamic> c, String host, {String net = 'TCP', int port = 443}) =>
    simulateMihomo(c, SimConn(inType: 'SOCKS5', host: host, network: net, port: port));

void main() {
  setUp(() => Socks5Credentials().init('u', 'p'));

  group('порты', () {
    test('один, несколько и диапазон, через запятую, пробел или косую черту', () {
      expect(routePortRanges(''), isEmpty);
      expect(routePortRanges('443'), [(443, 443)]);
      expect(routePortRanges('80, 443 27000-27050/8080'),
          [(80, 80), (443, 443), (27000, 27050), (8080, 8080)]);
    });

    test('не порт: ноль, больше 65535, перевёрнутый диапазон, буквы', () {
      for (final bad in ['0', '65536', '50-10', 'https', '443-', '-443', '1.5']) {
        expect(routePortRanges(bad), isNull, reason: bad);
      }
    });
  });

  group('маршрут', () {
    test('протокол и порты сохраняются и читаются обратно', () {
      final back = TrafficRoute.fromJson(
        jsonDecode(jsonEncode(_quic.toJson())) as Map<String, dynamic>,
      );
      expect(back, _quic);
      expect(_ru.toJson().containsKey('network'), isFalse);
      expect(_ru.toJson().containsKey('ports'), isFalse);
    });

    test('сохранённый до протокола маршрут читается как любой протокол', () {
      final old = TrafficRoute.fromJson(const {
        'id': 'old',
        'content': 'sites',
        'sites': 'x.example',
        'target': 'direct',
      });
      expect(old.network, RouteNetwork.any);
      expect(old.ports, '');
      expect(routeHasProtocol(old), isFalse);
    });

    test('в общие списки не сворачивается: там у правила нет ни сети, ни порта', () {
      final folded = foldRoutes(_base, [_quic, _ru]);
      expect(folded.blockedRules, isEmpty);
      expect(folded.directRules, 'ru, vk.com');
    });

    test('неверные порты, выключенный и пустой маршрут в ядро не идут', () {
      final rules = routeProtocolRules(
        routes: [
          _quic.copyWith(ports: '99999'),
          _ru.copyWith(network: RouteNetwork.udp, enabled: false),
          const TrafficRoute(id: 'empty', network: RouteNetwork.tcp),
        ],
        outbounds: const [],
      );
      expect(rules, isEmpty);
    });

    test('сервер только у маршрута с протоколом тоже получает выход', () {
      final outbounds = routeServerOutbounds(
        routes: const [_tcpOnly],
        servers: _servers,
        activeServerId: 'nl',
        core: VpnBackend.xray,
      );
      expect(outbounds.single.serverId, 'de');
      expect(outbounds.single.entries, isEmpty);
      expect(
        routeProtocolRules(routes: const [_tcpOnly], outbounds: outbounds)
            .single
            .serverTag,
        outbounds.single.tag,
      );
    });

    test('в ссылку «Поделиться» не попадает, а считается пропущенным', () {
      final share = routingLinkOf(
        name: 'p',
        finalOutbound: AppSettings.finalOutboundProxy,
        routes: const [_quic, _ru],
      );
      expect(share.skipped, 1);
      final json = utf8.decode(base64.decode(
        share.link.substring('keqdroid://routing/add/'.length),
      ));
      expect(json, isNot(contains('youtube.com')));
      expect(json, contains('vk.com'));
    });
  });

  final routes = [_quic, _ru, _games, _tcpOnly];

  group('xray', () {
    test('QUIC к YouTube в блок, TCP к нему и UDP к остальным как раньше', () {
      final c = _xray(routes);
      expect(_x(c, 'www.youtube.com', net: 'udp'), 'block');
      expect(_x(c, 'www.youtube.com'), 'proxy');
      expect(_x(c, 'www.youtube.com', net: 'udp', port: 8443), 'proxy');
      expect(_x(c, 'telegram.org', net: 'udp'), 'proxy');
    });

    test('весь трафик с протоколом: только эта сеть и эти порты', () {
      final c = _xray(routes);
      expect(_x(c, 'game.example', net: 'udp', port: 27015), 'direct');
      expect(_x(c, 'game.example', port: 27015), 'proxy');
      expect(_x(c, 'game.example', net: 'udp', port: 3478), 'proxy');
    });

    test('сервер только по TCP', () {
      final c = _xray(routes);
      final de = _prepare(routes, VpnBackend.xray).outbounds.single.tag;
      expect(_x(c, 'example.org'), de);
      expect(_x(c, 'example.org', net: 'udp'), 'proxy');
    });

    test('работает и без туннеля: условия на процесс у такого правила нет', () {
      final rule = ((_xray(routes)['routing'] as Map)['rules'] as List)
          .cast<Map>()
          .firstWhere((r) => r['ruleTag'] == 'keq-proto-0-domains');
      expect(rule.containsKey('process'), isFalse);
      expect(rule.containsKey('inboundTag'), isFalse);
      expect(rule['network'], 'udp');
      expect(rule['port'], '443');
    });
  });

  group('mihomo', () {
    for (final tun in [
      null,
      const MihomoTunOptions(stack: 'gvisor', fromFileDescriptor: true),
    ]) {
      final mode = tun == null ? 'прокси' : 'туннель';

      test('QUIC к YouTube в блок, TCP к нему и UDP к остальным как раньше [$mode]', () {
        final c = _mihomo(routes, tun: tun);
        expect(unknownMihomoTargets(c), isEmpty);
        expect(_m(c, 'www.youtube.com', net: 'UDP'), 'REJECT');
        expect(_m(c, 'www.youtube.com'), MihomoConfigGen.proxyName);
        expect(_m(c, 'www.youtube.com', net: 'UDP', port: 8443),
            MihomoConfigGen.proxyName);
      });

      test('весь трафик с протоколом: только эта сеть и эти порты [$mode]', () {
        final c = _mihomo(routes, tun: tun);
        expect(_m(c, 'game.example', net: 'UDP', port: 27015), 'DIRECT');
        expect(_m(c, 'game.example', port: 27015), MihomoConfigGen.proxyName);
        expect(_m(c, 'game.example', net: 'UDP', port: 3478),
            MihomoConfigGen.proxyName);
      });

      test('сервер только по TCP [$mode]', () {
        final c = _mihomo(routes, tun: tun);
        final de = _prepare(routes, VpnBackend.mihomo).outbounds.single.tag;
        expect(_m(c, 'example.org'), de);
        expect(_m(c, 'example.org', net: 'UDP'), MihomoConfigGen.proxyName);
      });
    }

    test('порты через косую черту: запятая разрезала бы правило на поля', () {
      final rules = (_mihomo([
        _games.copyWith(ports: '27000-27050, 3478'),
      ])['rules'] as List)
          .cast<String>();
      expect(
        rules,
        contains('AND,((NETWORK,UDP),(DST-PORT,27000-27050/3478)),DIRECT'),
      );
    });

    test('больше 28 портов делятся на несколько DST-PORT: одним ядро роняет конфиг', () {
      final ports = [for (var p = 10001; p <= 10030; p++) '$p'].join(', ');
      final c = _mihomo([_games.copyWith(ports: ports)]);
      final rule = (c['rules'] as List)
          .cast<String>()
          .firstWhere((r) => r.contains('DST-PORT'));
      for (final m in RegExp(r'DST-PORT,([^)]*)').allMatches(rule)) {
        expect('/'.allMatches(m.group(1)!).length + 1, lessThanOrEqualTo(28));
      }
      expect(rule, startsWith('AND,((NETWORK,UDP),(OR,((DST-PORT,'));
      expect(_m(c, 'game.example', net: 'UDP', port: 10001), 'DIRECT');
      expect(_m(c, 'game.example', net: 'UDP', port: 10030), 'DIRECT');
      expect(_m(c, 'game.example', net: 'UDP', port: 10031),
          MihomoConfigGen.proxyName);
    });

    test('процесс ради такого маршрута ядро не ищет', () {
      final c = _mihomo(
        routes,
        tun: const MihomoTunOptions(stack: 'gvisor', fromFileDescriptor: true),
      );
      expect(c['find-process-mode'], 'off');
    });
  });
}
