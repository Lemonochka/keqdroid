import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/app/app.dart';
import 'package:keqdroid/l10n/app_localizations_ru.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/platform/platform_bootstrap.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/settings_tab.dart';
import 'package:keqdroid/services/storage_service.dart';
import 'package:keqdroid/shared/ui/update_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_storage.dart';

final _ru = AppLocalizationsRu();

Future<StorageService> _pump(WidgetTester tester, Widget home,
    {AppSettings settings = const AppSettings(appLanguageCode: 'ru')}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  final storage = await tester.runAsync(() => buildStorageService(
        initialValues: {'keqdis_settings': settings.toJsonString()},
      ));
  await tester.pumpWidget(ProviderScope(
    overrides: [storageProvider.overrideWithValue(storage!)],
    child: KeqdisApp(home: Scaffold(body: home)),
  ));
  await tester.pumpAndSettle();
  return storage;
}

void main() {
  setUp(() => PlatformBootstrap.debugIsDesktopOverride = false);
  tearDown(() => PlatformBootstrap.debugIsDesktopOverride = null);

  group('как часто сообщать о новой версии', () {
    test('по умолчанию раз в 3 дня, чужие значения тоже 3', () {
      expect(const AppSettings().updatePromptDays, 3);
      for (final (raw, want) in [(1, 1), (7, 7), (3, 3), (2, 3), (null, 3), ('7', 3)]) {
        final s = AppSettings.fromJson({'updatePromptDays': raw});
        expect(s.updatePromptDays, want, reason: '$raw');
      }
      final back = AppSettings.fromJson(
        const AppSettings().copyWith(updatePromptDays: 7).toJson(),
      );
      expect(back.updatePromptDays, 7);
    });

    test('окно не чаще выбранного срока, а сдвинутые назад часы его не запирают', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      const day = 24 * 60 * 60 * 1000;

      SharedPreferences.setMockInitialValues({});
      expect(await UpdatePrompt.autoPromptDue(3), isTrue);
      await UpdatePrompt.markAutoPrompted();
      expect(await UpdatePrompt.autoPromptDue(1), isFalse);
      expect(await UpdatePrompt.autoPromptDue(3), isFalse);

      SharedPreferences.setMockInitialValues({'update_auto_prompted_at': now - 2 * day});
      expect(await UpdatePrompt.autoPromptDue(1), isTrue);
      expect(await UpdatePrompt.autoPromptDue(3), isFalse);

      SharedPreferences.setMockInitialValues({'update_auto_prompted_at': now - 8 * day});
      expect(await UpdatePrompt.autoPromptDue(7), isTrue);

      SharedPreferences.setMockInitialValues({'update_auto_prompted_at': now + day});
      expect(await UpdatePrompt.autoPromptDue(7), isTrue);
    });
  });

  testWidgets('на экране «Поведение» выбор срока сохраняется, уведомления переехали сюда', (tester) async {
    await _pump(tester, behaviourSettingsScreenForTest());
    expect(find.text(_ru.behaviourUpdatePrompt), findsOneWidget);
    expect(find.text(_ru.appearanceNotifSpeedTitle), findsOneWidget);
    expect(find.text(_ru.appearanceNotifUptimeTitle), findsOneWidget);
    expect(find.text(_ru.appearanceNotifSubUpdatesTitle), findsOneWidget);

    await tester.tap(find.text(_ru.behaviourEveryWeek));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.text(_ru.behaviourUpdatePrompt)),
    );
    expect(container.read(settingsNotifierProvider).value?.updatePromptDays, 7);
  });

  testWidgets('во «Внешнем виде» уведомлений больше нет', (tester) async {
    await _pump(tester, appearanceGeneralTabForTest(const AppSettings(appLanguageCode: 'ru')));
    expect(find.text(_ru.appearanceNotifSpeedTitle, skipOffstage: false), findsNothing);
    expect(find.text(_ru.appearanceNotifSectionTitle, skipOffstage: false), findsNothing);
  });

  testWidgets('на узком телефоне выбор срока помещается', (tester) async {
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final storage = await tester.runAsync(() => buildStorageService(
          initialValues: {
            'keqdis_settings':
                const AppSettings(appLanguageCode: 'ru').toJsonString(),
          },
        ));
    await tester.pumpWidget(ProviderScope(
      overrides: [storageProvider.overrideWithValue(storage!)],
      child: KeqdisApp(home: Scaffold(body: behaviourSettingsScreenForTest())),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(_ru.behaviourEveryWeek), findsOneWidget);
  });
}
