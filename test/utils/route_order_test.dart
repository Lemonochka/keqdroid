import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/traffic_route.dart';
import 'package:keqdroid/tunnel/vpn_backend.dart';
import 'package:keqdroid/utils/app_routes.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';
import 'package:keqdroid/utils/route_servers.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';
import 'package:keqdroid/utils/traffic_routes.dart';

import '../helpers/mihomo_rules_sim.dart';
import '../helpers/xray_rules_sim.dart';

// порядок раздела всех приложений: по цели, пока маршруты не перетаскивали
const _xrayActive = 'vless://00000000-0000-4000-8000-000000000000@203.0.113.10:443'
    '?type=tcp&security=tls&sni=nl.example#NL';
const _mihomoActive = 'ss://YWVzLTI1Ni1nY206dGVzdHBhc3M@203.0.113.10:8388#nl';
const _de = 'trojan://pw@198.51.100.7:443?security=tls&sni=de.example#DE';

final _servers = [
  ServerItem(id: 'nl', type: ServerItemType.manual, config: _xrayActive),
  ServerItem(id: 'de', type: ServerItemType.manual, config: _de),
];

const _ruDirect = TrafficRoute(
  id: 'ru',
  sites: 'ru, 198.18.0.0/16',
  target: RouteTarget.direct,
);
const _oneVpn = TrafficRoute(
  id: 'one',
  sites: 'example.ru, 198.18.5.5',
  target: RouteTarget.vpn,
);
const _mediaDe = TrafficRoute(
  id: 'media',
  sites: 'media.example.ru',
  target: RouteTarget.server,
  serverId: 'de',
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
      const AppSettings(),
      routes,
      serverUsable: (r) => outbounds.any((o) => o.serverId == r.serverId),
    ),
    outbounds: outbounds,
    apps: routeProtocolRules(routes: routes, outbounds: outbounds),
  );
}

// lists: как подставляет connect() скачанный список маршруту с этой ссылкой
List<RouteAppRules> _withLists(
  List<RouteAppRules> apps,
  Map<String, List<String>> lists,
) =>
    [
      for (final r in apps)
        r.copyWith(
          listDomains: [
            for (final e in lists.entries)
              if (r.entries.contains(e.key)) ...e.value,
          ],
        ),
    ];

String _xrayText(
  List<TrafficRoute> routes, {
  String active = _xrayActive,
  Map<String, List<String>> lists = const {},
}) {
  final p = _prepare(routes, VpnBackend.xray);
  return ConfigGeneratorV2.generateConfig(
    active,
    p.settings,
    routeServers: p.outbounds,
    appRoutes: _withLists(p.apps, lists),
  );
}

Map<String, dynamic> _xray(
  List<TrafficRoute> routes, {
  String active = _xrayActive,
  Map<String, List<String>> lists = const {},
}) =>
    jsonDecode(_xrayText(routes, active: active, lists: lists))
        as Map<String, dynamic>;

Map<String, dynamic> _mihomo(
  List<TrafficRoute> routes, {
  Map<String, List<String>> lists = const {},
  String input = _mihomoActive,
}) {
  final p = _prepare(routes, VpnBackend.mihomo);
  return MihomoConfigGen.build(
    input,
    p.settings,
    socksPort: 2080,
    routeServers: p.outbounds,
    appRoutes: _withLists(p.apps, lists),
  );
}

String? _x(
  Map<String, dynamic> c, {
  String host = '',
  String ip = '',
  String resolvesTo = '',
  String net = 'tcp',
}) =>
    simulateXray(
      c,
      XrayConn(
        inbound: 'socks-in',
        host: host,
        ip: ip,
        resolvesTo: resolvesTo,
        network: net,
      ),
    );

String _m(
  Map<String, dynamic> c, {
  String host = '',
  String ip = '',
  String resolvesTo = '',
  String net = 'TCP',
}) =>
    simulateMihomo(
      c,
      SimConn(
        inType: 'SOCKS5',
        host: host,
        ip: ip,
        resolvesTo: resolvesTo,
        network: net,
      ),
    );

// как перетаскивание на экране: маршруты встают в названном порядке
List<TrafficRoute> _placed(List<TrafficRoute> shown) {
  var routes = shown;
  for (var to = 0; to < shown.length; to++) {
    final from = routesIn(RouteSection.allApps, routes)
        .indexWhere((r) => r.id == shown[to].id);
    routes = withAllAppsMoved(routes, from, to);
  }
  return routes;
}

List<Map<String, dynamic>> _xrayRules(Map<String, dynamic> c) => [
      for (final r in (c['routing'] as Map)['rules'] as List)
        (r as Map).cast<String, dynamic>(),
    ];

List<List<T>> _permutations<T>(List<T> items) {
  if (items.length <= 1) return [items];
  return [
    for (var i = 0; i < items.length; i++)
      for (final rest in _permutations([...items]..removeAt(i)))
        [items[i], ...rest],
  ];
}

void main() {
  setUp(() => Socks5Credentials().init('u', 'p'));

  group('без перетаскивания порядок по цели', () {
    final all = [_ruDirect, _mediaDe, _oneVpn];

    test('xray: напрямую раньше сервера и VPN, как ни записаны маршруты', () {
      final expected = _xrayText(all);
      for (final routes in _permutations(all)) {
        expect(_xrayText(routes), expected,
            reason: routes.map((r) => r.id).join(', '));
      }
      final c = _xray(all);
      expect(_x(c, host: 'example.ru'), 'direct');
      expect(_x(c, host: 'media.example.ru'), 'direct');
      expect(_x(c, ip: '198.18.5.5'), 'direct');
    });

    test('mihomo: напрямую раньше сервера и VPN, как ни записаны маршруты', () {
      final expected = jsonEncode(_mihomo(all));
      for (final routes in _permutations(all)) {
        expect(jsonEncode(_mihomo(routes)), expected,
            reason: routes.map((r) => r.id).join(', '));
      }
      final c = _mihomo(all);
      expect(unknownMihomoTargets(c), isEmpty);
      expect(_m(c, host: 'example.ru'), 'DIRECT');
      expect(_m(c, host: 'media.example.ru'), 'DIRECT');
      expect(_m(c, ip: '198.18.5.5'), 'DIRECT');
    });

    test('другой сервер раньше VPN в обоих ядрах', () {
      const viaVpn = TrafficRoute(id: 'v', sites: 'shop.example');
      const viaDe = TrafficRoute(
        id: 'd',
        sites: 'shop.example',
        target: RouteTarget.server,
        serverId: 'de',
      );
      final routes = [viaVpn, viaDe];
      final xTag = _prepare(routes, VpnBackend.xray).outbounds.single.tag;
      final mTag = _prepare(routes, VpnBackend.mihomo).outbounds.single.tag;
      expect(_x(_xray(routes), host: 'shop.example'), xTag);
      expect(_m(_mihomo(routes), host: 'shop.example'), mTag);
    });
  });

  group('место маршрута', () {
    const block = TrafficRoute(id: 'ads', sites: 'ads.example', target: RouteTarget.block);
    const app = TrafficRoute(id: 'app', apps: ['chrome'], sites: 'yt.example');

    test('перетаскивание нумерует весь раздел и не трогает остальные', () {
      final routes = withAllAppsMoved([block, _ruDirect, app, _mediaDe, _oneVpn], 2, 0);
      expect(
        routesIn(RouteSection.allApps, routes).map((r) => r.id),
        ['one', 'ru', 'media'],
      );
      expect(
        {for (final r in routes) r.id: r.order},
        {'ads': null, 'ru': 1, 'app': null, 'media': 2, 'one': 0},
      );
      expect(orderedRoutes(routes).map((r) => r.id),
          ['ads', 'app', 'one', 'ru', 'media']);
      expect(routesHaveOwnOrder(routes), isTrue);
    });

    test('место у маршрута другого раздела своим порядком не считается', () {
      expect(routesHaveOwnOrder([_ruDirect, _oneVpn]), isFalse);
      expect(
        routesHaveOwnOrder([block.copyWith(order: 0), app.copyWith(order: 1)]),
        isFalse,
      );
    });

    test('новый маршрут в перетащенном разделе встаёт по цели', () {
      final routes = _placed([_oneVpn, _ruDirect]);
      List<String> shown(TrafficRoute added) => [
            for (final r in routesIn(RouteSection.allApps, [...routes, added]))
              r.id,
          ];
      const direct = TrafficRoute(id: 'new', sites: 'n.example', target: RouteTarget.direct);
      expect(shown(direct), ['one', 'ru', 'new']);
      expect(shown(direct.copyWith(target: RouteTarget.vpn)), ['one', 'ru', 'new']);
      expect(
        shown(direct.copyWith(target: RouteTarget.server, serverId: 'de')),
        ['one', 'ru', 'new'],
      );
      // обхода в разделе нет: напрямую встаёт первым, как раньше
      expect(
        [
          for (final r in routesIn(
            RouteSection.allApps,
            [..._placed([_oneVpn, _mediaDe]), direct],
          ))
            r.id,
        ],
        ['new', 'one', 'media'],
      );
    });

    test('переживает сохранение, без перетаскивания в записи его нет', () {
      final moved = _placed([_oneVpn, _ruDirect]).first;
      expect(moved.order, isNotNull);
      expect(TrafficRoute.fromJson(moved.toJson()), moved);
      expect(_ruDirect.toJson().containsKey('order'), isFalse);
    });

    test('правка маршрута место не сбрасывает', () {
      final moved = _placed([_oneVpn, _ruDirect])
          .firstWhere((r) => r.id == 'one');
      expect(moved.copyWith(sites: 'other.ru').order, moved.order);
    });

    test('в три списка сворачивается только блокировка', () {
      final folded = foldRoutes(const AppSettings(), [block, ..._placed([_oneVpn, _ruDirect])]);
      expect(folded.blockedRules, 'ads.example');
      expect(folded.directRules, isEmpty);
      expect(folded.proxyRules, isEmpty);
    });
  });

  group('свой порядок в ядрах', () {
    final lifted = _placed([_mediaDe, _oneVpn, _ruDirect]);

    test('xray: решает место на экране, а не цель', () {
      final c = _xray(lifted);
      final de = _prepare(lifted, VpnBackend.xray).outbounds.single.tag;
      expect(_x(c, host: 'media.example.ru'), de);
      expect(_x(c, host: 'example.ru'), 'proxy');
      expect(_x(c, host: 'www.example.ru'), 'proxy');
      expect(_x(c, host: 'vk.ru'), 'direct');
      expect(_x(c, ip: '198.18.5.5'), 'proxy');
      expect(_x(c, ip: '198.18.9.9'), 'direct');
      expect(_x(c, host: 'other.example'), 'proxy');
    });

    test('mihomo: решает место на экране, а не цель', () {
      final c = _mihomo(lifted);
      final de = _prepare(lifted, VpnBackend.mihomo).outbounds.single.tag;
      expect(unknownMihomoTargets(c), isEmpty);
      expect(_m(c, host: 'media.example.ru'), de);
      expect(_m(c, host: 'example.ru'), MihomoConfigGen.proxyName);
      expect(_m(c, host: 'www.example.ru'), MihomoConfigGen.proxyName);
      expect(_m(c, host: 'vk.ru'), 'DIRECT');
      expect(_m(c, ip: '198.18.5.5'), MihomoConfigGen.proxyName);
      expect(_m(c, ip: '198.18.9.9'), 'DIRECT');
      expect(_m(c, host: 'other.example'), MihomoConfigGen.proxyName);
    });

    test('адрес из резолва сверяется в том же порядке', () {
      final x = _xray(lifted);
      expect(_x(x, host: 'cdn.example', resolvesTo: '198.18.5.5'), 'proxy');
      expect(_x(x, host: 'cdn.example', resolvesTo: '198.18.9.9'), 'direct');
      final m = _mihomo(lifted);
      expect(_m(m, host: 'cdn.example', resolvesTo: '198.18.5.5'),
          MihomoConfigGen.proxyName);
      expect(_m(m, host: 'cdn.example', resolvesTo: '198.18.9.9'), 'DIRECT');
    });

    // жалоба, с которой всё началось: один сайт через VPN при всей стране напрямую
    test('сайт через VPN стоит выше geoip страны напрямую', () {
      const country = TrafficRoute(id: 'geo', sites: 'geoip:ru', target: RouteTarget.direct);
      const site = TrafficRoute(id: 'site', sites: 'example.ru');
      final routes = _placed([site, country]);

      final xray = [for (final r in _xrayRules(_xray(routes))) jsonEncode(r)];
      expect(
        xray.indexWhere((r) => r.contains('example.ru')),
        lessThan(xray.indexWhere((r) => r.contains('geoip:ru'))),
      );
      final mihomo = (_mihomo(routes)['rules'] as List).cast<String>();
      expect(
        mihomo.indexWhere((r) => r.contains('example.ru')),
        lessThan(mihomo.indexWhere((r) => r.startsWith('GEOIP,ru'))),
      );

      // без перетаскивания страна выше: так было и остаётся
      final before = [for (final r in _xrayRules(_xray([site, country]))) jsonEncode(r)];
      expect(
        before.indexWhere((r) => r.contains('geoip:ru')),
        lessThan(before.indexWhere((r) => r.contains('example.ru'))),
      );
    });

    test('перетащили обратно по цели: соединения идут как до перетаскивания', () {
      final all = [_ruDirect, _mediaDe, _oneVpn];
      final back = _placed(all);
      expect(routesHaveOwnOrder(back), isTrue);
      final de = _prepare(all, VpnBackend.xray).outbounds.single.tag;
      for (final (host, ip) in [
        ('example.ru', ''),
        ('media.example.ru', ''),
        ('other.example', ''),
        ('', '198.18.5.5'),
        ('', '10.0.0.7'),
      ]) {
        expect(
          _x(_xray(back), host: host, ip: ip),
          _x(_xray(all), host: host, ip: ip),
          reason: 'xray $host$ip',
        );
        expect(
          _m(_mihomo(back), host: host, ip: ip),
          _m(_mihomo(all), host: host, ip: ip),
          reason: 'mihomo $host$ip',
        );
      }
      expect(de, isNotEmpty);
    });

    test('локальная сеть напрямую, даже если маршрут через VPN поднят наверх', () {
      const lan = TrafficRoute(id: 'lan', sites: '192.168.1.5, nas.example');
      final routes = _placed([lan, _ruDirect]);
      expect(_x(_xray(routes), ip: '192.168.1.5'), 'direct');
      expect(_m(_mihomo(routes), ip: '192.168.1.5'), 'DIRECT');
      expect(_x(_xray(routes), host: 'nas.example'), 'proxy');
    });

    test('блокировка по-прежнему раньше всех', () {
      const ads = TrafficRoute(id: 'ads', sites: 'ads.example.ru', target: RouteTarget.block);
      final routes = [ads, ..._placed([_oneVpn, _ruDirect])];
      expect(_x(_xray(routes), host: 'ads.example.ru'), 'block');
      expect(_m(_mihomo(routes), host: 'ads.example.ru'), 'REJECT');
    });

    test('сервер без выхода идёт через VPN со своего места', () {
      const gone = TrafficRoute(
        id: 'gone',
        sites: 'example.ru',
        target: RouteTarget.server,
        serverId: 'missing',
      );
      final routes = _placed([gone, _ruDirect]);
      expect(_x(_xray(routes), host: 'example.ru'), 'proxy');
      expect(_m(_mihomo(routes), host: 'example.ru'), MihomoConfigGen.proxyName);
    });

    test('маршрут с протоколом стоит на своём месте, а не на ступени цели', () {
      const tcpDe = TrafficRoute(
        id: 'tcp',
        sites: 'example.org',
        target: RouteTarget.server,
        serverId: 'de',
        network: RouteNetwork.tcp,
      );
      const direct = TrafficRoute(id: 'org', sites: 'example.org', target: RouteTarget.direct);
      final above = _placed([tcpDe, direct]);
      final below = _placed([direct, tcpDe]);
      final xDe = _prepare(above, VpnBackend.xray).outbounds.single.tag;
      final mDe = _prepare(above, VpnBackend.mihomo).outbounds.single.tag;
      expect(_x(_xray(above), host: 'example.org'), xDe);
      expect(_x(_xray(above), host: 'example.org', net: 'udp'), 'direct');
      expect(_x(_xray(below), host: 'example.org'), 'direct');
      final m = _mihomo(above);
      expect(unknownMihomoTargets(m), isEmpty);
      expect(_m(m, host: 'example.org'), mDe);
      expect(_m(m, host: 'example.org', net: 'UDP'), 'DIRECT');
      expect(_m(_mihomo(below), host: 'example.org'), 'DIRECT');
    });

    test('mihomo: список по ссылке у перетащенного маршрута своим набором', () {
      const listed = TrafficRoute(id: 'l', sites: 'https://lists.example/a.txt');
      final routes = _placed([listed, _ruDirect]);
      final c = _mihomo(routes, lists: {
        'lists.example': ['listed.ru'],
      });
      expect(unknownMihomoTargets(c), isEmpty);
      expect(_m(c, host: 'www.listed.ru'), MihomoConfigGen.proxyName);
      expect(_m(c, host: 'vk.ru'), 'DIRECT');
      // правила без условия встают в общий список, набор за SUB-RULE им не нужен
      expect(c['sub-rules'], anyOf(isNull, isEmpty));
    });

    test('xray: метки правил не повторяются', () {
      const vision = 'vless://00000000-0000-4000-8000-000000000000@203.0.113.10:443'
          '?type=tcp&security=reality&sni=decoy.example&pbk=publickey&sid=aabb'
          '&fp=chrome&flow=xtls-rprx-vision#v';
      final tags = [
        for (final r in _xrayRules(_xray(lifted, active: vision)))
          if (r['ruleTag'] != null) r['ruleTag'],
      ];
      expect(tags.toSet().length, tags.length);
    });

    test('xray: QUIC к VLESS Vision режется и у поднятого маршрута', () {
      const vision = 'vless://00000000-0000-4000-8000-000000000000@203.0.113.10:443'
          '?type=tcp&security=reality&sni=decoy.example&pbk=publickey&sid=aabb'
          '&fp=chrome&flow=xtls-rprx-vision#v';
      final c = _xray(_placed([_oneVpn, _ruDirect]), active: vision);
      expect(_x(c, host: 'example.ru', net: 'udp'), 'block');
      expect(_x(c, host: 'example.ru'), 'proxy');
      expect(_x(c, host: 'vk.ru', net: 'udp'), 'direct');
      expect(_x(c, host: 'other.example', net: 'udp'), 'block');
      // без перетаскивания то же самое делал общий block-quic
      final before = _xray([_oneVpn], active: vision);
      expect(_x(before, host: 'example.ru', net: 'udp'), 'block');
      expect(_x(before, host: 'example.ru'), 'proxy');
    });

    test('xray: DNS поднятого сайта идёт раньше резолвера обхода', () {
      List<Map> servers(List<TrafficRoute> routes) => [
            for (final s in (_xray(routes)['dns'] as Map)['servers'] as List)
              if (s is Map) s,
          ];
      bool has(Map s, String domain) =>
          (s['domains'] as List?)?.contains(domain) ?? false;

      // голое слово ru генератор пишет зоной
      const ruZone = r'regexp:.*\.ru$';
      final own = servers(_placed([_oneVpn, _ruDirect]));
      final site = own.indexWhere((s) => has(s, 'domain:example.ru'));
      final zone = own.indexWhere((s) => has(s, ruZone));
      expect(site, isNot(-1));
      expect(zone, isNot(-1));
      expect(site, lessThan(zone));
      expect(own[site]['address'], isNot('localhost'));
      expect(own[zone]['address'], 'localhost');

      // сайт ниже обхода и так решает обход: отдельной записи нет
      final below = servers(_placed([_ruDirect, _oneVpn]));
      expect(below.any((s) => has(s, 'domain:example.ru')), isFalse);
      expect(below.any((s) => has(s, ruZone)), isTrue);

      // без перетаскивания блок DNS прежний
      final before = servers([_oneVpn, _ruDirect]);
      expect(before.any((s) => has(s, 'domain:example.ru')), isFalse);
      expect(before.any((s) => has(s, ruZone)), isTrue);
      expect(jsonEncode(below), jsonEncode(before));
    });

    test('xray: сайты из списков по ссылке DNS берёт с того же места', () {
      const vpnList = TrafficRoute(id: 'vl', sites: 'https://lists.example/vpn.txt');
      const directList = TrafficRoute(
        id: 'dl',
        sites: 'https://lists.example/direct.txt',
        target: RouteTarget.direct,
      );
      const lists = {
        'https://lists.example/vpn.txt': ['blocked.example'],
        'https://lists.example/direct.txt': ['bank.example', 'blocked.example'],
      };
      final c = _xray(_placed([vpnList, directList]), lists: lists);
      expect(_x(c, host: 'blocked.example'), 'proxy');
      expect(_x(c, host: 'bank.example'), 'direct');

      final servers = [
        for (final s in (c['dns'] as Map)['servers'] as List)
          if (s is Map) s,
      ];
      int first(String domain) => servers.indexWhere(
            (s) => (s['domains'] as List?)?.contains('domain:$domain') ?? false,
          );
      expect(first('bank.example'), isNot(-1));
      expect(servers[first('bank.example')]['address'], 'localhost');
      expect(first('blocked.example'), isNot(-1));
      expect(first('blocked.example'), lessThan(first('bank.example')));
      expect(servers[first('blocked.example')]['address'], isNot('localhost'));
    });

    test('приватные сети из прежнего пресета резолв по правилам не включают', () {
      const preset = TrafficRoute(
        id: 'p',
        sites: 'ru, 10.0.0.0/8, 192.168.0.0/16',
        target: RouteTarget.direct,
      );
      const site = TrafficRoute(id: 's', sites: 'example.ru');
      for (final routes in [
        [preset, site],
        _placed([site, preset]),
      ]) {
        expect((_xray(routes)['routing'] as Map)['domainStrategy'], 'AsIs');
        final rules = (_mihomo(routes)['rules'] as List).cast<String>();
        expect(
          rules.where((r) => r.startsWith('IP-CIDR,10.0.0.0/8,DIRECT')),
          everyElement(endsWith(',no-resolve')),
        );
      }
    });
  });

  group('готовый конфиг провайдера', () {
    test('xray JSON: свой порядок после правил автора, на его выходы', () {
      const custom = '''
{
  "outbounds": [
    {
      "tag": "my-proxy",
      "protocol": "vless",
      "settings": {"vnext": [{"address": "203.0.113.10", "port": 443,
        "users": [{"id": "00000000-0000-4000-8000-000000000000", "encryption": "none"}]}]}
    },
    {"tag": "my-direct", "protocol": "freedom"}
  ],
  "routing": {"rules": [
    {"type": "field", "domain": ["domain:author.example"], "outboundTag": "my-direct"}
  ]}
}
''';
      final c = _xray(_placed([_oneVpn, _ruDirect]), active: custom);
      final outbounds = {
        for (final o in c['outbounds'] as List) (o as Map)['tag'],
      };
      for (final r in _xrayRules(c)) {
        expect(outbounds, contains(r['outboundTag']), reason: '${r['ruleTag']}');
      }
      expect(_x(c, host: 'author.example'), 'my-direct');
      expect(_x(c, host: 'example.ru'), 'my-proxy');
      expect(_x(c, ip: '198.18.5.5'), 'my-proxy');
      expect(_x(c, host: 'vk.ru'), 'my-direct');
      expect(_x(c, ip: '198.18.9.9'), 'my-direct');

      final before = _xray([_oneVpn, _ruDirect], active: custom);
      expect(_x(before, host: 'example.ru'), 'my-direct');
      expect(_x(before, host: 'vk.ru'), 'my-direct');
    });

    test('Clash: свой порядок после правил автора, на его группу', () {
      const clash = '''
proxies:
  - {name: p1, type: ss, server: 203.0.113.10, port: 8388, cipher: aes-256-gcm, password: x}
proxy-groups:
  - {name: G, type: select, proxies: [p1]}
rules:
  - DOMAIN-SUFFIX,author.example,DIRECT
  - MATCH,G
''';
      final c = _mihomo(_placed([_oneVpn, _ruDirect]), input: clash);
      expect(unknownMihomoTargets(c), isEmpty);
      expect(_m(c, host: 'author.example'), 'DIRECT');
      expect(_m(c, host: 'example.ru'), 'G');
      expect(_m(c, ip: '198.18.5.5'), 'G');
      expect(_m(c, host: 'vk.ru'), 'DIRECT');
      expect(_m(c, ip: '198.18.9.9'), 'DIRECT');

      final before = _mihomo([_oneVpn, _ruDirect], input: clash);
      expect(_m(before, host: 'example.ru'), 'DIRECT');
      expect(_m(before, host: 'vk.ru'), 'DIRECT');
    });
  });
}
