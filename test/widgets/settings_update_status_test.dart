import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/app/app.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/settings_tab.dart';
import 'package:keqdroid/services/update_service.dart';
import 'package:keqdroid/services/vpn_engine.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

/// Карточка версии в настройках по итогу фоновой проверки, без подмены провайдера.

final _en = lookupAppLocalizations(const Locale('en'));

Future<void> _pumpSettings(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
}) async {
  tester.view.physicalSize = const Size(700, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final storage =
      (await tester.runAsync(() => buildStorageService(initialValues: prefs)))!;
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
        theme: buildAppTheme(
          buildPresetScheme(themePresetFor(const AppSettings()), Brightness.light),
        ),
        home: const SettingsTab(),
      ),
    ),
  );
  // riverpod повторил бы упавшую проверку через 0,2 с, потом 0,4 и дальше
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  final realFetch = UpdateService.fetchUpdate;
  late int calls;

  setUp(() {
    calls = 0;
    UpdateService.resetAutoCheck();
  });
  tearDown(() {
    UpdateService.fetchUpdate = realFetch;
    UpdateService.resetAutoCheck();
  });

  testWidgets('GitHub не ответил на первой проверке: ошибка проверки, а не актуальная версия',
      (tester) async {
    UpdateService.fetchUpdate = ({
      required bool viaLocalProxy,
      required int httpPort,
    }) async {
      calls++;
      throw DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.connectionError,
      );
    };

    await _pumpSettings(tester);

    expect(find.text(_en.settingsCheckFailed, skipOffstage: false), findsOneWidget);
    expect(find.text(_en.settingsUpToDate, skipOffstage: false), findsNothing);
    expect(find.text(_en.settingsChecking, skipOffstage: false), findsNothing);
    expect(calls, 1);
  });

  testWidgets('пропущенная версия видна в карточке как обновление', (tester) async {
    UpdateService.fetchUpdate = ({
      required bool viaLocalProxy,
      required int httpPort,
    }) async {
      calls++;
      return UpdateInfo(
        currentVersion: '0.26.0',
        latestVersion: '0.27.0',
        downloadUrl: 'https://example.invalid/keqdroid.apk',
        apkSize: 40 * 1024 * 1024,
      );
    };

    await _pumpSettings(tester, prefs: {'skip_update_version': '0.27.0'});

    expect(find.text(_en.settingsUpdateAvailable, skipOffstage: false), findsOneWidget);
    expect(find.text(_en.settingsNewVersionAvailable, skipOffstage: false), findsOneWidget);
    expect(find.textContaining('v0.27.0', skipOffstage: false), findsOneWidget);
    expect(find.text(_en.settingsUpToDate, skipOffstage: false), findsNothing);
  });
}
