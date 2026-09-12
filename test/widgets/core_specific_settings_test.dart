import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/app/app.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/settings_tab.dart';
import 'package:keqdroid/services/vpn_engine.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

/// Настройки, которых у второго ядра нет, показываются только при своём ядре.
///
/// Жалоба звучала так: настройка стоит на экране у всех, включаешь — ничего не
/// происходит, и только потом читаешь мелкий текст под ней о том, что она про
/// другое ядро. Теперь при чужом ядре её на экране нет вовсе, и тест сторожит
/// обе стороны: и что она пропала, и что при своём ядре она на месте.
class _FakeSettings extends SettingsNotifier {
  _FakeSettings(this._settings);
  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> save(AppSettings settings) async => state = AsyncData(settings);
}

/// `pumpAndSettle` тут не годится: в настройках живёт бесконечная анимация.
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> _openAppearance(WidgetTester tester, String core) async {
  final storage = await buildStorageService();
  // Активного сервера нет: тогда ядро берётся из самой настройки, и тест не
  // зависит от того, какой формат сервера чем исполняется.
  final settings = AppSettings(vpnCore: core);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage),
        settingsNotifierProvider.overrideWith(() => _FakeSettings(settings)),
        vpnEngineProvider.overrideWithValue(
          VpnEngine.withBackend(FakeTunnelBackend()),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        theme: buildAppTheme(
          buildPresetScheme(themePresetFor(settings), Brightness.light),
        ),
        home: const SettingsTab(),
      ),
    ),
  );
  await _frames(tester);
  await tester.tap(find.text('Appearance'));
  await _frames(tester);
}

void main() {
  testWidgets('разбивка трафика есть на mihomo', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openAppearance(tester, AppSettings.vpnCoreMihomo);
    expect(find.text('Show VPN and direct apart'), findsOneWidget);
  });

  testWidgets('на xray её нет: считать разбивку он не умеет', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openAppearance(tester, AppSettings.vpnCoreXray);
    expect(find.text('Show VPN and direct apart'), findsNothing);
    // Соседние переключатели той же группы на месте — спрятана ровно одна
    // строка, а не вся секция.
    expect(find.text('Show traffic'), findsOneWidget);
  });
}
