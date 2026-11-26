import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/services/connections_service.dart';
import 'package:keqdroid/services/subscription_body_parser.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:keqdroid/utils/clash_template.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

// смена сервера при живой сессии: по умолчанию стоп и старт, у mihomo подмена конфига на ходу

class _SwitchBackend extends FakeTunnelBackend {
  final calls = <String>[];
  final sessions = <TunnelSessionRequest>[];
  final _states = StreamController<VpnState>.broadcast();
  VpnState current = VpnState.disconnected;
  bool? reloads;
  int credsFetched = 0;
  final reloaded = <TunnelSessionRequest>[];

  @override
  Future<({String username, String password})> fetchSocksCredentials() async {
    credsFetched++;
    return (username: 'u$credsFetched', password: 'p$credsFetched');
  }

  @override
  Future<bool> reloadMihomoConfig(TunnelSessionRequest request) async {
    final ok = reloads;
    if (ok == null) return super.reloadMihomoConfig(request);
    calls.add('reload');
    reloaded.add(request);
    return ok;
  }

  @override
  Stream<VpnState> get stateStream => _states.stream;

  @override
  Future<VpnState> getCurrentState() async => current;

  @override
  Future<void> startSession(TunnelSessionRequest request) async {
    calls.add('start');
    sessions.add(request);
    current = const VpnState(status: VpnStatus.connected);
  }

  @override
  Future<void> stopSession() async {
    calls.add('stop');
    current = VpnState.disconnected;
    _states.add(VpnState.disconnected);
  }

  @override
  void dispose() {
    unawaited(_states.close());
    super.dispose();
  }
}

ServerItem _server(String id, String host) => ServerItem(
  id: id,
  type: ServerItemType.manual,
  config:
      'vless://00000000-0000-4000-8000-000000000000@$host:443'
      '?type=tcp&security=tls&sni=$host#$id',
);

final _a = _server('a', 'a.example.com');
final _b = _server('b', 'b.example.com');

Future<ProviderContainer> _connected(
  _SwitchBackend backend, {
  String core = AppSettings.vpnCoreMihomo,
}) async {
  final storage = await buildStorageService();
  await storage.saveServers([_a, _b]);
  await storage.setActiveServerId(_a.id);
  await storage.saveSettings(AppSettings(vpnCore: core));
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
  expect(container.read(vpnStateProvider).value?.status, VpnStatus.connected);
  backend.calls.clear();
  return container;
}

Future<void> _switchTo(ProviderContainer container, ServerItem server) async {
  await container.read(serversProvider.notifier).setActive(server);
  await container.read(vpnStateProvider.notifier).reconnectToActiveServer();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'на xray смена сервера останавливает сессию и поднимает новую',
    () async {
      final backend = _SwitchBackend();
      final container = await _connected(
        backend,
        core: AppSettings.vpnCoreXray,
      );

      await _switchTo(container, _b);

      expect(backend.calls, ['stop', 'start']);
      expect(backend.sessions.last.xrayConfig, contains('b.example.com'));
      expect(
        container.read(vpnStateProvider).value?.status,
        VpnStatus.connected,
      );
    },
  );

  test('mihomo меняет сервер на ходу, туннель не снимается', () async {
    final backend = _SwitchBackend()..reloads = true;
    final container = await _connected(backend);
    final first = backend.sessions.single;
    final statuses = <VpnStatus?>[];
    container.listen(
      vpnStateProvider,
      (_, next) => statuses.add(next.value?.status),
    );

    await _switchTo(container, _b);

    expect(backend.calls, ['reload']);
    final next = backend.reloaded.single;
    expect(next.mihomoConfig, contains('b.example.com'));
    expect(next.mihomoConfig, isNot(contains('a.example.com')));
    expect(next.serverName, 'b');
    expect(next.socksPort, first.socksPort);
    expect(next.httpPort, first.httpPort);
    expect(backend.credsFetched, 1, reason: 'креды работающего ядра');
    expect(statuses, isNot(contains(VpnStatus.disconnecting)));
    expect(container.read(vpnStateProvider).value?.status, VpnStatus.connected);

    // вторая смена тоже на ходу и от той же сессии
    await _switchTo(container, _a);
    expect(backend.calls, ['reload', 'reload']);
    expect(backend.reloaded.last.mihomoConfig, contains('a.example.com'));
  });

  test('ядро отказалось от конфига: смена идёт стопом и стартом', () async {
    final backend = _SwitchBackend()..reloads = false;
    final container = await _connected(backend);

    await _switchTo(container, _b);

    expect(backend.calls, ['reload', 'stop', 'start']);
    expect(backend.sessions.last.mihomoConfig, contains('b.example.com'));
    expect(container.read(vpnStateProvider).value?.status, VpnStatus.connected);
  });

  test('другой режим туннеля на ходу не меняют', () async {
    final backend = _SwitchBackend()..reloads = true;
    final container = await _connected(backend);
    final storage = container.read(storageProvider);
    final settings = await storage.getSettings();
    await storage.saveSettings(
      settings.copyWith(
        connectionMode: settings.connectionMode == 'tun' ? 'proxy' : 'tun',
      ),
    );

    await _switchTo(container, _b);

    expect(backend.calls, ['stop', 'start']);
  });

  test('ядро сменилось на xray: стоп и старт', () async {
    final backend = _SwitchBackend()..reloads = true;
    final container = await _connected(backend);
    final storage = container.read(storageProvider);
    await storage.saveSettings(
      (await storage.getSettings()).copyWith(vpnCore: AppSettings.vpnCoreXray),
    );

    await _switchTo(container, _b);

    expect(backend.calls, ['stop', 'start']);
    expect(backend.sessions.last.xrayConfig, contains('b.example.com'));
  });

  test('mihomo без подмены на ходу меняет сервер стопом и стартом', () async {
    final backend = _SwitchBackend();
    final container = await _connected(backend);

    await _switchTo(container, _b);

    expect(backend.calls, ['stop', 'start']);
    expect(backend.sessions.last.mihomoConfig, contains('b.example.com'));
    expect(container.read(vpnStateProvider).value?.status, VpnStatus.connected);
  });

  test(
    'смена сервера на ходу заново закрепляет выбранный узел в группе шаблона Clash',
    () async {
      final prevOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = prevOverrides);

      final putCalls = <({String path, String body})>[];

      final rawTemplate = File(
        'test/fixtures/subscription_payloads/clash-template-groups.txt',
      ).readAsStringSync();
      final template = ClashTemplate.fromBody(rawTemplate)!;
      final templatedServers = [
        for (final c in SubscriptionBodyParser.parseBody(rawTemplate))
          ServerItem.fromRaw(c, subscriptionId: 's1'),
      ];

      final storage = await buildStorageService(
        initialValues: {
          'keqdis_clash_template_s1': template.encode(),
        },
      );
      await storage.saveSubscriptions([
        Subscription(
          id: 's1',
          name: 'Sub',
          url: 'https://example.com/s1',
          groupChoices: const {'Любой доступный': '🇱🇻 Latvia'},
        ),
      ]);
      await storage.saveServers(templatedServers);
      await storage.setActiveServerId(templatedServers[0].id);
      await storage.saveSettings(
        const AppSettings(vpnCore: AppSettings.vpnCoreMihomo),
      );

      final backend = _SwitchBackend()..reloads = true;
      final container = ProviderContainer(
        overrides: [
          storageProvider.overrideWithValue(storage),
          vpnEngineProvider.overrideWithValue(VpnEngine.withBackend(backend)),
        ],
      );
      addTearDown(container.dispose);

      container.read(serversProvider);
      await container.read(subscriptionsProvider.future);
      await container.read(vpnStateProvider.future);
      await container.read(vpnStateProvider.notifier).connect();
      backend.calls.clear();

      final apiServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      ConnectionsService.debugClashPort = apiServer.port;
      addTearDown(() async {
        ConnectionsService.debugClashPort = null;
        await apiServer.close();
      });
      apiServer.listen((req) async {
        final body = await utf8.decoder.bind(req).join();
        if (req.method == 'PUT') {
          putCalls.add((path: req.uri.path, body: body));
        }
        req.response.statusCode = 204;
        await req.response.close();
      });

      await _switchTo(container, templatedServers[1]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(backend.calls, ['reload']);
      expect(
        putCalls.any(
          (c) =>
              Uri.decodeComponent(c.path) == '/proxies/Любой доступный' &&
              c.body.contains('Latvia'),
        ),
        isTrue,
        reason: 'PUT /configs сбрасывает группы шаблона, пин нужно прислать заново',
      );
    },
  );
}
