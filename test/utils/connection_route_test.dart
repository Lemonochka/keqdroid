import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/connection_entry.dart';
import 'package:keqdroid/models/traffic_route.dart';
import 'package:keqdroid/utils/connection_route.dart';
import 'package:keqdroid/utils/geo_dat_reader.dart';

ConnectionEntry _conn(
  String host, {
  String rule = '',
  String outbound = 'direct',
  String destIp = '',
  String network = 'tcp',
  int port = 443,
  bool decidedByCore = false,
}) =>
    ConnectionEntry(
      id: host,
      network: network,
      host: host,
      destPort: port,
      destIp: destIp,
      outbound: outbound,
      rule: rule,
      decidedByCore: decidedByCore,
    );

TrafficRoute _route(
  String id, {
  RouteTarget target = RouteTarget.direct,
  RouteContent content = RouteContent.sites,
  String sites = '',
  String presetId = '',
  List<String> apps = const [],
  int? order,
  RouteNetwork network = RouteNetwork.any,
  bool enabled = true,
}) =>
    TrafficRoute(
      id: id,
      target: target,
      content: content,
      sites: sites,
      presetId: presetId,
      apps: apps,
      order: order,
      network: network,
      enabled: enabled,
    );

final _geo = PreloadedGeoLookup(
  sites: {
    'category-ru': const [
      GeoDomain(type: GeoDomainType.domain, value: 'ru'),
      GeoDomain(type: GeoDomainType.domain, value: 'dodois.io'),
    ],
    'ru-whitelist': const [
      GeoDomain(type: GeoDomainType.full, value: 'api.vk.com'),
    ],
    'category-ads-all': const [
      GeoDomain(type: GeoDomainType.plain, value: 'adfox'),
      GeoDomain(type: GeoDomainType.regex, value: r'^mc\.yandex\.'),
    ],
  },
  ips: {
    'refilter': const ['149.154.160.0/20', '2001:67c:4e8::/48'],
  },
);

final _ru = _route('ru', content: RouteContent.preset, presetId: 'ru');
final _vk = _route('vk', sites: 'vk.com, full:id.vk.com');
final _ads = _route(
  'ads',
  target: RouteTarget.block,
  content: RouteContent.preset,
  presetId: 'ads',
);

ConnectionTarget _t(String host, [String ip = '']) =>
    ConnectionTarget.of(_conn(host, destIp: ip));

void main() {
  group('matchToken', () {
    test('domain entries match the domain and its subdomains', () {
      expect(matchToken('vk.com', _t('vk.com'), _geo), isTrue);
      expect(matchToken('vk.com', _t('m.vk.com'), _geo), isTrue);
      expect(matchToken('vk.com', _t('notvk.com'), _geo), isFalse);
      expect(matchToken('*.vk.com', _t('m.vk.com'), _geo), isTrue);
      expect(matchToken('.vk.com', _t('vk.com'), _geo), isTrue);
      expect(matchToken('domain:vk.com', _t('a.b.vk.com'), _geo), isTrue);
    });

    test('a bare word is a zone, not a keyword', () {
      expect(matchToken('ru', _t('lenta.ru'), _geo), isTrue);
      expect(matchToken('su', _t('aistudio.google.com'), _geo), isFalse);
    });

    test('full and regexp entries', () {
      expect(matchToken('full:id.vk.com', _t('id.vk.com'), _geo), isTrue);
      expect(matchToken('full:id.vk.com', _t('m.id.vk.com'), _geo), isFalse);
      expect(matchToken(r'regexp:^ya\.', _t('ya.ru'), _geo), isTrue);
      expect(matchToken('regexp:([', _t('ya.ru'), _geo), isFalse);
    });

    test('geosite by all four match types of the base', () {
      expect(matchToken('geosite:category-ru', _t('lenta.ru'), _geo), isTrue);
      expect(
        matchToken('geosite:category-ru', _t('drinkit.dodois.io'), _geo),
        isTrue,
      );
      expect(matchToken('geosite:ru-whitelist', _t('api.vk.com'), _geo), isTrue);
      expect(matchToken('geosite:ru-whitelist', _t('vk.com'), _geo), isFalse);
      expect(
        matchToken('geosite:category-ads-all', _t('banners.adfox.ru'), _geo),
        isTrue,
      );
      expect(
        matchToken('geosite:category-ads-all', _t('mc.yandex.ru'), _geo),
        isTrue,
      );
    });

    test('a code missing from the base is unknown, not a miss', () {
      expect(matchToken('geosite:ir', _t('example.ir'), _geo), isNull);
      expect(matchToken('geoip:ir', _t('1.1.1.1'), _geo), isNull);
    });

    test('ip entries check the destination address', () {
      expect(matchToken('geoip:refilter', _t('149.154.167.41'), _geo), isTrue);
      expect(
        matchToken('geoip:refilter', _t('telegram.org', '149.154.167.99'), _geo),
        isTrue,
      );
      expect(matchToken('geoip:refilter', _t('telegram.org'), _geo), isFalse);
      expect(matchToken('10.0.0.0/8', _t('10.2.3.4'), _geo), isTrue);
      expect(matchToken('10.0.0.1', _t('10.0.0.2'), _geo), isFalse);
      // доменное правило на голый IP не ложится
      expect(matchToken('vk.com', _t('87.240.132.78'), _geo), isFalse);
    });

    test('a list by link is not read here', () {
      expect(
        matchToken('https://example.com/list.txt', _t('vk.com'), _geo),
        isNull,
      );
    });
  });

  group('ipInCidr', () {
    test('v4, v6, whole space and garbage', () {
      expect(ipInCidr('149.154.175.50', '149.154.160.0/20'), isTrue);
      expect(ipInCidr('149.154.176.1', '149.154.160.0/20'), isFalse);
      expect(ipInCidr('2001:67c:4e8:f004::9', '2001:67c:4e8::/48'), isTrue);
      expect(ipInCidr('1.2.3.4', '0.0.0.0/0'), isTrue);
      expect(ipInCidr('1.2.3.4', '2001:67c:4e8::/48'), isFalse);
      expect(ipInCidr('1.2.3.4', '1.2.3.0/33'), isFalse);
      expect(ipInCidr('not-an-ip', '1.2.3.0/24'), isFalse);
    });
  });

  group('explainRoute', () {
    RouteExplanation explain(
      ConnectionEntry entry,
      List<TrafficRoute> routes, {
      bool ruleInfoAvailable = true,
      Map<String, bool?> appMatch = const {},
    }) =>
        explainRoute(
          entry: entry,
          routes: routes,
          ruleInfoAvailable: ruleInfoAvailable,
          geo: _geo,
          appMatch: appMatch,
        );

    String? routeOf(RouteExplanation e) => switch (e) {
          ByRoute(:final route) => route.id,
          _ => null,
        };

    test('a dragged route is found by its tag exactly', () {
      final routes = [
        _route('first', sites: 'example.com', order: 0),
        _route('second', content: RouteContent.preset, presetId: 'ru', order: 1),
      ];
      final e = explain(
        _conn('drinkit-mobile-api.drinkit.dodois.io',
            rule: 'keq-route-1-domains'),
        routes,
      );
      expect(routeOf(e), 'second');
    });

    test('an app route is found by its tag exactly', () {
      final routes = [
        _vk,
        _route('chrome', apps: ['com.android.chrome'],
            content: RouteContent.allTraffic, target: RouteTarget.vpn),
      ];
      final e = explain(
        _conn('example.com', rule: 'keq-app-0', outbound: 'proxy'),
        routes,
      );
      expect(routeOf(e), 'chrome');
    });

    test('a tag of a route that is gone explains nothing', () {
      expect(
        explain(_conn('a.ru', rule: 'keq-route-5'), [_ru]),
        isA<Unexplained>(),
      );
    });

    test('nothing matched means the final row', () {
      expect(explain(_conn('x.com', outbound: 'proxy'), [_ru]), isA<ByFinal>());
      expect(
        explain(_conn('x.com', rule: '*', outbound: 'proxy'), [_ru]),
        isA<ByFinal>(),
      );
      expect(
        explain(_conn('x.com', rule: 'final', outbound: 'proxy'), [_ru]),
        isA<ByFinal>(),
      );
    });

    test('without Info logs an empty rule is not taken for the final row', () {
      expect(
        explain(
          _conn('x.com', outbound: 'proxy'),
          [_ru],
          ruleInfoAvailable: false,
        ),
        isA<Unexplained>(),
      );
    });

    test('xray folded lists: the route whose sites match', () {
      final routes = [_vk, _ru];
      expect(
        routeOf(explain(_conn('lenta.ru', rule: 'user-direct-domains'), routes)),
        'ru',
      );
      expect(
        routeOf(explain(_conn('m.vk.com', rule: 'user-direct-domains'), routes)),
        'vk',
      );
      expect(
        routeOf(explain(
          _conn('mc.yandex.ru', rule: 'user-block-domains', outbound: 'block'),
          [_ru, _ads],
        )),
        'ads',
      );
    });

    test('a route that would send it elsewhere is never named', () {
      expect(
        explain(
          _conn('lenta.ru', rule: 'user-proxy-domains', outbound: 'proxy'),
          [_ru],
        ),
        isA<Unexplained>(),
      );
    });

    test('mihomo rule payload points at the route without the base', () {
      final empty = PreloadedGeoLookup();
      RouteExplanation clash(String rule, String host) => explainRoute(
            entry: _conn(host, rule: rule),
            routes: [_vk, _ru],
            ruleInfoAvailable: true,
            geo: empty,
          );
      expect(routeOf(clash('GeoSite(category-ru)', 'lenta.ru')), 'ru');
      expect(routeOf(clash('DomainSuffix(vk.com)', 'm.vk.com')), 'vk');
      expect(routeOf(clash('Domain(id.vk.com)', 'id.vk.com')), 'vk');
    });

    test('service rules of the core are not routes', () {
      expect(
        explain(
          _conn('172.19.0.2', rule: 'dns-out-tun', outbound: 'dns-out'),
          [_ru],
        ),
        isA<Unexplained>(),
      );
      expect(
        explain(
          _conn('x.ru', rule: 'user-direct-domains', decidedByCore: true),
          [_ru],
        ),
        isA<Unexplained>(),
      );
    });

    test('an app route counts only when the owner is that app', () {
      final routes = [
        _route('chrome-vk', apps: ['com.android.chrome'], sites: 'vk.com'),
        _vk,
      ];
      final entry = _conn('vk.com', rule: 'DomainSuffix(vk.com)');
      expect(routeOf(explain(entry, routes)), 'vk');
      expect(
        routeOf(explain(entry, routes, appMatch: {'chrome-vk': true})),
        'chrome-vk',
      );
    });

    test('disabled and protocol-mismatched routes are skipped', () {
      final routes = [
        _route('off', sites: 'vk.com', enabled: false),
        _route('udp', sites: 'vk.com', network: RouteNetwork.udp),
        _vk,
      ];
      expect(
        routeOf(explain(_conn('vk.com', rule: 'DomainSuffix(vk.com)'), routes)),
        'vk',
      );
    });
  });

  group('presetMatches', () {
    test('every ready list gets an answer', () {
      final lists = presetMatches(_t('drinkit.dodois.io'), _geo);
      expect(lists['ru'], ListMatch.hit);
      expect(lists['ads'], ListMatch.miss);
      // кодов ir и refilter в этой базе для домена нет
      expect(lists['ir'], ListMatch.unknown);
      expect(lists['whitelist'], ListMatch.miss);
    });

    test('an address-only connection is checked by geoip', () {
      final lists = presetMatches(_t('149.154.167.41'), _geo);
      expect(lists['refilter'], ListMatch.hit);
      expect(lists['ru'], ListMatch.miss);
    });
  });

  group('routeAppsMatch', () {
    test('android: by the packages behind the label', () {
      expect(
        routeAppsMatch(
          ['com.android.chrome'],
          process: 'Chrome',
          packages: {'com.android.chrome'},
        ),
        isTrue,
      );
      expect(
        routeAppsMatch(['org.telegram.messenger'],
            process: 'Chrome', packages: {'com.android.chrome'}),
        isFalse,
      );
      expect(routeAppsMatch(['com.android.chrome'], process: ''), isNull);
    });

    test('pc: by process name or by the path typed in', () {
      const exe = r'C:\Program Files\Mozilla Firefox\firefox.exe';
      expect(routeAppsMatch(['firefox.exe'], process: exe, windows: true),
          isTrue);
      expect(routeAppsMatch(['FIREFOX'], process: exe, windows: true), isTrue);
      expect(routeAppsMatch([exe], process: exe, windows: true), isTrue);
      expect(
        routeAppsMatch([r'D:\other\firefox.exe'], process: exe, windows: true),
        isFalse,
      );
      expect(routeAppsMatch(['firefox'], process: '/usr/bin/firefox',
          windows: false), isTrue);
    });
  });

  group('inspectConnection on real base files', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('connection_route_');
    });

    tearDown(() async {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    test('reads only the codes it needs and answers off the isolate', () async {
      await File('${tmp.path}${Platform.pathSeparator}geosite.dat')
          .writeAsBytes(Uint8List.fromList([
        ..._entry('CATEGORY-RU', _domain(2, 'ru')),
        ..._entry('CATEGORY-ADS-ALL', _domain(2, 'doubleclick.net')),
      ]));
      await File('${tmp.path}${Platform.pathSeparator}geoip.dat')
          .writeAsBytes(Uint8List.fromList([
        ..._entry('REFILTER', _cidr([149, 154, 160, 0], 20)),
      ]));

      final insight = await inspectConnection(
        entry: _conn('lenta.ru', rule: 'user-direct-domains'),
        routes: [_ru],
        ruleInfoAvailable: true,
        geoDir: tmp.path,
      );
      expect(insight.route, isA<ByRoute>());
      expect((insight.route as ByRoute).route.id, 'ru');
      expect(insight.lists['ru'], ListMatch.hit);
      expect(insight.lists['ads'], ListMatch.miss);
      expect(insight.lists['whitelist'], ListMatch.unknown);
    });

    test('without a base directory nothing is claimed', () async {
      final insight = await inspectConnection(
        entry: _conn('lenta.ru', rule: 'user-direct-domains'),
        routes: [_ru],
        ruleInfoAvailable: true,
        geoDir: null,
      );
      expect(insight.route, isA<Unexplained>());
      // в каждом готовом списке есть geo-код, без базы про них ничего не сказать
      expect(insight.lists.values.toSet(), {ListMatch.unknown});
    });
  });
}

void _varint(List<int> out, int value) {
  var v = value;
  while (v >= 0x80) {
    out.add((v & 0x7f) | 0x80);
    v >>= 7;
  }
  out.add(v);
}

List<int> _domain(int type, String value) {
  final body = <int>[];
  if (type != 0) body.addAll([0x08, type]);
  body.add(0x12);
  _varint(body, value.length);
  body.addAll(value.codeUnits);
  final out = <int>[0x12];
  _varint(out, body.length);
  return out..addAll(body);
}

List<int> _cidr(List<int> ip, int prefix) {
  final body = <int>[0x0a];
  _varint(body, ip.length);
  body
    ..addAll(ip)
    ..add(0x10);
  _varint(body, prefix);
  final out = <int>[0x12];
  _varint(out, body.length);
  return out..addAll(body);
}

List<int> _entry(String code, List<int> body) {
  final entry = <int>[0x0a];
  _varint(entry, code.length);
  entry
    ..addAll(code.codeUnits)
    ..addAll(body);
  final out = <int>[0x0a];
  _varint(out, entry.length);
  return out..addAll(entry);
}
