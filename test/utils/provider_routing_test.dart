import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/traffic_route.dart';
import 'package:keqdroid/utils/provider_routing.dart';

// пример своего профиля из dev-docs/routing.md Happ
const _happChina = {
  'Name': 'China',
  'GlobalProxy': 'true',
  'RemoteDNSType': 'DoH',
  'RemoteDNSDomain': 'https://cloudflare-dns.com/dns-query',
  'RemoteDNSIP': '1.1.1.1',
  'DomesticDNSType': 'DoU',
  'DomesticDNSDomain': '',
  'DomesticDNSIP': '8.8.8.8',
  'Geoipurl':
      'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat',
  'Geositeurl':
      'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat',
  'LastUpdated': '',
  'DnsHosts': {'cloudflare-dns.com': '1.1.1.1'},
  'DirectSites': ['geosite:cn', 'geosite:geolocation-cn'],
  'DirectIp': ['geoip:cn', '10.0.0.0/8', '192.168.0.0/16'],
  'ProxySites': ['geosite:cn'],
  'ProxyIp': ['geoip:amazon'],
  'BlockSites': ['geosite:ads'],
  'BlockIp': ['geoip:ads'],
  'DomainStrategy': 'IPIfNonMatch',
  'FakeDNS': 'false',
};

// заголовок routing из docs.v2raytun.com/overview/supported-headers
const _v2rayTunHeader =
    'eyJkb21haW5TdHJhdGVneSI6IkFzSXMiLCJpZCI6IjFFQUE4OEJCLUI1RjUtNEY2OS04MkQwLTlGRjQ0OTkwODc5NCIsImJhbGFuY2VycyI6W10sImRvbWFpbk1hdGNoZXIiOiJoeWJyaWQiLCJydWxlcyI6W3siZG9tYWluIjpbInJlZ2V4cDouKlxcXFwucnUkIiwiZ2Vvc2l0ZTpjYXRlZ29yeS1ydSJdLCJpZCI6IjlDQTYyQzY5LTNEN0EtNEZFNS05RTE5LTIxODlFMkU0ODUzRSIsIm91dGJvdW5kVGFnIjoiZGlyZWN0IiwidHlwZSI6ImZpZWxkIiwiX19uYW1lX18iOiJEaXJlY3QgUnVzc2lhIiwiaXAiOlsiZ2VvaXA6cnUiXX1dLCJuYW1lIjoiRXhhbXBsZSJ9';

String _link(String scheme, Map<String, Object?> profile, {String kind = 'onadd'}) =>
    '$scheme://routing/$kind/${base64.encode(utf8.encode(jsonEncode(profile)))}';

ProviderRoutingRules _rules(ProviderRouting? parsed) {
  expect(parsed, isA<ProviderRoutingRules>());
  return parsed! as ProviderRoutingRules;
}

void main() {
  group('профиль Happ', () {
    test('списки ложатся маршрутами: блок, напрямую, через VPN', () {
      final rules = _rules(parseProviderRouting(_link('happ', _happChina)));
      expect(rules.name, 'China');
      expect(rules.finalOutbound, AppSettings.finalOutboundProxy);
      expect(rules.routes.map((r) => r.target), [
        RouteTarget.block,
        RouteTarget.direct,
        RouteTarget.vpn,
      ]);
      expect(rules.routes[0].sites, 'geosite:ads\ngeoip:ads');
      expect(
        rules.routes[1].sites,
        'geosite:cn\ngeosite:geolocation-cn\ngeoip:cn\n10.0.0.0/8\n192.168.0.0/16',
      );
      expect(rules.routes[2].sites, 'geosite:cn\ngeoip:amazon');
      expect(rules.routes.every((r) => r.allApps), isTrue);
    });

    test('add и onadd одинаковы, Incy и наша схема тоже', () {
      final names = [
        for (final link in [
          _link('happ', _happChina, kind: 'add'),
          _link('incy', _happChina),
          _link('keqdroid', _happChina),
          _link('keqdis', _happChina, kind: 'add'),
          _link('HAPP', _happChina),
        ])
          _rules(parseProviderRouting(link)).name,
      ];
      expect(names, everyElement('China'));
    });

    test('GlobalProxy false отправляет остальное напрямую', () {
      final rules = _rules(parseProviderRouting(
        _link('happ', {'Name': 'RU', 'GlobalProxy': 'false'}),
      ));
      expect(rules.finalOutbound, AppSettings.finalOutboundDirect);
      expect(rules.routes, isEmpty);
    });

    test('пустые списки маршрутов не дают, без имени имя пустое', () {
      final rules = _rules(parseProviderRouting(
        _link('happ', {'DirectSites': <String>[], 'ProxySites': ['  ']}),
      ));
      expect(rules.name, isNull);
      expect(rules.routes, isEmpty);
    });

    test('base64 без паддинга и в url-safe алфавите', () {
      final payload = base64Url
          .encode(utf8.encode(jsonEncode({'Name': 'Ютуб?', 'ProxySites': ['geosite:youtube']})))
          .replaceAll('=', '');
      final rules = _rules(parseProviderRouting('happ://routing/onadd/$payload'));
      expect(rules.name, 'Ютуб?');
      expect(rules.routes.single.sites, 'geosite:youtube');
    });

    test('голый JSON в заголовке тоже профиль', () {
      final rules = _rules(parseProviderRouting(jsonEncode(_happChina)));
      expect(rules.routes, hasLength(3));
    });

    test('keyword становится regexp, ext и ссылки на списки выпадают', () {
      final rules = _rules(parseProviderRouting(_link('happ', {
        'DirectSites': [
          'keyword:sber',
          'ext:custom.dat:ru',
          'https://example.com/list.txt',
          'full:gosuslugi.ru',
        ],
      })));
      expect(rules.routes.single.sites, 'regexp:sber\nfull:gosuslugi.ru');
    });

    test('off выключает, мусор не профиль', () {
      expect(parseProviderRouting('happ://routing/off'), isA<ProviderRoutingOff>());
      expect(parseProviderRouting('keqdroid://routing/off'), isA<ProviderRoutingOff>());
      expect(parseProviderRouting('happ://routing/onadd/не-base64'), isNull);
      expect(parseProviderRouting('happ://routing/add/'), isNull);
      expect(parseProviderRouting('happ://add/https://example.com/sub'), isNull);
      expect(parseProviderRouting(jsonEncode({'foo': 1})), isNull);
      expect(parseProviderRouting(''), isNull);
    });
  });

  group('правила xray, как у v2RayTun', () {
    test('пример из их документации', () {
      final rules = _rules(parseProviderRouting(_v2rayTunHeader));
      expect(rules.name, 'Example');
      expect(rules.finalOutbound, AppSettings.finalOutboundProxy);
      final route = rules.routes.single;
      expect(route.target, RouteTarget.direct);
      expect(route.sites, r'regexp:.*\\.ru$' '\ngeosite:category-ru\ngeoip:ru');
    });

    test('правило с портом пропускается, правило на всё задаёт остальное', () {
      final routing = {
        'rules': [
          {'type': 'field', 'port': '443', 'domain': ['a.example'], 'outboundTag': 'direct'},
          {'type': 'field', 'domain': ['b.example'], 'outboundTag': 'block'},
          {'type': 'field', 'domain': ['c.example'], 'outboundTag': 'my-balancer'},
          {'type': 'field', 'network': 'udp', 'ip': ['1.1.1.1'], 'outboundTag': 'direct'},
          {'type': 'field', 'domain': ['d.example'], 'outboundTag': 'proxy', 'enabled': false},
          {'type': 'field', 'network': 'tcp,udp', 'outboundTag': 'direct'},
          {'type': 'field', 'domain': ['e.example'], 'outboundTag': 'proxy'},
        ],
      };
      final rules = _rules(
        parseProviderRouting(base64.encode(utf8.encode(jsonEncode(routing)))),
      );
      expect(rules.routes.map((r) => (r.target, r.sites)), [
        (RouteTarget.block, 'b.example'),
      ]);
      expect(rules.finalOutbound, AppSettings.finalOutboundDirect);
    });
  });

  group('где профиль приходит', () {
    test('в теле подписки строкой, в том числе внутри base64', () {
      final link = _link('happ', _happChina);
      final body = '#profile-title: X\n$link\nvless://u@198.51.100.1:443#A\n';
      expect(_rules(providerRoutingInBody(body)).name, 'China');
      expect(
        _rules(providerRoutingInBody(base64.encode(utf8.encode(body)))).name,
        'China',
      );
      expect(providerRoutingInBody('vless://u@198.51.100.1:443#A'), isNull);
      expect(providerRoutingInBody('happ://routing/off\n'), isA<ProviderRoutingOff>());
    });

    test('заголовки: Routing-Enable 0 сильнее правил рядом', () {
      final link = _link('happ', _happChina);
      String? Function(String) headers(Map<String, String> h) => (n) => h[n];
      expect(
        _rules(providerRoutingFromHeaders(headers({'routing': link}))).name,
        'China',
      );
      expect(
        providerRoutingFromHeaders(headers({'routing': link, 'routing-enable': '0'})),
        isA<ProviderRoutingOff>(),
      );
      expect(
        _rules(providerRoutingFromHeaders(
          headers({'routing': link, 'routing-enable': 'true'}),
        )).name,
        'China',
      );
      expect(providerRoutingFromHeaders(headers({})), isNull);
    });
  });
}
