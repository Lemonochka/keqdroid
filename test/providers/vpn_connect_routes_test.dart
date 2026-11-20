import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/traffic_route.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/services/vpn_engine.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

/// Подключение собирает конфиг из маршрутов. Прежние поля списков после
/// переноса не читает никто: иначе удалённый маршрут продолжал бы работать
/// из старого поля.
class _Backend extends FakeTunnelBackend {
  VpnState current = VpnState.disconnected;
  TunnelSessionRequest? session;

  @override
  Future<VpnState> getCurrentState() async => current;

  @override
  Future<void> startSession(TunnelSessionRequest request) async {
    session = request;
    current = const VpnState(status: VpnStatus.connected);
  }
}

final _server = ServerItem(
  id: 'srv-1',
  type: ServerItemType.manual,
  config:
      'vless://00000000-0000-4000-8000-000000000000@198.51.100.10:443'
      '?type=tcp&security=none#test',
);

List<Map<String, dynamic>> _rules(String xray) => [
  for (final r
      in ((jsonDecode(xray) as Map)['routing'] as Map)['rules'] as List)
    (r as Map).cast<String, dynamic>(),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('в сессию едут маршруты, а не прежние поля списков', () async {
    final backend = _Backend();
    final storage = await buildStorageService();
    await storage.saveServers([_server]);
    await storage.setActiveServerId(_server.id);
    await storage.saveSettings(
      const AppSettings(
        directRules: 'legacy-direct.example',
        blockedRules: 'legacy-block.example',
      ),
    );
    await storage.saveRoutes(const [
      TrafficRoute(
        id: 'a',
        sites: 'route-direct.example',
        target: RouteTarget.direct,
      ),
      TrafficRoute(
        id: 'b',
        sites: 'route-block.example',
        target: RouteTarget.block,
      ),
      TrafficRoute(
        id: 'c',
        sites: 'route-off.example',
        target: RouteTarget.vpn,
        enabled: false,
      ),
    ]);

    final container = ProviderContainer(
      overrides: [
        storageProvider.overrideWithValue(storage),
        vpnEngineProvider.overrideWithValue(VpnEngine.withBackend(backend)),
      ],
    );
    addTearDown(container.dispose);
    container.read(serversProvider);
    await container.read(vpnStateProvider.future);

    await container.read(vpnStateProvider.notifier).connect();

    final xray = backend.session!.xrayConfig;
    List<String> domainsOf(String tag) => [
      for (final r in _rules(xray))
        if (r['ruleTag'] == tag) ...(r['domain'] as List).cast<String>(),
    ];
    expect(domainsOf('direct-domains'), ['domain:route-direct.example']);
    expect(domainsOf('block-domains'), ['domain:route-block.example']);
    expect(xray, isNot(contains('legacy-')));
    expect(xray, isNot(contains('route-off.example')));
  });

  // «Другой сервер»: свой аутбаунд для сервера из маршрута. Сервер, которого
  // больше нет, — её решение: такой маршрут идёт через текущий сервер.
  test(
    'маршрут на другой сервер едет своим выходом, на пропавший — через VPN',
    () async {
      final backend = _Backend();
      final storage = await buildStorageService();
      final de = ServerItem(
        id: 'srv-de',
        type: ServerItemType.manual,
        config: 'trojan://pw@de.example:443?security=tls&sni=de.example#DE',
      );
      await storage.saveServers([_server, de]);
      await storage.setActiveServerId(_server.id);
      await storage.saveRoutes(const [
        TrafficRoute(
          id: 'to-de',
          sites: 'youtube.com',
          target: RouteTarget.server,
          serverId: 'srv-de',
        ),
        TrafficRoute(
          id: 'to-gone',
          sites: 'twitch.tv',
          target: RouteTarget.server,
          serverId: 'srv-gone',
        ),
      ]);

      final container = ProviderContainer(
        overrides: [
          storageProvider.overrideWithValue(storage),
          vpnEngineProvider.overrideWithValue(VpnEngine.withBackend(backend)),
        ],
      );
      addTearDown(container.dispose);
      container.read(serversProvider);
      await container.read(vpnStateProvider.future);

      await container.read(vpnStateProvider.notifier).connect();

      final config = jsonDecode(backend.session!.xrayConfig) as Map;
      final outbounds = [
        for (final o in config['outbounds'] as List) (o as Map)['tag'],
      ];
      expect(outbounds, contains('keq-srv-0'));
      final rules = _rules(backend.session!.xrayConfig);
      final toDe = rules.firstWhere((r) => r['ruleTag'] == 'keq-srv-0-domains');
      expect(toDe['domain'], ['domain:youtube.com']);
      expect(toDe['outboundTag'], 'keq-srv-0');
      final viaVpn = rules.firstWhere((r) => r['ruleTag'] == 'proxy-domains');
      expect(viaVpn['domain'], ['domain:twitch.tv']);
    },
  );

  // Отдельные приложения: только mihomo в своём туннеле на ПК, как обещает
  // экран. В режиме прокси ядро не узнает процесс, и правил нет вовсе.
  group('маршрут приложения', () {
    Future<_Backend> connectWith(String connectionMode) async {
      final backend = _Backend();
      final storage = await buildStorageService();
      final de = ServerItem(
        id: 'srv-de',
        type: ServerItemType.manual,
        config: 'trojan://pw@de.example:443?security=tls&sni=de.example#DE',
      );
      await storage.saveServers([_server, de]);
      await storage.setActiveServerId(_server.id);
      await storage.saveSettings(
        AppSettings(
          vpnCore: AppSettings.vpnCoreMihomo,
          connectionMode: connectionMode,
        ),
      );
      await storage.saveRoutes(const [
        TrafficRoute(
          id: 'chrome',
          apps: ['chrome.exe'],
          sites: 'youtube.com',
          target: RouteTarget.server,
          serverId: 'srv-de',
        ),
      ]);
      final container = ProviderContainer(
        overrides: [
          storageProvider.overrideWithValue(storage),
          vpnEngineProvider.overrideWithValue(VpnEngine.withBackend(backend)),
        ],
      );
      addTearDown(container.dispose);
      container.read(serversProvider);
      await container.read(vpnStateProvider.future);
      await container.read(vpnStateProvider.notifier).connect();
      return backend;
    }

    test('в TUN — правило по процессу на свой сервер', () async {
      final backend = await connectWith('tun');
      final config =
          jsonDecode(backend.session!.mihomoConfig!) as Map<String, dynamic>;
      final rules = (config['rules'] as List).cast<String>();
      expect(
        rules.where((r) => r.startsWith('SUB-RULE,') && r.contains('chrome')),
        hasLength(1),
      );
      expect((config['sub-rules'] as Map)['keq-app-0'], [
        'DOMAIN-SUFFIX,youtube.com,keq-srv-0',
      ]);
      expect(
        (config['proxies'] as List).map((p) => (p as Map)['name']),
        contains('keq-srv-0'),
      );
    });

    test('в режиме прокси правил по процессу нет', () async {
      final backend = await connectWith('proxy');
      final config = backend.session!.mihomoConfig!;
      expect(config, isNot(contains('chrome')));
      expect(config, isNot(contains('keq-srv-0')));
    });
  });
}
