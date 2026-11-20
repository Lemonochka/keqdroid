import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/traffic_route.dart';
import 'package:keqdroid/tunnel/vpn_backend.dart';
import 'package:keqdroid/utils/app_routes.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/route_servers.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

import '../helpers/xray_rules_sim.dart';

// маршруты приложений на xray под Android: правила с process на входе tun-in,
// в том же порядке, что у mihomo
const _active =
    'vless://00000000-0000-4000-8000-000000000000@203.0.113.10:443'
    '?type=tcp&security=tls&sni=nl.example#NL';
const _de = 'trojan://pw@198.51.100.7:443?security=tls&sni=de.example#DE';

const _settings = AppSettings(
  directRules: 'ru, yandex.ru',
  proxyRules: 'telegram.org',
  blockedRules: 'doubleclick.net',
);

final _servers = [
  ServerItem(id: 'nl', type: ServerItemType.manual, config: _active),
  ServerItem(id: 'de', type: ServerItemType.manual, config: _de),
];

const _chrome = 'com.android.chrome';
const _firefox = 'org.mozilla.firefox';
const _discord = 'com.discord';
const _telegram = 'org.telegram.messenger';

TrafficRoute _route(
  String id, {
  required List<String> apps,
  RouteContent content = RouteContent.sites,
  String sites = '',
  RouteTarget target = RouteTarget.vpn,
  String serverId = '',
}) => TrafficRoute(
  id: id,
  apps: apps,
  content: content,
  sites: sites,
  target: target,
  serverId: serverId,
);

final _chromeAll = _route(
  'chrome-all',
  apps: const [_chrome],
  content: RouteContent.allTraffic,
  target: RouteTarget.direct,
);
final _chromeYoutube = _route(
  'chrome-yt',
  apps: const [_chrome],
  sites: 'youtube.com, googlevideo.com',
  target: RouteTarget.server,
  serverId: 'de',
);
final _firefoxBlock = _route(
  'ff-block',
  apps: const [_firefox],
  sites: 'tracker.example',
  target: RouteTarget.block,
);
final _discordAll = _route(
  'discord',
  apps: const [_discord],
  content: RouteContent.allTraffic,
  target: RouteTarget.server,
  serverId: 'de',
);
final _routes = [_chromeAll, _chromeYoutube, _firefoxBlock, _discordAll];

Map<String, dynamic> _config(
  List<TrafficRoute> routes, {
  String input = _active,
  bool tun = true,
  Map<String, List<String>> listDomains = const {},
}) {
  Socks5Credentials().init('u', 'p');
  final outbounds = routeServerOutbounds(
    routes: routes,
    servers: _servers,
    activeServerId: 'nl',
    core: VpnBackend.xray,
    withApps: true,
  );
  final apps = [
    for (final r in routeAppRules(
      routes: routes,
      outbounds: outbounds,
      windows: false,
    ))
      r.copyWith(listDomains: listDomains[r.entries]),
  ];
  return jsonDecode(
        ConfigGeneratorV2.generateConfig(
          input,
          _settings,
          nativeTunInbound: tun,
          routeServers: outbounds,
          appRoutes: apps,
        ),
      )
      as Map<String, dynamic>;
}

List<Map<String, dynamic>> _rules(Map<String, dynamic> c) => [
  for (final r in (c['routing'] as Map)['rules'] as List)
    (r as Map).cast<String, dynamic>(),
];

String? _go(
  Map<String, dynamic> c,
  String app, {
  String host = '',
  String ip = '',
  String resolvesTo = '',
  String inbound = 'tun-in',
}) => simulateXray(
  c,
  XrayConn(
    inbound: inbound,
    process: app,
    host: host,
    ip: ip,
    resolvesTo: resolvesTo,
  ),
);

void main() {
  test('правило — вход туннеля, приложения и выход', () {
    final rules = _rules(_config([_chromeYoutube]));
    final rule = rules.singleWhere((r) => r['ruleTag'] == 'keq-app-0-domains');
    expect(rule['inboundTag'], ['tun-in']);
    expect(rule['process'], [_chrome]);
    expect(rule['domain'], ['domain:youtube.com', 'domain:googlevideo.com']);
    expect(rule['outboundTag'], 'keq-srv-0');
  });

  test(
    'порядок: блок, сам сервер, частные сети, приложения, все приложения',
    () {
      final tags = [for (final r in _rules(_config(_routes))) r['ruleTag']];
      int at(String tag) {
        final i = tags.indexOf(tag);
        expect(i, isNot(-1), reason: tag);
        return i;
      }

      expect(at('block-domains'), lessThan(at('keq-app-0-domains')));
      expect(at('keq-app-0-domains'), lessThan(at('server-ip')));
      expect(at('route-server-0'), lessThan(at('app-private')));
      expect(at('app-private'), lessThan(at('keq-app-1-domains')));
      expect(at('keq-app-1-domains'), lessThan(at('keq-app-2')));
      expect(at('keq-app-3'), lessThan(at('direct-domains')));
      expect(at('direct-domains'), lessThan(at('proxy-domains')));
    },
  );

  test('сайты приложения раньше его «весь трафик»', () {
    final c = _config(_routes);
    expect(_go(c, _chrome, host: 'youtube.com'), 'keq-srv-0');
    expect(_go(c, _chrome, host: 'rr1.googlevideo.com'), 'keq-srv-0');
    expect(_go(c, _chrome, host: 'example.com'), 'direct');
    expect(_go(c, _chrome, host: 'telegram.org'), 'direct');
  });

  test('блокировка действует и в приложении со своим маршрутом', () {
    final c = _config(_routes);
    expect(_go(c, _chrome, host: 'doubleclick.net'), 'block');
    expect(_go(c, _firefox, host: 'tracker.example'), 'block');
    expect(_go(c, _chrome, host: 'tracker.example'), 'direct');
    expect(_go(c, _firefox, host: 'yandex.ru'), 'direct');
    expect(_go(c, _firefox, host: 'example.com'), 'proxy');
  });

  test('другие приложения и вход приложения маршруты не задевают', () {
    final c = _config(_routes);
    expect(_go(c, 'com.other', host: 'youtube.com'), 'proxy');
    expect(_go(c, 'com.other', host: 'doubleclick.net'), 'block');
    expect(_go(c, _chrome, host: 'youtube.com', inbound: 'http-in'), 'proxy');
  });

  test('локальная сеть и сами серверы — напрямую при любом маршруте', () {
    final c = _config(_routes);
    expect(_go(c, _discord, ip: '192.168.1.10'), 'direct');
    expect(_go(c, _discord, ip: '10.0.0.5'), 'direct');
    expect(_go(c, _discord, ip: '203.0.113.10'), 'direct');
    expect(_go(c, _discord, ip: '198.51.100.7'), 'direct');
    expect(_go(c, _discord, ip: '93.184.216.34'), 'keq-srv-0');
  });

  test('адрес в сайтах маршрута: по адресу сразу, по домену после резолва', () {
    final c = _config([
      _route(
        'tg',
        apps: const [_telegram],
        sites: '149.154.160.0/20, t.me',
        target: RouteTarget.server,
        serverId: 'de',
      ),
    ]);
    expect((c['routing'] as Map)['domainStrategy'], 'IPIfNonMatch');
    expect(_go(c, _telegram, ip: '149.154.167.51'), 'keq-srv-0');
    expect(
      _go(c, _telegram, host: 'api.example', resolvesTo: '149.154.167.51'),
      'keq-srv-0',
    );
    expect(
      _go(c, _telegram, host: 'yandex.ru', resolvesTo: '149.154.167.51'),
      'direct',
    );
    expect(
      _go(c, 'com.other', host: 'api.example', resolvesTo: '149.154.167.51'),
      'proxy',
    );
  });

  test('скачанные списки маршрута — в его же правиле', () {
    const url = 'https://lists.example/games.txt';
    final c = _config(
      [
        _route(
          'games',
          apps: const ['com.valvesoftware.android.steam.community'],
          sites: url,
          target: RouteTarget.direct,
        ),
      ],
      listDomains: const {
        url: ['steampowered.com'],
      },
    );
    expect(
      _go(
        c,
        'com.valvesoftware.android.steam.community',
        host: 'store.steampowered.com',
      ),
      'direct',
    );
    expect(_go(c, _chrome, host: 'store.steampowered.com'), 'proxy');
  });

  test('без своего туннеля правил по приложениям нет', () {
    final c = _config(_routes, tun: false);
    expect(_rules(c).where((r) => r.containsKey('process')), isEmpty);
    expect(_rules(c).where((r) => r['ruleTag'] == 'app-private'), isEmpty);
  });

  test('готовый JSON: после правил автора, на его выходы', () {
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
    final c = _config(_routes, input: custom);
    final outbounds = {
      for (final o in c['outbounds'] as List) (o as Map)['tag'],
    };
    for (final r in _rules(c)) {
      expect(outbounds, contains(r['outboundTag']), reason: '${r['ruleTag']}');
    }
    expect(_go(c, _chrome, host: 'author.example'), 'my-direct');
    expect(_go(c, _chrome, host: 'youtube.com'), 'keq-srv-0');
    expect(_go(c, _chrome, host: 'example.com'), 'my-direct');
    expect(_go(c, _firefox, host: 'tracker.example'), isNot('my-proxy'));
    expect(_go(c, _discord, ip: '192.168.1.10'), 'my-direct');
  });
}
