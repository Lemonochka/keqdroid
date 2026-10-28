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
import 'package:keqdroid/services/storage_service.dart';
import 'package:keqdroid/services/vpn_engine.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

/// «Запускать в трее, без окна» на экране Windows: раннер решает, показывать
/// ли окно, до первого кадра, поэтому флаг обязан доехать до нативной части
/// сразу, а без автозапуска переключать его нечего.
const _channel = MethodChannel('keqdis_vpn_channel');
const _title = 'Start in the tray, without a window';

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<(StorageService, List<MethodCall>)> _openWindowsSettings(
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
  await tester.tap(find.text('Windows'));
  await _frames(tester);
  return (storage, calls);
}

void main() {
  // раздел «Windows» в настройках строится по настоящей ОС, на раннере CI с Linux его нет
  final skip = !Platform.isWindows;

  testWidgets('стоит между правами администратора и подключением', (tester) async {
    await _openWindowsSettings(tester, autostart: true);

    final admin = tester.getRect(find.text('Start with admin rights'));
    final tray = tester.getRect(find.text(_title));
    final connect = tester.getRect(find.text('Connect on autostart'));
    expect(tray.top, greaterThan(admin.top));
    expect(tray.top, lessThan(connect.top));
  }, skip: skip);

  testWidgets('без автозапуска нажатие ничего не меняет', (tester) async {
    final (storage, calls) = await _openWindowsSettings(tester, autostart: false);

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
    final (storage, calls) = await _openWindowsSettings(tester, autostart: true);

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
}
