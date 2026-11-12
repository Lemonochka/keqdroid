import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:keqdroid/utils/local_vpn_proxy.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

/// Креды локального входа у приложения и у ядра.
///
/// На Pixel 6a 12.11.2026 они разошлись, и всё своё приложение (обновление,
/// подписки) получало 407 от своего же прокси до перезапуска. Теперь
/// приложение берёт креды у работающего ядра каждый раз, как сессия
/// оказывается подключённой.
class _Backend extends FakeTunnelBackend {
  final states = StreamController<VpnState>.broadcast();
  VpnState current = VpnState.disconnected;

  /// Креды, с которыми поднято ядро; null — ядра нет.
  ({String username, String password})? core;

  @override
  Stream<VpnState> get stateStream => states.stream;

  @override
  Future<VpnState> getCurrentState() async => current;

  @override
  Future<({String username, String password})?>
      fetchActiveSocksCredentials() async => core;

  @override
  Future<void> startSession(TunnelSessionRequest request) async {
    current = const VpnState(status: VpnStatus.connected);
  }
}

final _server = ServerItem(
  id: 'srv-1',
  type: ServerItemType.manual,
  config: 'vless://00000000-0000-4000-8000-000000000000@198.51.100.10:443'
      '?type=tcp&security=none#test',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Backend backend;

  Future<ProviderContainer> build() async {
    final storage = await buildStorageService();
    await storage.saveServers([_server]);
    await storage.setActiveServerId(_server.id);
    final container = ProviderContainer(
      overrides: [
        storageProvider.overrideWithValue(storage),
        vpnEngineProvider.overrideWithValue(VpnEngine.withBackend(backend)),
      ],
    );
    addTearDown(container.dispose);
    container.read(serversProvider);
    await container.read(vpnStateProvider.future);
    return container;
  }

  setUp(() {
    backend = _Backend();
    VpnStateNotifier.debugSyncsCredentials = true;
  });

  tearDown(() {
    VpnStateNotifier.debugSyncsCredentials = null;
    localProxyCredentialsSync = null;
    Socks5Credentials().init('', '');
  });

  test('сессия подключена, а пароль приложения другой: берётся пароль ядра',
      () async {
    Socks5Credentials().init('stale', 'stale');
    backend.core = (username: 'core', password: 'core');
    await build();

    backend.states.add(const VpnState(status: VpnStatus.connected));
    await pumpEventQueue();

    expect(Socks5Credentials().username, 'core');
    expect(Socks5Credentials().password, 'core');
  });

  test('свежий изолят без кредов получает их у ядра', () async {
    backend.core = (username: 'core', password: 'core');
    await build();

    backend.states.add(const VpnState(status: VpnStatus.connected));
    await pumpEventQueue();

    expect(Socks5Credentials().username, 'core');
  });

  test('ядра нет: пароль приложения не трогаем', () async {
    Socks5Credentials().init('mine', 'mine');
    backend.core = null;
    await build();

    backend.states.add(const VpnState(status: VpnStatus.connected));
    await pumpEventQueue();

    expect(Socks5Credentials().username, 'mine');
  });

  test('не подключено: сверки нет', () async {
    Socks5Credentials().init('mine', 'mine');
    backend.core = (username: 'core', password: 'core');
    await build();

    backend.states.add(const VpnState(status: VpnStatus.connecting));
    await pumpEventQueue();

    expect(Socks5Credentials().username, 'mine');
  });

  test('повтор после 407 сверяет креды через нотифаер, пока он жив', () async {
    Socks5Credentials().init('stale', 'stale');
    backend.core = (username: 'core', password: 'core');
    final container = await build();

    final sync = localProxyCredentialsSync;
    expect(sync, isNotNull);
    await sync!();
    expect(Socks5Credentials().username, 'core');

    container.dispose();
    expect(localProxyCredentialsSync, isNull);
  });

  test('где сверять не с кем, повтора после 407 нет', () async {
    VpnStateNotifier.debugSyncsCredentials = false;
    await build();
    expect(localProxyCredentialsSync, isNull);
  });

  test(
    'после connect() креды сверяются с поднятым ядром',
    () async {
      // старт поверх живой сессии: ядро осталось с прежними кредами
      backend.core = (username: 'core', password: 'core');
      final container = await build();

      await container.read(vpnStateProvider.notifier).connect();
      await pumpEventQueue();

      expect(container.read(vpnStateProvider).value?.status,
          VpnStatus.connected);
      expect(Socks5Credentials().username, 'core');
    },
    skip: Platform.isWindows ? false : 'connect() идёт веткой этой платформы',
  );
}
