import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/services/linux_background_service.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:keqdroid/services/windows_tray_menu.dart';
import 'package:path/path.dart' as p;

List<int> _icoSizes(ByteData ico) => [
  for (var i = 0; i < ico.getUint16(4, Endian.little); i++)
    switch (ico.getUint8(6 + i * 16)) {
      0 => 256,
      final s => s,
    },
];

class _Vpn extends VpnStateNotifier {
  @override
  Future<VpnState> build() async =>
      const VpnState(status: VpnStatus.disconnected);

  void emit(VpnStatus status) => state = AsyncData(VpnState(status: status));
}

/// Значок в трее: зелёная точка горит, только пока VPN подключён. В ico по
/// кадру на каждый масштаб экрана: из одного кадра 256 Windows ужимала значок
/// до 16 пикселей сама, и он выходил рваным рядом с соседними.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const trayChannel = MethodChannel('tray_manager');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> icons;
  late List<Object?> ids;

  setUp(() {
    icons = [];
    ids = [];
    messenger.setMockMethodCallHandler(trayChannel, (call) async {
      if (call.method == 'setIcon') {
        final args = call.arguments as Map;
        icons.add(p.basename(args['iconPath'] as String));
        ids.add(args['id']);
      }
      return true;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(trayChannel, null));

  test(
    'Windows: точка появляется при подключении и гаснет при любом другом',
    () async {
      final menu = Provider<WindowsTrayMenu>((ref) {
        final menu = WindowsTrayMenu(ref);
        menu.init();
        return menu;
      });
      final container = ProviderContainer(
        overrides: [vpnStateProvider.overrideWith(_Vpn.new)],
      );
      addTearDown(container.dispose);
      container.listen(menu, (_, _) {});
      await pumpEventQueue();
      final vpn = container.read(vpnStateProvider.notifier) as _Vpn;

      for (final status in [
        VpnStatus.connecting,
        VpnStatus.connected,
        VpnStatus.disconnecting,
        VpnStatus.disconnected,
        VpnStatus.connecting,
        VpnStatus.error,
      ]) {
        vpn.emit(status);
        await pumpEventQueue();
      }

      expect(icons, [
        'tray_icon.ico',
        'tray_icon_connected.ico',
        'tray_icon.ico',
      ]);
    },
  );

  test('Linux: тот же значок с точкой, под прежним id', () async {
    final service = LinuxBackgroundService.forTesting();
    await service.showConnected(true);
    await service.showConnected(false);

    expect(icons, ['icon_connected.png', 'icon.png']);
    expect(ids, everyElement('keqdroid'));
  });

  group('значки едут в сборке', () {
    for (final name in ['tray_icon.ico', 'tray_icon_connected.ico']) {
      test('$name: кадр на каждый масштаб экрана', () async {
        final ico = await rootBundle.load('assets/$name');
        expect(_icoSizes(ico), containsAll([16, 20, 24, 28, 32, 40, 48, 256]));
      });
    }

    // панель задач рисует 24 x масштаб, заголовок окна 16 x масштаб
    test('app_icon.ico в exe: кадры под панель задач и заголовок окна', () {
      final ico = File(
        'windows/runner/resources/app_icon.ico',
      ).readAsBytesSync();
      expect(
        _icoSizes(ByteData.sublistView(ico)),
        containsAll([16, 20, 24, 28, 30, 32, 36, 40, 42, 48, 256]),
      );
    });

    for (final name in ['icon.png', 'icon_connected.png']) {
      test('$name: 256 на 256, как ждут ярлык и пакеты Linux', () async {
        final png = await rootBundle.load('assets/$name');
        expect(png.getUint32(16), 256);
        expect(png.getUint32(20), 256);
      });
    }
  });
}
