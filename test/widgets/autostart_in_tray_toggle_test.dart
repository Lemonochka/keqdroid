import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/app/app.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/settings_tab.dart';
import 'package:keqdroid/services/linux_autostart.dart';
import 'package:keqdroid/services/storage_service.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:path/path.dart' as p;

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

/// «Запускать в трее, без окна» на экране Windows и Linux: раннер решает,
/// показывать ли окно, до первого кадра, поэтому флаг обязан доехать до
/// нативной части сразу, а без автозапуска переключать его нечего.
const _channel = MethodChannel('keqdroid_vpn_channel');
const _title = 'Start in the tray, without a window';

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<(StorageService, List<MethodCall>)> _openDesktopSettings(
  WidgetTester tester, {
  required bool autostart,
}) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final calls = <MethodCall>[];
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_channel, (call) async {
    calls.add(call);
    return switch (call.method) {
      'isLaunchAtStartup' => autostart,
      'isLaunchAtStartupElevated' => false,
      'setLaunchAtStartup' => true,
      _ => null,
    };
  });
  addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  final storage = (await tester.runAsync(() => buildStorageService(
        initialValues: {
          'keqdis_settings':
              AppSettings(launchAtStartup: autostart).toJsonString(),
        },
      )))!;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage),
        vpnEngineProvider.overrideWithValue(VpnEngine.withBackend(FakeTunnelBackend())),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        theme: buildAppTheme(buildPresetScheme(themePresetFor(const AppSettings()), Brightness.light)),
        home: const SettingsTab(),
      ),
    ),
  );
  await _frames(tester);
  await tester.tap(find.text(Platform.isLinux ? 'Linux' : 'Windows'));
  await _frames(tester);
  return (storage, calls);
}

void main() {
  // раздел «Windows» в настройках строится по настоящей ОС, на раннере CI с Linux его нет
  final skip = !Platform.isWindows;

  testWidgets('стоит между запуском с Windows и подключением', (tester) async {
    await _openDesktopSettings(tester, autostart: true);

    final launch = tester.getRect(find.text('Start with Windows'));
    final tray = tester.getRect(find.text(_title));
    final connect = tester.getRect(find.text('Connect on autostart'));
    expect(tray.top, greaterThan(launch.top));
    expect(tray.top, lessThan(connect.top));
  }, skip: skip);

  // TUN без прав поднимает служба, задача планировщика с правами больше не заводится
  testWidgets('переключателя прав нет, автозапуск включается обычный', (tester) async {
    final (storage, calls) = await _openDesktopSettings(tester, autostart: false);
    expect(find.text('Start with admin rights'), findsNothing);
    expect(find.byIcon(Icons.admin_panel_settings_rounded), findsNothing);

    await tester.tap(find.text('Start with Windows'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await _frames(tester);

    expect(
      calls.where((c) => c.method == 'setLaunchAtStartup').last.arguments,
      {'enabled': true, 'elevated': false, 'allowElevation': true},
    );
    final saved = (await tester.runAsync(storage.getSettings))!;
    expect(saved.launchAtStartupElevated, isFalse);
  }, skip: skip);

  testWidgets('без автозапуска нажатие ничего не меняет', (tester) async {
    final (storage, calls) = await _openDesktopSettings(tester, autostart: false);

    await tester.tap(find.text(_title));
    // хранилище собрано в runAsync, и его запись дожидается настоящего времени
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await _frames(tester);

    final saved = (await tester.runAsync(storage.getSettings))!;
    expect(saved.autostartInTray, isFalse);
    expect(
      calls.where((c) => c.method == 'setAutostartInTray' && c.arguments['enabled'] == true),
      isEmpty,
    );
  }, skip: skip);

  testWidgets('с автозапуском включается и сразу уходит в раннер', (tester) async {
    final (storage, calls) = await _openDesktopSettings(tester, autostart: true);

    await tester.tap(find.text(_title));
    // хранилище собрано в runAsync, и его запись дожидается настоящего времени
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await _frames(tester);

    final saved = (await tester.runAsync(storage.getSettings))!;
    expect(saved.autostartInTray, isTrue);
    expect(
      calls.where((c) => c.method == 'setAutostartInTray').last.arguments,
      {'enabled': true},
    );
  }, skip: skip);

  group('Linux', () {
    // раздел «Linux» есть только на настоящем Linux
    final skip = !Platform.isLinux;
    late Directory dir;

    File inTray() =>
        File(p.join(dir.path, 'data', 'com.keqdroid.keqdroid', 'autostart-in-tray'));

    // экран сверяет переключатель автозапуска с ярлыком на диске
    void loginEntry() => File(p.join(dir.path, 'config', 'autostart', 'keqdroid.desktop'))
      ..createSync(recursive: true)
      ..writeAsStringSync(LinuxAutostart.contentFor('/opt/keqdroid/keqdroid'));

    // каждый шаг записи ждёт настоящего ввода-вывода, а продолжение после него идёт только на кадре
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
      }
      await _frames(tester);
    }

    setUp(() {
      dir = Directory.systemTemp.createTempSync('kq_in_tray_');
      LinuxAutostart.configHomeOverride = p.join(dir.path, 'config');
      LinuxAutostart.dataHomeOverride = p.join(dir.path, 'data');
    });

    tearDown(() {
      LinuxAutostart.configHomeOverride = null;
      LinuxAutostart.dataHomeOverride = null;
      dir.deleteSync(recursive: true);
    });

    testWidgets('стоит между запуском при входе и подключением', (tester) async {
      loginEntry();
      await _openDesktopSettings(tester, autostart: true);

      final login = tester.getRect(find.text('Start at login'));
      final tray = tester.getRect(find.text(_title));
      final connect = tester.getRect(find.text('Connect on autostart'));
      expect(tray.top, greaterThan(login.top));
      expect(tray.top, lessThan(connect.top));
    }, skip: skip);

    testWidgets('без автозапуска нажатие ничего не меняет', (tester) async {
      final (storage, _) = await _openDesktopSettings(tester, autostart: false);

      await tester.tap(find.text(_title));
      await settle(tester);

      final saved = (await tester.runAsync(storage.getSettings))!;
      expect(saved.autostartInTray, isFalse);
      expect(inTray().existsSync(), isFalse);
    }, skip: skip);

    testWidgets('включение кладёт файл для раннера, выключение убирает', (tester) async {
      loginEntry();
      final (storage, _) = await _openDesktopSettings(tester, autostart: true);

      await tester.tap(find.text(_title));
      await settle(tester);
      expect((await tester.runAsync(storage.getSettings))!.autostartInTray, isTrue);
      expect(inTray().existsSync(), isTrue);

      await tester.tap(find.text(_title));
      await settle(tester);
      expect((await tester.runAsync(storage.getSettings))!.autostartInTray, isFalse);
      expect(inTray().existsSync(), isFalse);
    }, skip: skip);
  });
}
