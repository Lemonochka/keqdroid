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

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  testWidgets(
    'соединения и журналы доступны из диагностики без режима отладки',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final StorageService storage = (await tester.runAsync(
        () => buildStorageService(
          initialValues: {
            'keqdis_settings': const AppSettings().toJsonString(),
          },
        ),
      ))!;

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
            home: advancedSettingsScreenForTest(),
          ),
        ),
      );
      await _frames(tester);

      expect(find.text('Connections and logs'), findsOneWidget);
      expect(find.text('Share device HWID'), findsOneWidget);
      expect(find.text('Debug mode'), findsNothing);

      await tester.tap(find.text('Connections and logs'));
      await _frames(tester);

      TabBarView view = tester.widget(find.byType(TabBarView));
      expect(view.controller?.index, 0);
      expect(find.byTooltip('Pause updates'), findsOneWidget);
      expect(find.byTooltip('Copy the whole log'), findsNothing);

      await tester.tap(find.byTooltip('Pause updates'));
      await _frames(tester);
      expect(find.text('Paused'), findsOneWidget);
      expect(find.byTooltip('Resume updates'), findsOneWidget);

      await tester.tap(find.widgetWithText(Tab, 'Logs'));
      await _frames(tester);

      view = tester.widget(find.byType(TabBarView));
      expect(view.controller?.index, 1);
      expect(find.text('App'), findsOneWidget);
      expect(find.text('Core logs'), findsOneWidget);
      expect(find.byTooltip('Copy the whole log'), findsOneWidget);
      expect(find.byTooltip('Pause updates'), findsNothing);

      await tester.tap(find.text('Core logs'));
      await _frames(tester);

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Core logs'),
        ),
        findsOneWidget,
      );
      expect(
        find.text('No Xray session logs yet. Connect VPN first.'),
        findsOne,
      );
      expect(find.text('Debug mode'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
