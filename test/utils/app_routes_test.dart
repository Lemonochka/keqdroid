import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/traffic_route.dart';
import 'package:keqdroid/tunnel/connection_mode.dart';
import 'package:keqdroid/tunnel/vpn_backend.dart';
import 'package:keqdroid/utils/app_routes.dart';
import 'package:keqdroid/utils/route_servers.dart';

const _de = 'trojan://pw@de.example:443?security=tls&sni=de.example#DE';
const _nl = 'trojan://pw@nl.example:443?security=tls&sni=nl.example#NL';

final _servers = [
  ServerItem(id: 'nl', type: ServerItemType.manual, config: _nl),
  ServerItem(id: 'de', type: ServerItemType.manual, config: _de),
];

TrafficRoute _app(
  String id,
  List<String> apps, {
  RouteContent content = RouteContent.sites,
  String sites = 'example.com',
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

void main() {
  group('appRoutesRun', () {
    // владельца соединения xray и mihomo узнают у своего TUN на любой платформе
    test('в TUN да, в режиме прокси нет', () {
      expect(appRoutesRun(ConnectionMode.tun), isTrue);
      expect(appRoutesRun(ConnectionMode.proxy), isFalse);
    });
  });

  group('routeAppRules', () {
    test('блокировка, затем сайты, затем «весь трафик»', () {
      final rules = routeAppRules(
        routes: [
          _app('all', ['chrome.exe'], content: RouteContent.allTraffic),
          _app('sites', ['chrome.exe'], sites: 'youtube.com'),
          _app('block', ['firefox.exe'], target: RouteTarget.block),
          _app('every', const [], sites: 'vk.com'),
        ],
        outbounds: const [],
        windows: true,
      );
      expect(rules.map((r) => r.target), [
        RouteTarget.block,
        RouteTarget.vpn,
        RouteTarget.vpn,
      ]);
      expect(rules.map((r) => r.allTraffic), [false, false, true]);
      expect(rules.map((r) => r.tag), ['keq-app-0', 'keq-app-1', 'keq-app-2']);
      expect(rules[1].entries, 'youtube.com');
    });

    test('имена и пути — как их видит ядро, без повторов и пустых', () {
      final rules = routeAppRules(
        routes: [
          _app('r', [
            'Chrome',
            'chrome.exe',
            '  ',
            r'"C:\Program Files\App\app.exe"',
          ]),
        ],
        outbounds: const [],
        windows: true,
      );
      expect(rules.single.apps, [
        'Chrome.exe',
        r'C:\Program Files\App\app.exe',
      ]);
    });

    test('выключенные, пустые и без приложений пропускаются', () {
      final rules = routeAppRules(
        routes: [
          _app('off', ['a.exe'], enabled: false),
          _app('empty', ['a.exe'], sites: ' , '),
          _app('blank', ['  ']),
        ],
        outbounds: const [],
        windows: true,
      );
      expect(rules, isEmpty);
    });

    test('сервер — выход из outbounds, нет выхода — через VPN', () {
      final routes = [
        _app('de', ['a.exe'], target: RouteTarget.server, serverId: 'de'),
        _app('active', ['b.exe'], target: RouteTarget.server, serverId: 'nl'),
        _app('gone', ['c.exe'], target: RouteTarget.server, serverId: 'x'),
      ];
      final outbounds = routeServerOutbounds(
        routes: routes,
        servers: _servers,
        activeServerId: 'nl',
        core: VpnBackend.mihomo,
        withApps: true,
      );
      expect(outbounds.map((o) => o.serverId), ['de']);
      expect(outbounds.single.entries, isEmpty);
      final rules = routeAppRules(routes: routes, outbounds: outbounds);
      expect(rules.map((r) => r.serverTag), ['keq-srv-0', '', '']);
    });
  });

  group('routeServerOutbounds', () {
    test('без withApps маршруты приложений выхода не получают', () {
      final routes = [
        _app('de', ['a.exe'], target: RouteTarget.server, serverId: 'de'),
      ];
      expect(
        routeServerOutbounds(
          routes: routes,
          servers: _servers,
          activeServerId: 'nl',
          core: VpnBackend.mihomo,
        ),
        isEmpty,
      );
    });

    test('сайты маршрутов приложений в общий выход не попадают', () {
      final outbounds = routeServerOutbounds(
        routes: [
          _app(
            'every',
            const [],
            sites: 'vk.com',
            target: RouteTarget.server,
            serverId: 'de',
          ),
          _app(
            'app',
            ['a.exe'],
            sites: 'youtube.com',
            target: RouteTarget.server,
            serverId: 'de',
          ),
        ],
        servers: _servers,
        activeServerId: 'nl',
        core: VpnBackend.mihomo,
        withApps: true,
      );
      expect(outbounds.single.entries, 'vk.com');
    });
  });

  group('appsOutsideSplit', () {
    test('без сплита — никого', () {
      expect(
        appsOutsideSplit(['a.exe'], include: const {}, exclude: const {}),
        isEmpty,
      );
    });

    test('«все, кроме выбранных»: исключённые', () {
      expect(
        appsOutsideSplit(
          ['Discord.exe', 'chrome.exe'],
          include: const {},
          exclude: const {'discord.exe'},
          windows: true,
        ),
        ['Discord.exe'],
      );
    });

    test('«только выбранные»: не выбранные', () {
      expect(
        appsOutsideSplit(
          ['firefox.exe', 'chrome.exe'],
          include: const {'Firefox.exe'},
          exclude: const {},
          windows: true,
        ),
        ['chrome.exe'],
      );
    });

    test('имя при выбранном пути того же файла считается пропущенным', () {
      expect(
        appsOutsideSplit(
          ['firefox.exe'],
          include: const {r'C:\Program Files\Mozilla Firefox\firefox.exe'},
          exclude: const {},
          windows: true,
        ),
        isEmpty,
      );
      // А путь к другому файлу того же имени уже нет.
      expect(
        appsOutsideSplit(
          [r'D:\Portable\firefox.exe'],
          include: const {r'C:\Program Files\Mozilla Firefox\firefox.exe'},
          exclude: const {},
          windows: true,
        ),
        [r'D:\Portable\firefox.exe'],
      );
    });

    test('путь при выбранном имени — пропущен', () {
      expect(
        appsOutsideSplit(
          [r'D:\Portable\firefox.exe'],
          include: const {'firefox.exe'},
          exclude: const {},
          windows: true,
        ),
        isEmpty,
      );
    });
  });
}
