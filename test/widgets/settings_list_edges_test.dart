import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/app/app.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/settings_tab.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:keqdroid/shared/ui/smooth_fade.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

/// Края списка настроек: верх не гаснет, низ плавно уходит под версию, и над версией нет линии.

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> _pumpSettings(WidgetTester tester) async {
  tester.view.physicalSize = const Size(700, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final storage = (await tester.runAsync(buildStorageService))!;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage),
        vpnEngineProvider.overrideWithValue(VpnEngine.withBackend(FakeTunnelBackend())),
        updateInfoProvider.overrideWith((ref) async => null),
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
  await _frames(tester);
}

void main() {
  testWidgets('у настроек гаснет низ под версией, а верх нет и при прокрутке', (tester) async {
    await _pumpSettings(tester);
    EdgeFadeMask fade() => tester.widget<EdgeFadeMask>(
          find.ancestor(of: find.byType(ListView).first, matching: find.byType(EdgeFadeMask)),
        );
    expect(fade().bottom, greaterThan(20));
    expect(fade().top, 0);
    await tester.drag(find.byType(ListView).first, const Offset(0, -200));
    await _frames(tester);
    expect(fade().top, 0);
  });

  testWidgets('над версией приложения нет разделительной линии', (tester) async {
    await _pumpSettings(tester);
    expect(find.text('App version'), findsOneWidget);
    expect(find.byType(Divider), findsNothing);
  });
}
