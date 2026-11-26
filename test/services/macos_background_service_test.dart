import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/platform/vpn_native_bridge.dart';
import 'package:keqdroid/services/macos_autostart.dart';
import 'package:keqdroid/services/macos_background_service.dart';
import 'package:keqdroid/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const windowChannel = MethodChannel('window_manager');
  const trayChannel = MethodChannel('tray_manager');

  late Directory tmp;
  late List<String> windowCalls;
  late List<String> vpnCalls;
  late List<int> exitCodes;
  final origExit = MacosBackgroundService.exitProcess;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('keq_macos_bg_');
    windowCalls = [];
    vpnCalls = [];
    exitCodes = [];

    SharedPreferences.setMockInitialValues({
      'keqdis_window_bounds': jsonEncode({
        'x': 120.0,
        'y': 80.0,
        'w': 1040.0,
        'h': 700.0,
        'maximized': true,
      }),
    });
    await StorageService.init();

    MacosAutostart.homeOverride = tmp.path;
    MacosAutostart.captureLaunchArgs(const []);
    MacosBackgroundService.exitProcess = exitCodes.add;

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(windowChannel, (call) async {
      windowCalls.add(call.method);
      switch (call.method) {
        case 'isMaximized':
          return false;
        case 'getBounds':
          return {'x': 120.0, 'y': 80.0, 'width': 1040.0, 'height': 700.0};
        case 'isVisible':
          return true;
        case 'isMinimized':
          return false;
        default:
          return true;
      }
    });
    messenger.setMockMethodCallHandler(trayChannel, (call) async => true);
    messenger.setMockMethodCallHandler(VpnNativeBridge.channel, (call) async {
      vpnCalls.add(call.method);
      return null;
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(windowChannel, null);
    messenger.setMockMethodCallHandler(trayChannel, null);
    messenger.setMockMethodCallHandler(VpnNativeBridge.channel, null);
    MacosAutostart.homeOverride = null;
    MacosAutostart.captureLaunchArgs(const []);
    MacosBackgroundService.exitProcess = origExit;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('tracks minimize and restore in uiVisible', () {
    final svc = MacosBackgroundService.forTesting();
    expect(svc.uiVisible.value, isTrue);

    svc.onWindowMinimize();
    expect(svc.uiVisible.value, isFalse);

    svc.onWindowRestore();
    expect(svc.uiVisible.value, isTrue);
  });

  test(
    'defers window bounds and maximize restore when autostarted in tray',
    () async {
      MacosAutostart.captureLaunchArgs([MacosAutostart.flag]);
      await MacosAutostart.setStartInTray(true);

      final svc = MacosBackgroundService.forTesting();
      await svc.initWindowAndTray();

      expect(svc.uiVisible.value, isFalse);
      expect(windowCalls, isNot(contains('setBounds')));
      expect(windowCalls, isNot(contains('maximize')));

      await svc.restoreMainWindow();

      expect(svc.uiVisible.value, isTrue);
      expect(windowCalls, contains('setBounds'));
      expect(windowCalls, contains('maximize'));
      expect(windowCalls, contains('show'));
    },
  );

  test(
    'restores deferred window bounds when focused from Dock after tray autostart',
    () async {
      MacosAutostart.captureLaunchArgs([MacosAutostart.flag]);
      await MacosAutostart.setStartInTray(true);

      final svc = MacosBackgroundService.forTesting();
      await svc.initWindowAndTray();

      expect(windowCalls, isNot(contains('setBounds')));

      svc.onWindowFocus();
      await Future<void>.delayed(Duration.zero);

      expect(svc.uiVisible.value, isTrue);
      expect(windowCalls, contains('setBounds'));
      expect(windowCalls, contains('maximize'));
    },
  );

  test('repeated app terminate waits for in-flight tray quit', () async {
    final svc = MacosBackgroundService.forTesting();
    final cleanupGate = Completer<void>();
    svc.onQuit = () => cleanupGate.future;

    final firstQuit = svc.quit();
    await svc.quit(fromAppTerminate: true);
    await svc.quit(fromAppTerminate: true);
    expect(vpnCalls, isNot(contains('confirmAppTerminate')));

    cleanupGate.complete();
    await firstQuit;

    expect(
      vpnCalls.where((call) => call == 'confirmAppTerminate'),
      hasLength(1),
    );
    expect(exitCodes, isEmpty);
  });

  test(
    'onOpenSettings native callback invokes registered handler on macOS',
    () async {
      var opened = 0;
      VpnNativeBridge.registerOpenSettingsHandler(() => opened++);
      addTearDown(() => VpnNativeBridge.registerOpenSettingsHandler(null));

      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      await messenger.handlePlatformMessage(
        VpnNativeBridge.channel.name,
        VpnNativeBridge.channel.codec.encodeMethodCall(
          const MethodCall('onOpenSettings'),
        ),
        (_) {},
      );

      expect(opened, Platform.isMacOS ? 1 : 0);
    },
  );
}
