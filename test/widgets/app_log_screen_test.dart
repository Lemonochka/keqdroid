import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/app/app.dart';
import 'package:keqdroid/core/app_logger.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/screens/settings_tab.dart';

/// `pumpAndSettle` тут не годится: журнал части опрашивается по таймеру.
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

/// Даёт настоящему чтению файла журнала дойти до конца: в поддельном времени
/// теста оно само не идёт.
Future<void> _settle(WidgetTester tester, Finder until) async {
  for (var i = 0; i < 50 && until.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await _frames(tester);
}

/// Вход в журнал говорит, в какой части проблемы, а журнал части с фильтром
/// «только проблемы» прячет обычные строки и оставляет ошибки.
void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('app_log_screen');
    AppLogger.instance.enableFileLogIn(dir);
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('от счётчика на входе до строки с ошибкой', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() async {
      AppLogger.instance.info('subscription refreshed');
      AppLogger.instance.error('Background subscription update task failed');
    });

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        theme: buildAppTheme(
          buildPresetScheme(themePresetFor(const AppSettings()), Brightness.light),
        ),
        home: appLogScreenForTest(),
      ),
    );
    await _settle(tester, find.text('1 problem'));

    // Одна ошибка в app.log — и вход в журнал говорит это до того, как его
    // открыли.
    expect(find.text('1 problem'), findsOneWidget);

    await tester.tap(find.text('App'));
    await _settle(tester, find.textContaining('update task failed'));
    expect(find.textContaining('subscription refreshed'), findsOneWidget);
    expect(find.textContaining('update task failed'), findsOneWidget);

    await tester.tap(find.text('Problems only'));
    await _frames(tester);
    expect(find.textContaining('subscription refreshed'), findsNothing);
    expect(find.textContaining('update task failed'), findsOneWidget);
  });

  testWidgets('на телефоне журнал уходит файлом через меню «Поделиться»', (tester) async {
    final temp = Directory.systemTemp.createTempSync('app_log_share');
    addTearDown(() => temp.deleteSync(recursive: true));
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => temp.path,
    );
    String? sharedName;
    String? sharedText;
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/share'),
      (call) async {
        final path = ((call.arguments as Map)['paths'] as List).single as String;
        sharedName = File(path).uri.pathSegments.last;
        sharedText = File(path).readAsStringSync();
        return 'com.example.chosen';
      },
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/share'),
        null,
      );
    });

    await tester.runAsync(() async {
      for (var i = 0; i < 310; i++) {
        AppLogger.instance.info('record ${i.toString().padLeft(3, '0')}');
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: appLogScreenForTest(shareAsFile: true),
      ),
    );
    await _frames(tester);

    expect(find.byTooltip('Copy the whole log'), findsNothing);
    await tester.tap(find.byTooltip('Send the log as a file'));
    for (var i = 0; i < 50 && (sharedText == null || temp.listSync().isNotEmpty); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(sharedName, matches(RegExp(r'^keqdroid-log-\d{4}-\d{2}-\d{2}-\d{4}\.txt$')));
    expect(sharedText, contains('record 000'));
    expect(sharedText, contains('record 309'));
    // копию держит share_plus, наша в кэше не копится
    expect(temp.listSync(), isEmpty);
  });
}
