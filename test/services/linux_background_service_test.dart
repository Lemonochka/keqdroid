import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/linux_background_service.dart';
import 'package:keqdroid/tunnel/tunnel_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const windowChannel = MethodChannel('window_manager');
  const trayChannel = MethodChannel('tray_manager');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<String> calls;
  late List<List<Map<Object?, Object?>>> menus;
  late Object? trayAvailable;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LinuxBackgroundService.quitSettleDelay = Duration.zero;
    LinuxBackgroundService.closeToBackground = () async => true;
    calls = [];
    menus = [];
    trayAvailable = true;
    messenger.setMockMethodCallHandler(windowChannel, (call) async {
      calls.add('window.${call.method}');
      return switch (call.method) {
        'isMaximized' || 'isMinimized' => false,
        'isVisible' => true,
        'getBounds' => {'x': 10.0, 'y': 20.0, 'width': 920.0, 'height': 720.0},
        _ => true,
      };
    });
    messenger.setMockMethodCallHandler(trayChannel, (call) async {
      calls.add('tray.${call.method}');
      if (call.method == 'setContextMenu') {
        final menu = (call.arguments as Map)['menu'] as Map;
        menus.add([
          for (final item in menu['items'] as List)
            item as Map<Object?, Object?>,
        ]);
      }
      if (call.method == 'isAvailable') {
        final answer = trayAvailable;
        if (answer is Exception) throw answer;
        return answer;
      }
      return true;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(windowChannel, null);
    messenger.setMockMethodCallHandler(trayChannel, null);
  });

  group('close button', () {
    test('hides the window when a tray is there to bring it back', () async {
      LinuxBackgroundService.forTesting().onWindowClose();
      await pumpEventQueue();

      expect(calls, contains('window.hide'));
      expect(calls, isNot(contains('window.minimize')));
    });

    test('minimizes the window when there is no tray', () async {
      trayAvailable = false;
      LinuxBackgroundService.forTesting().onWindowClose();
      await pumpEventQueue();

      expect(calls, contains('window.minimize'));
      expect(calls, isNot(contains('window.hide')));
    });

    test('hides on a tiling compositor, which never minimizes', () async {
      trayAvailable = false;
      LinuxBackgroundService.desktopOverride = 'Hyprland';
      addTearDown(() => LinuxBackgroundService.desktopOverride = null);
      LinuxBackgroundService.forTesting().onWindowClose();
      await pumpEventQueue();

      expect(calls, contains('window.hide'));
      expect(calls, isNot(contains('window.minimize')));
    });

    test('tells the screen the window is gone, and back on focus', () async {
      trayAvailable = false;
      final service = LinuxBackgroundService.forTesting();
      service.onWindowClose();
      await pumpEventQueue();
      expect(service.uiVisible.value, isFalse);

      service.onWindowFocus();
      expect(service.uiVisible.value, isTrue);
    });

    test('quits when "minimize to tray on close" is off', () async {
      LinuxBackgroundService.closeToBackground = () async => false;
      LinuxBackgroundService.forTesting().onWindowClose();
      await pumpEventQueue();

      expect(calls, contains('window.destroy'));
      expect(calls, isNot(contains('window.minimize')));
    });

    test('keeps hiding when the tray check itself fails', () async {
      trayAvailable = PlatformException(code: 'boom');
      LinuxBackgroundService.forTesting().onWindowClose();
      await pumpEventQueue();

      expect(calls, contains('window.hide'));
    });
  });

  // Меню трея на Linux: пункт подключения сверху, как на Windows. Меню
  // AppIndicator не пересобирается по клику, поэтому идёт за состоянием VPN.
  group('tray connect item', () {
    String describe(Map<Object?, Object?> item) => item['type'] == 'separator'
        ? '---'
        : '${item['label']}${item['disabled'] == true ? ' (off)' : ''}';

    Future<List<String>> menuFor(VpnStatus status, {bool server = true}) async {
      final service = LinuxBackgroundService.forTesting();
      await service.setTrayLabels(
        show: 'Open',
        quit: 'Exit',
        connect: 'Connect',
        disconnect: 'Disconnect',
      );
      await service.setTrayVpn(status: status, hasServer: server);
      return [for (final item in menus.last) describe(item)];
    }

    test('no item until the screen reports the VPN state', () async {
      final service = LinuxBackgroundService.forTesting();
      await service.setTrayLabels(
        show: 'Open',
        quit: 'Exit',
        connect: 'Connect',
        disconnect: 'Disconnect',
      );

      expect(
        [for (final item in menus.last) describe(item)],
        ['Open', '---', 'Exit'],
      );
    });

    test('label and availability follow the VPN state', () async {
      expect(await menuFor(VpnStatus.disconnected), [
        'Connect',
        '---',
        'Open',
        '---',
        'Exit',
      ]);
      expect(
        (await menuFor(VpnStatus.disconnected, server: false)).first,
        'Connect (off)',
      );
      expect((await menuFor(VpnStatus.connecting)).first, 'Disconnect');
      expect((await menuFor(VpnStatus.connected)).first, 'Disconnect');
      expect((await menuFor(VpnStatus.disconnecting)).first, 'Connect (off)');
      expect((await menuFor(VpnStatus.error)).first, 'Connect');
      expect(
        (await menuFor(VpnStatus.error, server: false)).first,
        'Connect (off)',
      );
    });

    test('the menu is not resent when the item stays the same', () async {
      final service = LinuxBackgroundService.forTesting();
      await service.setTrayVpn(status: VpnStatus.disconnected, hasServer: true);
      await service.setTrayVpn(status: VpnStatus.error, hasServer: true);
      expect(menus, hasLength(1));

      await service.setTrayVpn(status: VpnStatus.connecting, hasServer: true);
      await service.setTrayVpn(status: VpnStatus.connected, hasServer: true);
      expect(menus, hasLength(2));
    });

    test(
      'a click runs the toggle once, even when clicked again meanwhile',
      () async {
        final service = LinuxBackgroundService.forTesting();
        final release = Completer<void>();
        var toggles = 0;
        service.onToggleVpn = () async {
          toggles++;
          await release.future;
        };

        service.onTrayMenuItemClick(MenuItem(key: 'vpn'));
        service.onTrayMenuItemClick(MenuItem(key: 'vpn'));
        await pumpEventQueue();
        expect(toggles, 1);

        release.complete();
        await pumpEventQueue();
        service.onTrayMenuItemClick(MenuItem(key: 'vpn'));
        await pumpEventQueue();
        expect(toggles, 2);
      },
    );

    test('a failed toggle does not lock the item', () async {
      final service = LinuxBackgroundService.forTesting();
      var toggles = 0;
      service.onToggleVpn = () async {
        toggles++;
        throw StateError('core died');
      };

      service.onTrayMenuItemClick(MenuItem(key: 'vpn'));
      await pumpEventQueue();
      service.onTrayMenuItemClick(MenuItem(key: 'vpn'));
      await pumpEventQueue();

      expect(toggles, 2);
    });
  });

  test('isTilingDesktop reads every entry of XDG_CURRENT_DESKTOP', () {
    expect(LinuxBackgroundService.isTilingDesktop('Hyprland'), isTrue);
    expect(LinuxBackgroundService.isTilingDesktop('sway'), isTrue);
    expect(LinuxBackgroundService.isTilingDesktop('niri:GNOME'), isTrue);
    expect(LinuxBackgroundService.isTilingDesktop('ubuntu:GNOME'), isFalse);
    expect(LinuxBackgroundService.isTilingDesktop('KDE'), isFalse);
  });

  group('quit', () {
    test('disconnects, hides the window, then destroys it', () async {
      final service = LinuxBackgroundService.forTesting();
      var disconnected = false;
      service.onQuit = () async {
        disconnected = true;
        expect(calls, isNot(contains('window.destroy')));
      };

      await service.quit();

      expect(disconnected, isTrue);
      final hide = calls.indexOf('window.hide');
      final destroy = calls.indexOf('window.destroy');
      expect(hide, isNonNegative);
      expect(destroy, greaterThan(hide));
      expect(calls, contains('tray.destroy'));
    });

    test('ignores the close event the destroyed window sends back', () async {
      final service = LinuxBackgroundService.forTesting();
      await service.quit();
      calls.clear();

      service.onWindowClose();
      await pumpEventQueue();

      expect(calls, isEmpty);
    });

    test('runs only once when asked twice', () async {
      final service = LinuxBackgroundService.forTesting();
      var quits = 0;
      service.onQuit = () async => quits++;

      await Future.wait([service.quit(), service.quit()]);

      expect(quits, 1);
      expect(calls.where((c) => c == 'window.destroy'), hasLength(1));
    });
  });
}
