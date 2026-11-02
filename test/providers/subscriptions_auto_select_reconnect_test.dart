import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/services/auto_select_home.dart';
import 'package:keqdroid/services/subscription_service.dart';
import 'package:keqdroid/services/vpn_engine.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

class _Backend extends FakeTunnelBackend {
  final sessions = <TunnelSessionRequest>[];
  final _states = StreamController<VpnState>.broadcast();
  VpnState current = VpnState.disconnected;

  @override
  Stream<VpnState> get stateStream => _states.stream;

  @override
  Future<VpnState> getCurrentState() async => current;

  @override
  Future<void> startSession(TunnelSessionRequest request) async {
    sessions.add(request);
    current = const VpnState(status: VpnStatus.connected);
  }

  @override
  Future<void> stopSession() async {
    current = VpnState.disconnected;
    _states.add(VpnState.disconnected);
  }

  @override
  void dispose() {
    unawaited(_states.close());
    super.dispose();
  }
}

String _vless(String host, String name) =>
    'vless://00000000-0000-4000-8000-000000000000@$host:443'
    '?type=tcp&security=none#$name';

Future<(ProviderContainer, _Backend)> _connected({
  required bool auto,
  required List<String> served,
}) async {
  final sub = Subscription(
    id: 'a',
    name: 'a',
    url: 'https://a.example/sub',
    autoSelectVisible: true,
    autoSelect: auto,
  );
  final gone = ServerItem.fromRaw(
    _vless('198.51.100.10', 'Old'),
    subscriptionId: 'a',
  );
  final storage = await buildStorageService();
  await storage.saveSubscriptions([sub]);
  await storage.saveServers([gone]);
  await storage.setActiveServerId(gone.id);

  final backend = _Backend();
  final container = ProviderContainer(
    overrides: [
      storageProvider.overrideWithValue(storage),
      vpnEngineProvider.overrideWithValue(VpnEngine.withBackend(backend)),
      subscriptionServiceProvider.overrideWithValue(
        SubscriptionService(
          storage,
          dio: Dio()..httpClientAdapter = _Body(served.join('\n')),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(subscriptionsProvider.future);
  container.read(serversProvider);
  await container.read(vpnStateProvider.future);
  await container.read(vpnStateProvider.notifier).connect();
  expect(backend.sessions.single.serverName, 'Old');
  return (container, backend);
}

Future<void> _settle(_Backend backend, int sessions) async {
  for (var i = 0; i < 100 && backend.sessions.length < sessions; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('авто: VPN включён, выбранный пропал из подписки, туннель переезжает '
      'на подставленный', () async {
    final (c, backend) = await _connected(
      auto: true,
      served: [_vless('198.51.100.11', 'New')],
    );

    final sub = c.read(subscriptionsProvider).value!.single;
    await c.read(subscriptionsProvider.notifier).refresh(sub);
    await _settle(backend, 2);

    expect(c.read(serversProvider).activeServer?.displayName, 'New');
    expect(backend.sessions.map((s) => s.serverName), ['Old', 'New']);
  });

  test('ручной выбор: выбор пуст, туннель не трогается', () async {
    final (c, backend) = await _connected(
      auto: false,
      served: [_vless('198.51.100.11', 'New')],
    );

    final sub = c.read(subscriptionsProvider).value!.single;
    await c.read(subscriptionsProvider.notifier).refresh(sub);
    await _settle(backend, 2);

    expect(c.read(serversProvider).activeServer, isNull);
    expect(backend.sessions, hasLength(1));
    expect(c.read(vpnStateProvider).value?.status, VpnStatus.connected);
  });

  // на Android подписку обновляет фоновый изолят, пока интерфейса нет, а туннель работает
  group('интерфейс открыли после фонового обновления, VPN включён', () {
    Future<(ProviderContainer, _Backend)> reopen({required bool replaced}) async {
      final picked = ServerItem.fromRaw(
        _vless('198.51.100.11', 'New'),
        subscriptionId: 'a',
      );
      final storage = await buildStorageService();
      await storage.saveSubscriptions([
        const Subscription(
          id: 'a',
          name: 'a',
          url: 'https://a.example/sub',
          autoSelectVisible: true,
          autoSelect: true,
        ),
      ]);
      await storage.saveServers([picked]);
      await storage.setActiveServerId(picked.id);
      if (replaced) await AutoSelectFollowStore.save(picked.id);

      final backend = _Backend()
        ..current = const VpnState(status: VpnStatus.connected);
      final container = ProviderContainer(
        overrides: [
          storageProvider.overrideWithValue(storage),
          vpnEngineProvider.overrideWithValue(VpnEngine.withBackend(backend)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(subscriptionsProvider.future);
      return (container, backend);
    }

    test('сервер подставлен обновлением: туннель переезжает на него', () async {
      final (_, backend) = await reopen(replaced: true);
      await _settle(backend, 1);
      expect(backend.sessions.map((s) => s.serverName), ['New']);
      expect(await AutoSelectFollowStore.take(), isNull);
    });

    test('ничего не подставлялось: туннель не трогается', () async {
      final (c, backend) = await reopen(replaced: false);
      c.read(serversProvider);
      await c.read(vpnStateProvider.future);
      await _settle(backend, 1);
      expect(backend.sessions, isEmpty);
    });
  });

  test('авто: выбранный сервер на месте, туннель не трогается', () async {
    final (c, backend) = await _connected(
      auto: true,
      served: [_vless('198.51.100.10', 'Old'), _vless('198.51.100.11', 'New')],
    );

    final sub = c.read(subscriptionsProvider).value!.single;
    await c.read(subscriptionsProvider.notifier).refresh(sub);
    await _settle(backend, 2);

    expect(c.read(serversProvider).activeServer?.displayName, 'Old');
    expect(backend.sessions, hasLength(1));
  });
}

class _Body implements HttpClientAdapter {
  _Body(this.body);

  final String body;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString(
        body,
        200,
        headers: {
          'content-type': ['text/plain; charset=utf-8'],
        },
      );
}
