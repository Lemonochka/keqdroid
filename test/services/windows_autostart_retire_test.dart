import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/windows_desktop_service.dart';

// настройки запуска с правами больше нет: её задачу снимает приложение, запущенное этой задачей,
// и только когда TUN после следующего входа поднимет служба
const _vpn = MethodChannel('keqdroid_vpn_channel');
const _tun = MethodChannel('keqdroid/tun_service');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<String> calls;
  late Map<String, Object?> setLaunch;
  late bool admin;
  late bool task;
  late bool serviceInstalled;
  late bool installOk;

  setUp(() {
    calls = [];
    setLaunch = {};
    admin = true;
    task = true;
    serviceInstalled = false;
    installOk = true;
    messenger.setMockMethodCallHandler(_vpn, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'requestTunnelPermission':
          return admin;
        case 'isLaunchAtStartupElevated':
          return task;
        case 'setLaunchAtStartup':
          setLaunch = Map<String, Object?>.from(call.arguments as Map);
          return true;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(_tun, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'status':
          return {'installed': serviceInstalled, 'trusted': serviceInstalled};
        case 'install':
          serviceInstalled = installOk;
          return {'ok': installOk, 'cancelled': false, 'code': installOk ? 0 : 5};
      }
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(_vpn, null);
    messenger.setMockMethodCallHandler(_tun, null);
  });

  group('старая задача автозапуска с правами', () {
    test('без прав у процесса не трогается: снять её можно только через UAC', () async {
      admin = false;
      expect(
        await WindowsDesktopService.retireElevatedAutostart(tun: true),
        isFalse,
      );
      expect(calls, isNot(contains('setLaunchAtStartup')));
      expect(calls, isNot(contains('install')));
    });

    test('без задачи ничего не делает', () async {
      task = false;
      expect(
        await WindowsDesktopService.retireElevatedAutostart(tun: true),
        isFalse,
      );
      expect(calls, isNot(contains('setLaunchAtStartup')));
      expect(calls, isNot(contains('install')));
    });

    test('в Proxy служба не нужна, задача сменяется обычным автозапуском', () async {
      expect(
        await WindowsDesktopService.retireElevatedAutostart(tun: false),
        isTrue,
      );
      expect(calls, isNot(contains('install')));
      expect(setLaunch, {
        'enabled': true,
        'elevated': false,
        'allowElevation': true,
      });
    });

    test('в TUN сперва ставится служба, потом снимается задача', () async {
      expect(
        await WindowsDesktopService.retireElevatedAutostart(tun: true),
        isTrue,
      );
      expect(
        calls.indexOf('install'),
        lessThan(calls.indexOf('setLaunchAtStartup')),
      );
      expect(setLaunch['elevated'], isFalse);
    });

    test('в TUN со службой задача снимается без переустановки', () async {
      serviceInstalled = true;
      expect(
        await WindowsDesktopService.retireElevatedAutostart(tun: true),
        isTrue,
      );
      expect(calls, isNot(contains('install')));
      expect(calls, contains('setLaunchAtStartup'));
    });

    test('служба не встала: задача остаётся, иначе TUN после входа не поднимется', () async {
      installOk = false;
      expect(
        await WindowsDesktopService.retireElevatedAutostart(tun: true),
        isFalse,
      );
      expect(calls, contains('install'));
      expect(calls, isNot(contains('setLaunchAtStartup')));
    });
  }, skip: !Platform.isWindows);
}
