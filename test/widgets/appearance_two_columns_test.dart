import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/app/app.dart';
import 'package:keqdroid/l10n/app_localizations_en.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/platform/platform_bootstrap.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/settings_tab.dart';

import '../helpers/test_storage.dart';

final _noRoom = AppLocalizationsEn().serversColumnsNoRoom;

Future<void> _pump(
  WidgetTester tester, {
  required double uiScale,
  required bool twoColumns,
  int columns = 2,
}) async {
  // Pixel 6a: 1080x2400 при 2.625, 411 dp в ширину
  tester.view.devicePixelRatio = 2.625;
  tester.view.physicalSize = const Size(1080, 2400);
  addTearDown(tester.view.reset);
  final settings = const AppSettings().copyWith(
    uiScale: uiScale,
    serversTwoColumns: twoColumns,
    serversColumns: columns,
  );
  final storage = await tester.runAsync(() => buildStorageService(
        initialValues: {'keqdis_settings': settings.toJsonString()},
      ));
  await tester.pumpWidget(ProviderScope(
    overrides: [storageProvider.overrideWithValue(storage!)],
    child: KeqdroidApp(
      home: Scaffold(body: appearanceGeneralTabForTest(settings)),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => PlatformBootstrap.debugIsDesktopOverride = false);
  tearDown(() => PlatformBootstrap.debugIsDesktopOverride = null);

  testWidgets('при 140% на телефоне две колонки объясняют, что не помещаются',
      (tester) async {
    await _pump(tester, uiScale: 1.4, twoColumns: true);
    expect(find.text(_noRoom, skipOffstage: false), findsOneWidget);
  });

  testWidgets('при 100% подписи нет', (tester) async {
    await _pump(tester, uiScale: 1.0, twoColumns: true);
    expect(find.text(_noRoom, skipOffstage: false), findsNothing);
  });

  testWidgets('выключенным двум колонкам объяснять нечего', (tester) async {
    await _pump(tester, uiScale: 1.4, twoColumns: false);
    expect(find.text(_noRoom, skipOffstage: false), findsNothing);
  });

  testWidgets('из трёх колонок при 100% помещаются две, и это сказано',
      (tester) async {
    await _pump(tester, uiScale: 1.0, twoColumns: true, columns: 3);
    expect(
      find.text(AppLocalizationsEn().serversColumnsOnlyFit(2),
          skipOffstage: false),
      findsOneWidget,
    );
  });
}
