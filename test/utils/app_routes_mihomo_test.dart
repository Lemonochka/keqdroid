import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/traffic_route.dart';
import 'package:keqdroid/models/xray_core_settings.dart';
import 'package:keqdroid/tunnel/app_routing_mode.dart';
import 'package:keqdroid/tunnel/vpn_backend.dart';
import 'package:keqdroid/utils/app_routes.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';
import 'package:keqdroid/utils/route_servers.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

import '../helpers/mihomo_rules_sim.dart';

// Маршруты отдельных приложений на mihomo в десктопном TUN: правила по
// процессу между блокировкой и маршрутами всех приложений, как в ТЗ.
const _active = 'ss://YWVzLTI1Ni1nY206dGVzdHBhc3M@203.0.113.10:8388#nl';
const _de = 'ss://YWVzLTI1Ni1nY206dGVzdHBhc3M@198.51.100.7:8388#de';
const _discordPath = r'C:\Apps\Discord\Discord.exe';

const _settings = AppSettings(
  directRules: 'ru, yandex.ru',
  proxyRules: 'telegram.org',
  blockedRules: 'doubleclick.net',
);

final _servers = [
  ServerItem(id: 'nl', type: ServerItemType.manual, config: _active),
  ServerItem(id: 'de', type: ServerItemType.manual, config: _de),
];

TrafficRoute _route(
  String id, {
  required List<String> apps,
  RouteContent content = RouteContent.sites,
  String sites = '',
  RouteTarget target = RouteTarget.vpn,
  String serverId = '',
  bool enabled = true,
}) => TrafficRoute(
  id: id,
  apps: apps,
  content: content,
  sites: sites,
  target: target,
  serverId: serverId,
  enabled: enabled,
);

// Конфиг сессии так, как его собирает подключение: выходы серверов и
// маршруты приложений из одних и тех же маршрутов.
Map<String, dynamic> _config(
  List<TrafficRoute> routes, {
  AppSettings settings = _settings,
  MihomoTunOptions? tun = const MihomoTunOptions(
    device: 'tun-keqdis',
    stack: 'gvisor',
  ),
  String input = _active,
  Map<String, List<String>> listDomains = const {},
}) {
  final outbounds = routeServerOutbounds(
    routes: routes,
    servers: _servers,
    activeServerId: 'nl',
    core: VpnBackend.mihomo,
    withApps: true,
  );
  final apps = [
    for (final r in routeAppRules(
      routes: routes,
      outbounds: outbounds,
      windows: true,
    ))
      r.copyWith(listDomains: listDomains[r.entries]),
  ];
  return MihomoConfigGen.build(
    input,
    settings,
    socksPort: 2080,
    httpPort: 2081,
    tun: tun,
    appProcessName: 'keqdroid.exe',
    windows: true,
    routeServers: outbounds,
    appRoutes: apps,
  );
}

String _go(
  Map<String, dynamic> config,
  String process, {
  String host = '',
  String ip = '',
  String resolvesTo = '',
  String? path,
  String inType = 'TUN',
}) => simulateMihomo(
  config,
  SimConn(
    process: process,
    path: path,
    host: host,
    ip: ip,
    resolvesTo: resolvesTo,
    inType: inType,
  ),
);

List<String> _rules(Map<String, dynamic> c) =>
    (c['rules'] as List).cast<String>();

void main() {
  setUp(() => Socks5Credentials().init('u', 'p'));

  final chromeAll = _route(
    'chrome-all',
    apps: const ['chrome.exe'],
    content: RouteContent.allTraffic,
    target: RouteTarget.direct,
  );
  final chromeYoutube = _route(
    'chrome-yt',
    apps: const ['chrome.exe'],
    sites: 'youtube.com, googlevideo.com',
    target: RouteTarget.server,
    serverId: 'de',
  );
  final firefoxBlock = _route(
    'ff-block',
    apps: const ['firefox.exe'],
    sites: 'tracker.example',
    target: RouteTarget.block,
  );
  final discordAll = _route(
    'discord',
    apps: const [_discordPath],
    content: RouteContent.allTraffic,
    target: RouteTarget.server,
    serverId: 'de',
  );
  // Маршрут Весь трафик Chrome заведён раньше маршрута YouTube: порядок проверки от этого
  // не зависит.
  final routes = [chromeAll, chromeYoutube, firefoxBlock, discordAll];

  test('конфиг разбирается: у каждого правила есть цель', () {
    final c = _config(routes);
    expect(unknownMihomoTargets(c), isEmpty);
    expect(c['find-process-mode'], 'strict');
    expect((c['proxies'] as List).map((p) => p['name']), [
      MihomoConfigGen.proxyName,
      'keq-srv-0',
    ]);
  });

  test('сайты приложения раньше его «весь трафик»', () {
    final c = _config(routes);
    expect(_go(c, 'chrome.exe', host: 'youtube.com'), 'keq-srv-0');
    expect(_go(c, 'chrome.exe', host: 'rr1.googlevideo.com'), 'keq-srv-0');
    expect(_go(c, 'chrome.exe', host: 'example.com'), 'DIRECT');
    // Списки всех приложений до маршрута Весь трафик Chrome не доходят.
    expect(_go(c, 'chrome.exe', host: 'telegram.org'), 'DIRECT');
  });

  test('сайтов маршрута мало — приложение идёт по общим правилам', () {
    final c = _config([chromeYoutube]);
    expect(_go(c, 'chrome.exe', host: 'youtube.com'), 'keq-srv-0');
    expect(_go(c, 'chrome.exe', host: 'yandex.ru'), 'DIRECT');
    expect(_go(c, 'chrome.exe', host: 'telegram.org'), 'proxy');
    expect(_go(c, 'chrome.exe', host: 'example.com'), 'proxy');
  });

  test('блокировка действует и в приложении со своим маршрутом', () {
    final c = _config(routes);
    expect(_go(c, 'chrome.exe', host: 'doubleclick.net'), 'REJECT');
    expect(_go(c, 'firefox.exe', host: 'tracker.example'), 'REJECT');
    // Блок одного приложения других не трогает.
    expect(_go(c, 'chrome.exe', host: 'tracker.example'), 'DIRECT');
    expect(_go(c, 'firefox.exe', host: 'yandex.ru'), 'DIRECT');
    expect(_go(c, 'firefox.exe', host: 'example.com'), 'proxy');
  });

  test('другие приложения маршруты приложений не задевают', () {
    final c = _config(routes);
    expect(_go(c, 'msedge.exe', host: 'youtube.com'), 'proxy');
    expect(_go(c, 'msedge.exe', host: 'yandex.ru'), 'DIRECT');
    expect(_go(c, 'msedge.exe', host: 'doubleclick.net'), 'REJECT');
  });

  test('запись с путём — только этот файл', () {
    final c = _config(routes);
    expect(
      _go(c, 'Discord.exe', host: 'discord.com', path: _discordPath),
      'keq-srv-0',
    );
    expect(
      _go(c, 'Discord.exe', host: 'discord.com', path: r'D:\Old\Discord.exe'),
      'proxy',
    );
  });

  test('локальная сеть и сами серверы — напрямую при любом маршруте', () {
    final c = _config(routes);
    String discord(String ip) =>
        _go(c, 'Discord.exe', ip: ip, path: _discordPath);
    expect(discord('192.168.1.10'), 'DIRECT');
    expect(discord('10.0.0.5'), 'DIRECT');
    expect(discord('203.0.113.10'), 'DIRECT');
    expect(discord('198.51.100.7'), 'DIRECT');
    expect(discord('93.184.216.34'), 'keq-srv-0');
  });

  test('вход не из туннеля маршруты приложений не трогают', () {
    final c = _config(routes);
    expect(_go(c, 'chrome.exe', host: 'youtube.com', inType: 'HTTP'), 'proxy');
    expect(
      _go(c, 'keqdroid.exe', host: 'example.com', inType: 'HTTP'),
      'proxy',
    );
  });

  test('выключенный маршрут и маршрут без приложений не участвуют', () {
    final c = _config([
      _route(
        'off',
        apps: const ['chrome.exe'],
        content: RouteContent.allTraffic,
        target: RouteTarget.block,
        enabled: false,
      ),
      _route('blank', apps: const ['  '], sites: 'example.com'),
    ]);
    expect(
      _rules(c).where((r) => r.contains('chrome') || r.contains('SUB-RULE')),
      isEmpty,
    );
    expect(c.containsKey('sub-rules'), isFalse);
    expect(_go(c, 'chrome.exe', host: 'example.com'), 'proxy');
  });

  test('сервера маршрута нет — через VPN', () {
    final c = _config([
      _route(
        'gone',
        apps: const ['chrome.exe'],
        content: RouteContent.allTraffic,
        target: RouteTarget.server,
        serverId: 'deleted',
      ),
      _route(
        'active',
        apps: const ['firefox.exe'],
        content: RouteContent.allTraffic,
        target: RouteTarget.server,
        serverId: 'nl',
      ),
    ]);
    expect(unknownMihomoTargets(c), isEmpty);
    expect(_go(c, 'chrome.exe', host: 'yandex.ru'), 'proxy');
    expect(_go(c, 'firefox.exe', host: 'yandex.ru'), 'proxy');
    expect((c['proxies'] as List), hasLength(1));
  });

  test('сервер только у маршрута приложения тоже получает выход', () {
    final c = _config([discordAll]);
    expect((c['proxies'] as List).map((p) => p['name']), [
      MihomoConfigGen.proxyName,
      'keq-srv-0',
    ]);
    // Сайтов у выхода нет: маршрут Весь трафик для Discord не распространяется на другие приложения.
    expect(_go(c, 'chrome.exe', host: 'discord.com'), 'proxy');
  });

  test('скобки, запятые и пробелы в имени не ломают разбор', () {
    const odd = ['App (x86).exe', 'a,b.exe', 'My App.exe'];
    final c = _config([
      _route('odd', apps: odd, sites: 'example.com', target: RouteTarget.block),
    ]);
    expect(unknownMihomoTargets(c), isEmpty);
    for (final app in odd) {
      expect(_go(c, app, host: 'example.com'), 'REJECT', reason: app);
    }
    expect(_go(c, 'App x86.exe', host: 'example.com'), 'proxy');
  });

  test('скачанные списки маршрута — своим набором', () {
    const url = 'https://lists.example/games.txt';
    final c = _config(
      [
        _route(
          'games',
          apps: const ['steam.exe'],
          sites: url,
          target: RouteTarget.direct,
        ),
      ],
      listDomains: const {
        url: ['steampowered.com', 'steamcontent.com'],
      },
    );
    expect(unknownMihomoTargets(c), isEmpty);
    expect(_go(c, 'steam.exe', host: 'cdn.steamcontent.com'), 'DIRECT');
    expect(_go(c, 'steam.exe', host: 'example.com'), 'proxy');
    expect(_go(c, 'chrome.exe', host: 'steampowered.com'), 'proxy');
  });

  group('адреса в сайтах маршрута', () {
    final telegram = _route(
      'tg',
      apps: const ['Telegram.exe'],
      sites: '149.154.160.0/20, t.me',
      target: RouteTarget.server,
      serverId: 'de',
    );

    test('соединение по адресу — сразу', () {
      final c = _config([telegram]);
      expect(_go(c, 'Telegram.exe', ip: '149.154.167.51'), 'keq-srv-0');
      expect(_go(c, 'chrome.exe', ip: '149.154.167.51'), 'proxy');
    });

    test('по домену — после всех доменов, с резолвом', () {
      final c = _config([telegram]);
      expect(
        _go(
          c,
          'Telegram.exe',
          host: 'api.example',
          resolvesTo: '149.154.167.51',
        ),
        'keq-srv-0',
      );
      // Домен из общего списка решает раньше адреса маршрута.
      expect(
        _go(c, 'Telegram.exe', host: 'yandex.ru', resolvesTo: '149.154.167.51'),
        'DIRECT',
      );
      expect(
        _go(c, 'chrome.exe', host: 'api.example', resolvesTo: '149.154.167.51'),
        'proxy',
      );
      expect(unknownMihomoTargets(c), isEmpty);
    });

    test('при «резолвить по требованию» хвоста нет, резолв на месте', () {
      final c = _config(
        [telegram],
        settings: _settings.copyWith(
          xrayCore: const XrayCoreSettings(routingDomainStrategy: 'IPOnDemand'),
        ),
      );
      expect((c['sub-rules'] as Map).keys, ['keq-app-0']);
      expect(
        _go(
          c,
          'Telegram.exe',
          host: 'api.example',
          resolvesTo: '149.154.167.51',
        ),
        'keq-srv-0',
      );
    });
  });

  test('без туннеля маршрутов приложений нет', () {
    final c = _config(routes, tun: null);
    expect(c.containsKey('sub-rules'), isFalse);
    expect(_rules(c).any((r) => r.contains('PROCESS-')), isFalse);
    expect(c['find-process-mode'], 'off');
    expect(unknownMihomoTargets(c), isEmpty);
  });

  group('Android: туннель из VpnService', () {
    const fdTun = MihomoTunOptions(
      fromFileDescriptor: true,
      stack: 'gvisor',
      autoRoute: false,
    );
    final telegramAll = _route(
      'tg',
      apps: const ['org.telegram.messenger'],
      content: RouteContent.allTraffic,
      target: RouteTarget.server,
      serverId: 'de',
    );
    final chromeYoutube = _route(
      'chrome-yt',
      apps: const ['com.android.chrome'],
      sites: 'youtube.com',
      target: RouteTarget.direct,
    );

    Map<String, dynamic> android(List<TrafficRoute> routes) {
      final outbounds = routeServerOutbounds(
        routes: routes,
        servers: _servers,
        activeServerId: 'nl',
        core: VpnBackend.mihomo,
        withApps: true,
      );
      return MihomoConfigGen.build(
        _active,
        _settings,
        socksPort: 2080,
        httpPort: 2081,
        tun: fdTun,
        routingMode: AppRoutingMode.onlySelected,
        managedProcessNames: const ['org.telegram.messenger'],
        windows: false,
        routeServers: outbounds,
        appRoutes: routeAppRules(
          routes: routes,
          outbounds: outbounds,
          windows: false,
        ),
      );
    }

    test('маршруты по имени пакета, поиск владельца включён', () {
      final c = android([telegramAll, chromeYoutube]);
      expect(unknownMihomoTargets(c), isEmpty);
      expect(c['find-process-mode'], 'strict');
      expect(
        _go(c, 'org.telegram.messenger', host: 'telegram.org'),
        'keq-srv-0',
      );
      expect(_go(c, 'com.android.chrome', host: 'youtube.com'), 'DIRECT');
      expect(_go(c, 'com.android.chrome', host: 'example.com'), 'proxy');
      expect(
        _go(c, 'org.telegram.messenger.web', host: 'telegram.org'),
        'proxy',
      );
      expect(
        _go(c, 'org.telegram.messenger', host: 'doubleclick.net'),
        'REJECT',
      );
    });

    test('сплит исполняет VpnService, его правил в ядре нет', () {
      final c = android([telegramAll]);
      expect(_rules(c).any((r) => r.contains('(?!')), isFalse);
      expect(_go(c, 'com.other.app', host: 'example.com'), 'proxy');
    });

    test('без маршрутов приложений владельца не ищет', () {
      final c = android(const []);
      expect(c['find-process-mode'], 'off');
      expect(_rules(c).any((r) => r.contains('PROCESS-')), isFalse);
    });
  });

  group('готовый Clash-конфиг', () {
    const clash = '''
proxies:
  - {name: p1, type: ss, server: 203.0.113.10, port: 8388, cipher: aes-256-gcm, password: x}
proxy-groups:
  - {name: G, type: select, proxies: [p1]}
sub-rules:
  author-set:
    - DOMAIN-SUFFIX,author-sub.example,DIRECT
rules:
  - SUB-RULE,(NETWORK,TCP),author-set
  - DOMAIN-SUFFIX,author-direct.example,DIRECT
  - MATCH,G
''';

    test('маршруты приложений — после правил автора, его наборы целы', () {
      final c = _config(
        [chromeYoutube, firefoxBlock],
        input: clash,
        settings: _settings.copyWith(lanSharing: true),
      );
      expect(unknownMihomoTargets(c), isEmpty);
      expect(
        (c['sub-rules'] as Map).keys,
        containsAll(['author-set', MihomoConfigGen.lanRuleSet, 'keq-app-0']),
      );
      expect(_go(c, 'chrome.exe', host: 'author-sub.example'), 'DIRECT');
      expect(_go(c, 'chrome.exe', host: 'author-direct.example'), 'DIRECT');
      expect(_go(c, 'chrome.exe', host: 'youtube.com'), 'keq-srv-0');
      expect(_go(c, 'firefox.exe', host: 'tracker.example'), 'REJECT');
      expect(_go(c, 'firefox.exe', host: 'example.com'), 'G');
    });
  });
}
