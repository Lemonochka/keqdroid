import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/app/app.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/settings_tab.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:keqdroid/shared/ui/halloween/halloween_season.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

// в настройках живёт бесконечная анимация, pumpAndSettle не кончится
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> _openThemes(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final storage = await buildStorageService();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage),
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
  await tester.tap(find.text('Appearance'));
  await _frames(tester);
  await tester.tap(find.text('Themes'));
  await _frames(tester);
}

final _systemColors = find.byWidgetPredicate(
  (w) =>
      w is Text &&
      (w.data == 'Use system accent colors' ||
          w.data == 'Use Android dynamic colors'),
);

void main() {
  tearDown(() => HalloweenSeason.now = DateTime.now);

  testWidgets(
    'в праздник подпись про светлую и тёмную тему остаётся под системными цветами',
    (tester) async {
      HalloweenSeason.now = () => DateTime(2026, 10, 25, 12);
      await _openThemes(tester);

      final holiday = tester.getRect(find.text('Show holiday decorations'));
      final colors = tester.getRect(_systemColors);
      final hint = tester.getRect(
        find.text('Light/Dark still switches on its own'),
      );
      expect(holiday.top, lessThan(colors.top));
      expect(hint.top, greaterThan(colors.bottom));
    },
  );

  testWidgets('вне праздника переключателя нет', (tester) async {
    HalloweenSeason.now = () => DateTime(2026, 11, 5);
    await _openThemes(tester);

    expect(_systemColors, findsOneWidget);
    expect(find.text('Show holiday decorations'), findsNothing);
  });
}
