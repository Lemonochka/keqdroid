import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/services/linux_background_service.dart';
import 'package:keqdroid/services/linux_tray_vpn.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:tray_manager/tray_manager.dart';

class _Servers extends ServersNotifier {
  static final _server = ServerItem(
    id: 'pl',
    config:
        'vless://00000000-0000-0000-0000-000000000000@pl.example.com:443'
        '#Poland',
    type: ServerItemType.manual,
  );

  @override
  ServersState build() =>
      ServersState(servers: [_server], activeServerId: 'pl');

  void choose(String? id) =>
      state = ServersState(servers: [_server], activeServerId: id);
}

class _Vpn extends VpnStateNotifier {
  final calls = <String>[];

  @override
  Future<VpnState> build() async =>
      const VpnState(status: VpnStatus.disconnected);

  void emit(VpnStatus status) => state = AsyncData(VpnState(status: status));

  @override
  Future<void> connect({bool autostartTunFallback = false}) async =>
      calls.add('connect');

  @override
  Future<void> disconnect() async => calls.add('disconnect');

  @override
  Future<void> cancelConnect() async => calls.add('cancel');
}

// Пункт подключения в трее Linux: экран спрятан в трей, а меню всё равно
// должно знать, подключён ли VPN, и включать его тем же путём, что Windows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const trayChannel = MethodChannel('tray_manager');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> items;

  setUp(() {
    items = [];
    messenger.setMockMethodCallHandler(trayChannel, (call) async {
      if (call.method == 'setContextMenu') {
        final first = ((call.arguments as Map)['menu'] as Map)['items'] as List;
        final item = first.first as Map;
        items.add(
          '${item['label']}${item['disabled'] == true ? ' (off)' : ''}',
        );
      }
      return true;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(trayChannel, null));

  Future<(ProviderContainer, LinuxBackgroundService, ProviderSubscription)>
  start() async {
    final tray = LinuxBackgroundService.forTesting();
    await tray.setTrayLabels(
      show: 'Open',
      quit: 'Exit',
      connect: 'Connect',
      disconnect: 'Disconnect',
    );
    items.clear();
    final provider = Provider<LinuxTrayVpn>((ref) {
      final vpn = LinuxTrayVpn(ref, tray);
      ref.onDispose(vpn.dispose);
      vpn.init();
      return vpn;
    });
    final container = ProviderContainer(
      overrides: [
        vpnStateProvider.overrideWith(_Vpn.new),
        serversProvider.overrideWith(_Servers.new),
      ],
    );
    addTearDown(container.dispose);
    // VPN к открытию экрана уже прочитан: меню не дождётся смены статуса, состояние нужно сразу
    await container.read(vpnStateProvider.future);
    final sub = container.listen(provider, (_, _) {});
    await pumpEventQueue();
    return (container, tray, sub);
  }

  test('the item is there from the start', () async {
    await start();

    expect(items, ['Connect']);
  });

  test('follows the VPN while the window sits in the tray', () async {
    final (container, _, screen) = await start();
    final vpn = container.read(vpnStateProvider.notifier) as _Vpn;
    // окно в трее: корневой TickerMode(false) ставит на паузу подписку экрана
    screen.pause();

    for (final status in [
      VpnStatus.connecting,
      VpnStatus.connected,
      VpnStatus.disconnecting,
      VpnStatus.disconnected,
    ]) {
      vpn.emit(status);
      await pumpEventQueue();
    }

    expect(items, ['Connect', 'Disconnect', 'Connect (off)', 'Connect']);
  });

  test('greys out with no server to connect to', () async {
    final (container, _, _) = await start();

    (container.read(serversProvider.notifier) as _Servers).choose(null);
    await pumpEventQueue();

    expect(items.last, 'Connect (off)');
  });

  group('a click', () {
    Future<List<String>> clickAt(VpnStatus status, {bool server = true}) async {
      final (container, tray, _) = await start();
      final vpn = container.read(vpnStateProvider.notifier) as _Vpn;
      if (!server) {
        (container.read(serversProvider.notifier) as _Servers).choose(null);
      }
      vpn.emit(status);
      await pumpEventQueue();
      tray.onTrayMenuItemClick(MenuItem(key: 'vpn'));
      await pumpEventQueue();
      return vpn.calls;
    }

    test('connects when off', () async {
      expect(await clickAt(VpnStatus.disconnected), ['connect']);
      expect(await clickAt(VpnStatus.error), ['connect']);
    });

    test('disconnects when on', () async {
      expect(await clickAt(VpnStatus.connected), ['disconnect']);
    });

    test('cancels a connect in progress', () async {
      expect(await clickAt(VpnStatus.connecting), ['cancel']);
    });

    test('does nothing while disconnecting or with no server', () async {
      expect(await clickAt(VpnStatus.disconnecting), isEmpty);
      expect(await clickAt(VpnStatus.disconnected, server: false), isEmpty);
    });
  });

  test('a disposed screen leaves the item inert', () async {
    final (container, tray, _) = await start();
    final vpn = container.read(vpnStateProvider.notifier) as _Vpn;

    container.dispose();
    tray.onTrayMenuItemClick(MenuItem(key: 'vpn'));
    await pumpEventQueue();

    expect(vpn.calls, isEmpty);
  });
}
