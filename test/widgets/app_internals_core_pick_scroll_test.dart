import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/app/app.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_internals.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/tun_settings.dart';
import 'package:keqdroid/models/xray_core_settings.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/settings_tab.dart';
import 'package:keqdroid/services/storage_service.dart';
import 'package:keqdroid/services/vpn_engine.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

// Выбор ядра меняет настройки, и сведения экрана собираются заново. Пока они
// собираются, страница остаётся на месте: раньше её подменяла крутилка,
// прокрутка обнулялась, экран прыгал наверх.
const _mihomoSubtitle =
    'Clash-compatible core. Ready-made xray configs stay on Xray.';

final _internals = AppInternals(
  cores: [
    for (final name in ['xray.exe', 'mihomo.exe'])
      CoreInfo(
        name: name,
        role: CoreRole.core,
        version: 'v1.0.0',
        sizeBytes: 30 << 20,
        modified: DateTime(2026, 11),
      ),
  ],
  geoBases: const [
    GeoBaseInfo(name: 'geoip.dat', codeCount: 250),
    GeoBaseInfo(name: 'geosite.dat', codeCount: 1400),
  ],
  session: const SessionInfo(
    status: VpnStatus.disconnected,
    engine: 'mihomo',
    socksPort: 10808,
    httpPort: 10809,
  ),
  build: const BuildInfo(
    appVersion: '0.36.1',
    buildNumber: '361',
    packageName: 'art.kequinq.keqdroid',
    operatingSystem: 'windows',
    osVersion: 'Windows 11',
    abi: 'windows_x64',
    dartVersion: '3.11.3',
    releaseMode: false,
  ),
);

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

ScrollPosition _page(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

void main() {
  testWidgets('прокрутка остаётся на месте, пока сведения собираются заново', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final StorageService storage = (await tester.runAsync(
      () => buildStorageService(
        initialValues: {
          'keqdis_settings': const AppSettings(
            vpnCore: AppSettings.vpnCoreXray,
          ).toJsonString(),
        },
      ),
    ))!;

    // каждое собирание ждёт, пока тест его отпустит
    final pending = <Completer<AppInternals>>[];
    var builds = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageProvider.overrideWithValue(storage),
          vpnEngineProvider.overrideWithValue(
            VpnEngine.withBackend(FakeTunnelBackend()),
          ),
          appInternalsProviderForTest.overrideWith((ref) async {
            await ref.watch(settingsNotifierProvider.future);
            builds++;
            final gate = Completer<AppInternals>();
            pending.add(gate);
            return gate.future;
          }),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          theme: buildAppTheme(
            buildPresetScheme(
              themePresetFor(const AppSettings()),
              Brightness.light,
            ),
          ),
          home: xrayCoreSettingsScreenForTest(),
        ),
      ),
    );
    await _frames(tester);
    expect(pending, hasLength(1));
    pending.last.complete(_internals);
    await _frames(tester);

    final mihomo = find.text(_mihomoSubtitle);
    await tester.scrollUntilVisible(
      mihomo,
      120,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await _frames(tester);
    final before = _page(tester).pixels;
    expect(before, greaterThan(0));

    await tester.tap(mihomo);
    await _frames(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    expect(
      container.read(settingsNotifierProvider).value?.vpnCore,
      AppSettings.vpnCoreMihomo,
      reason: 'нажатие выбирает mihomo',
    );
    expect(builds, 2, reason: 'новые настройки собирают сведения заново');
    expect(find.text(_mihomoSubtitle), findsOneWidget);
    expect(_page(tester).pixels, before);

    pending.last.complete(_internals);
    await _frames(tester);
    expect(_page(tester).pixels, before);
  });

  testWidgets('сброс параметров ядра сохраняет выбранные режим и ядро', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const initial = AppSettings(
      connectionMode: 'tun',
      connectionModeChosen: true,
      vpnCore: AppSettings.vpnCoreMihomo,
      localPort: 3080,
      httpPort: 3081,
      fakeIp: true,
      xrayCore: XrayCoreSettings(logLevel: 'debug'),
      tun: TunSettings(mtu: 1400),
    );
    final StorageService storage = (await tester.runAsync(
      () => buildStorageService(
        initialValues: {'keqdis_settings': initial.toJsonString()},
      ),
    ))!;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageProvider.overrideWithValue(storage),
          vpnEngineProvider.overrideWithValue(
            VpnEngine.withBackend(FakeTunnelBackend()),
          ),
          appInternalsProviderForTest.overrideWith((ref) async => _internals),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          theme: buildAppTheme(
            buildPresetScheme(
              themePresetFor(const AppSettings()),
              Brightness.light,
            ),
          ),
          home: xrayCoreSettingsScreenForTest(),
        ),
      ),
    );
    await _frames(tester);

    await tester.tap(find.text('Reset to defaults').first);
    await _frames(tester);
    await tester.tap(find.text('Reset'));
    await _frames(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    final saved = container.read(settingsNotifierProvider).value!;
    const defaults = AppSettings();
    expect(saved.connectionMode, initial.connectionMode);
    expect(saved.connectionModeChosen, isTrue);
    expect(saved.vpnCore, initial.vpnCore);
    expect(saved.localPort, defaults.localPort);
    expect(saved.httpPort, defaults.httpPort);
    expect(saved.fakeIp, defaults.fakeIp);
    expect(saved.xrayCore, const XrayCoreSettings());
    expect(saved.tun, const TunSettings());
  });

  testWidgets('повторный вход не собирает сведения о ядрах заново', (
    tester,
  ) async {
    final StorageService storage = (await tester.runAsync(
      () => buildStorageService(
        initialValues: {'keqdis_settings': const AppSettings().toJsonString()},
      ),
    ))!;
    var builds = 0;
    final container = ProviderContainer(
      overrides: [
        storageProvider.overrideWithValue(storage),
        vpnEngineProvider.overrideWithValue(
          VpnEngine.withBackend(FakeTunnelBackend()),
        ),
        appInternalsProviderForTest.overrideWith((ref) async {
          builds++;
          await ref.watch(settingsNotifierProvider.future);
          return _internals;
        }),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(appInternalsProviderForTest, (_, _) {});
    final initial = await tester.runAsync(
      () => container.read(appInternalsProviderForTest.future),
    );

    sub.close();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));

    expect(container.read(appInternalsProviderForTest).value, same(initial));
    expect(builds, 1);
  });
}
