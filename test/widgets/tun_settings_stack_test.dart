import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/app/app.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/settings_tab.dart';
import 'package:keqdroid/services/storage_service.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:keqdroid/tunnel/vpn_backend.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

// TUN на ПК при Xray держит сам xray и только на gVisor: выбирать стек там
// нечего, и переключатель без эффекта прятать (мёртвых настроек не бывает).
// У mihomo стеки свои, выбор остаётся.
class _Settings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

// pumpAndSettle не годится: в настройках живёт бесконечная анимация
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> _openCoreSettings(
  WidgetTester tester,
  VpnBackend core, {
  bool realSettings = false,
  StorageService? storageOverride,
}) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final storage = storageOverride ?? await buildStorageService();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage),
        if (!realSettings) settingsNotifierProvider.overrideWith(_Settings.new),
        activeVpnBackendProvider.overrideWithValue(core),
        vpnEngineProvider.overrideWithValue(
          VpnEngine.withBackend(FakeTunnelBackend()),
        ),
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
        home: const SettingsTab(),
      ),
    ),
  );
  await _frames(tester);
  for (final item in const ['Advanced', 'Core settings']) {
    final finder = find.text(item).first;
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await _frames(tester);
  }
  // раздел TUN есть только на Windows и Linux, тесты идут там же
  await tester.scrollUntilVisible(
    find.text('Strict route'),
    400,
    // у Xray в разделах есть горизонтальные прокрутки, крутить нужно сам экран
    scrollable: find
        .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        )
        .first,
  );
  await _frames(tester);
}

void main() {
  testWidgets('Xray: выбора стека нет, остальной раздел TUN на месте', (
    tester,
  ) async {
    await _openCoreSettings(tester, VpnBackend.xray);
    expect(find.text('TUN mode'), findsWidgets);
    expect(find.text('Network stack'), findsNothing);
    expect(find.text('gVisor'), findsNothing);
    final strictTile = find.widgetWithText(SwitchListTile, 'Strict route');
    expect(strictTile, findsOneWidget);
    expect(tester.widget<SwitchListTile>(strictTile).value, isTrue);
    expect(find.text('Linux: on, Windows: off'), findsNothing);
  });

  testWidgets('mihomo: все четыре стека на выбор', (tester) async {
    await _openCoreSettings(tester, VpnBackend.mihomo);
    expect(find.text('Network stack'), findsOneWidget);
    for (final stack in const ['system', 'gVisor', 'mixed', 'Mips']) {
      expect(find.text(stack), findsOneWidget, reason: stack);
    }
  });

  testWidgets('Strict route выключается и включается тумблером с сохранением', (
    tester,
  ) async {
    final storage = await buildStorageService();
    await _openCoreSettings(
      tester,
      VpnBackend.xray,
      realSettings: true,
      storageOverride: storage,
    );

    final strictTile = find.widgetWithText(SwitchListTile, 'Strict route');
    expect(tester.widget<SwitchListTile>(strictTile).value, isTrue);

    await tester.ensureVisible(strictTile);
    await tester.tap(strictTile);
    await _frames(tester);
    expect(tester.widget<SwitchListTile>(strictTile).value, isFalse);
    expect((await storage.getSettings()).tun.strictRoute, isFalse);

    await tester.tap(strictTile);
    await _frames(tester);
    expect(tester.widget<SwitchListTile>(strictTile).value, isTrue);
    expect((await storage.getSettings()).tun.strictRoute, isTrue);
  });
}
