import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/routing_rule.dart';
import 'package:keqdroid/models/traffic_route.dart';
import 'package:keqdroid/utils/rule_lists.dart';
import 'package:keqdroid/utils/traffic_routes.dart';

RoutingRule _rule(
  RuleType type,
  List<String> values,
  RuleAction action, {
  bool enabled = true,
}) => RoutingRule(
  id: '$type-$values',
  name: 'r',
  type: type,
  values: values,
  action: action,
  enabled: enabled,
);

TrafficRoute _route(
  String id, {
  List<String> apps = const [],
  RouteContent content = RouteContent.sites,
  String sites = 'x.example',
  String preset = '',
  RouteTarget target = RouteTarget.vpn,
  String server = '',
  bool enabled = true,
}) => TrafficRoute(
  id: id,
  apps: apps,
  content: content,
  sites: sites,
  presetId: preset,
  target: target,
  serverId: server,
  enabled: enabled,
);

// Прежнее сворачивание Своих правил в три списка повторяет код, который
// исполнял connect() до маршрутов. Заморожена здесь как эталон: перенос
// обязан давать ядру ровно то же самое.
AppSettings _legacyFold(AppSettings settings, List<RoutingRule> rules) {
  final direct = <String>[];
  final proxy = <String>[];
  final blocked = <String>[];
  for (final rule in rules) {
    if (!rule.enabled) continue;
    final values = rule.values
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toList();
    if (values.isEmpty) continue;
    final tokens = switch (rule.type) {
      RuleType.domain || RuleType.ipCidr => values,
      RuleType.geoip =>
        values
            .map((v) => v.toLowerCase().startsWith('geoip:') ? v : 'geoip:$v')
            .toList(),
      RuleType.geosite =>
        values
            .map(
              (v) => v.toLowerCase().startsWith('geosite:') ? v : 'geosite:$v',
            )
            .toList(),
      RuleType.processName => const <String>[],
    };
    if (tokens.isEmpty) continue;
    switch (rule.action) {
      case RuleAction.direct:
        direct.addAll(tokens);
      case RuleAction.proxy:
        proxy.addAll(tokens);
      case RuleAction.block:
        blocked.addAll(tokens);
    }
  }
  String append(String existing, List<String> tokens) {
    if (tokens.isEmpty) return existing;
    final base = existing.trimRight();
    final joined = tokens.join(', ');
    return base.isEmpty ? joined : '$base\n$joined';
  }

  return settings.copyWith(
    directRules: append(settings.directRules, direct),
    proxyRules: append(settings.proxyRules, proxy),
    blockedRules: append(settings.blockedRules, blocked),
  );
}

void main() {
  var n = 0;
  String id() => 'r${n++}';
  setUp(() => n = 0);

  group('перенос прежних настроек', () {
    // Главное обещание переноса: ядро получает ровно то, что получало до
    // обновления. Сверяем с прежним сворачиванием Своих правил в списки
    // запись за записью, на всех трёх полях.
    final cases = <String, (AppSettings, List<RoutingRule>)>{
      'по умолчанию': (const AppSettings(), const []),
      'три списка': (
        const AppSettings(
          directRules: 'ru, vk.com\n10.0.0.0/8',
          proxyRules: 'youtube.com',
          blockedRules: 'doubleclick.net, https://lists.example/ads.txt',
        ),
        const [],
      ),
      'пустые поля и свои правила': (
        const AppSettings(directRules: '', proxyRules: ' ', blockedRules: ''),
        [
          _rule(RuleType.domain, ['a.example', 'b.example'], RuleAction.direct),
          _rule(RuleType.geoip, ['ru'], RuleAction.direct),
          _rule(RuleType.geosite, ['geosite:google'], RuleAction.proxy),
          _rule(RuleType.ipCidr, ['1.1.1.1'], RuleAction.block),
          _rule(
            RuleType.domain,
            ['off.example'],
            RuleAction.proxy,
            enabled: false,
          ),
          _rule(RuleType.processName, ['chrome.exe'], RuleAction.direct),
        ],
      ),
      'списки и правила вместе': (
        const AppSettings(
          directRules: 'ru',
          proxyRules: 'discord.com',
          blockedRules: 'ads.example',
        ),
        [
          _rule(RuleType.domain, ['d.example'], RuleAction.direct),
          _rule(RuleType.domain, ['p.example'], RuleAction.proxy),
          _rule(RuleType.geosite, ['category-ads-all'], RuleAction.block),
          _rule(RuleType.domain, ['p2.example'], RuleAction.proxy),
        ],
      ),
      'geo-коды и пустые значения': (
        const AppSettings(
          directRules: 'vk.com',
          proxyRules: '',
          blockedRules: '',
        ),
        [
          _rule(RuleType.geoip, ['RU'], RuleAction.direct),
          _rule(RuleType.geoip, ['geoip:us'], RuleAction.proxy),
          _rule(RuleType.geosite, ['category-ads-all'], RuleAction.block),
          _rule(RuleType.domain, ['  ', 'real.example', ''], RuleAction.proxy),
          _rule(RuleType.domain, ['   ', ''], RuleAction.proxy),
          _rule(RuleType.domain, ['a.example', 'b.example'], RuleAction.proxy),
        ],
      ),
    };

    cases.forEach((name, input) {
      test('ядро получает то же самое: $name', () {
        final (settings, rules) = input;
        final before = _legacyFold(settings, rules);
        final after = foldRoutes(settings, routesFromLegacy(settings, rules));
        for (final (label, a, b) in [
          ('direct', before.directRules, after.directRules),
          ('proxy', before.proxyRules, after.proxyRules),
          ('blocked', before.blockedRules, after.blockedRules),
        ]) {
          expect(routingEntries(b), routingEntries(a), reason: label);
        }
      });
    });

    test('правило по процессу — маршрут этих приложений, выключенный', () {
      final routes = routesFromLegacy(
        const AppSettings(directRules: '', proxyRules: '', blockedRules: ''),
        [
          _rule(RuleType.processName, [
            'chrome.exe',
            'firefox',
          ], RuleAction.direct),
        ],
        newId: id,
      );
      expect(routes.single.apps, ['chrome.exe', 'firefox']);
      expect(routes.single.content, RouteContent.allTraffic);
      expect(routes.single.target, RouteTarget.direct);
      expect(routes.single.enabled, isFalse);
    });

    test('свежая установка — один маршрут из значения по умолчанию', () {
      final routes = routesFromLegacy(const AppSettings(), const [], newId: id);
      expect(routes, hasLength(1));
      expect(routes.single.sites, 'ru, yandex.ru, vk.com');
      expect(routes.single.target, RouteTarget.direct);
      expect(legacyRoutingCustomized(const AppSettings(), const []), isFalse);
    });

    test('подсказка — только тем, кто менял маршрутизацию', () {
      expect(
        legacyRoutingCustomized(
          const AppSettings(proxyRules: 'youtube.com'),
          const [],
        ),
        isTrue,
      );
      expect(
        legacyRoutingCustomized(const AppSettings(), [
          _rule(RuleType.domain, ['a.example'], RuleAction.direct),
        ]),
        isTrue,
      );
    });
  });

  group('порядок', () {
    test('разделы: блок, приложения, все приложения', () {
      final routes = [
        _route('all-vpn'),
        _route('app-all', apps: ['chrome'], content: RouteContent.allTraffic),
        _route('block', target: RouteTarget.block),
        _route('app-block', apps: ['chrome'], target: RouteTarget.block),
        _route('app-sites', apps: ['chrome']),
        _route('all-direct', target: RouteTarget.direct),
        _route('all-server', target: RouteTarget.server, server: 's'),
      ];
      expect(orderedRoutes(routes).map((r) => r.id), [
        // Блок действует везде, в том числе у приложений со своим маршрутом.
        'block', 'app-block',
        // Сайты приложения проверяются раньше, чем весь трафик того же приложения.
        'app-sites', 'app-all',
        // Как стояли прежние списки: обход, другой сервер, через VPN.
        'all-direct', 'all-server', 'all-vpn',
      ]);
    });
  });

  group('сворачивание в списки', () {
    test('выключенные и пустые не попадают', () {
      final s = foldRoutes(const AppSettings(), [
        _route('a', sites: 'on.example', target: RouteTarget.direct),
        _route(
          'b',
          sites: 'off.example',
          target: RouteTarget.direct,
          enabled: false,
        ),
        _route('c', sites: ' ', target: RouteTarget.block),
      ]);
      expect(routingEntries(s.directRules), ['on.example']);
      expect(s.blockedRules, isEmpty);
    });

    test('прежние поля настроек не участвуют', () {
      final s = foldRoutes(const AppSettings(directRules: 'legacy.example'), [
        _route('a', sites: 'route.example', target: RouteTarget.direct),
      ]);
      expect(routingEntries(s.directRules), ['route.example']);
    });

    test('готовый список разворачивается в свои значения', () {
      final s = foldRoutes(const AppSettings(), [
        _route(
          'a',
          content: RouteContent.preset,
          preset: 'ru',
          target: RouteTarget.direct,
        ),
      ]);
      expect(routingEntries(s.directRules), ['geosite:category-ru']);
    });

    test('маршрут отдельных приложений общим спискам не достаётся', () {
      final s = foldRoutes(const AppSettings(), [
        _route(
          'a',
          apps: ['chrome'],
          sites: 'yt.example',
          target: RouteTarget.direct,
        ),
      ]);
      expect(s.directRules, isEmpty);
    });

    // Её решение: если сервер пропал или ядро его не возьмёт, трафик маршрута
    // идёт через текущий сервер, а не теряется.
    test('недоступный сервер — через VPN', () {
      final s = foldRoutes(const AppSettings(), [
        _route(
          'a',
          sites: 'yt.example',
          target: RouteTarget.server,
          server: 'gone',
        ),
      ]);
      expect(routingEntries(s.proxyRules), ['yt.example']);
    });

    test('доступный сервер в общие списки не сворачивается', () {
      final s = foldRoutes(const AppSettings(), [
        _route(
          'a',
          sites: 'yt.example',
          target: RouteTarget.server,
          server: 'de',
        ),
      ], serverUsable: (r) => r.serverId == 'de');
      expect(s.proxyRules, isEmpty);
    });
  });

  test('ссылки на списки собираются из всех маршрутов без повторов', () {
    expect(
      routeListUrls([
        _route('a', sites: 'x.example, https://l.example/a.txt'),
        _route(
          'b',
          sites: 'https://l.example/a.txt\nhttps://l.example/b.txt',
          target: RouteTarget.block,
        ),
        _route('c', content: RouteContent.preset, preset: 'ads'),
      ]),
      ['https://l.example/a.txt', 'https://l.example/b.txt'],
    );
  });

  group('весь рунет напрямую', () {
    bool runet(String sites, [RouteTarget target = RouteTarget.direct]) =>
        routeSendsRunetDirect(_route('a', sites: sites, target: target));

    test('зоны в любом написании и geo-коды всей страны', () {
      for (final sites in [
        'ru, yandex.ru, vk.com',
        '.su',
        'domain:xn--p1ai',
        'РФ',
        'geoip:ru',
        'GeoSite:Category-RU',
      ]) {
        expect(runet(sites), isTrue, reason: sites);
      }
      expect(
        routeSendsRunetDirect(
          _route(
            'a',
            content: RouteContent.preset,
            preset: 'ru',
            target: RouteTarget.direct,
          ),
        ),
        isTrue,
      );
    });

    test('отдельные сайты, части страны и не «напрямую» не в счёт', () {
      for (final sites in [
        'yandex.ru, gosuslugi.ru',
        'geosite:category-gov-ru',
        'geoip:!ru',
        'full:ru.example',
      ]) {
        expect(runet(sites), isFalse, reason: sites);
      }
      expect(runet('ru', RouteTarget.vpn), isFalse);
      expect(runet('ru', RouteTarget.server), isFalse);
    });
  });

  test('маршрут переживает сохранение', () {
    final r = _route(
      'a',
      apps: ['chrome'],
      sites: 'yt.example',
      target: RouteTarget.server,
      server: 'de',
      enabled: false,
    );
    expect(TrafficRoute.fromJson(r.toJson()), r);
  });
}
