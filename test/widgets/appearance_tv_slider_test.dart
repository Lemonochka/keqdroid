import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/app/app.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/platform/platform_bootstrap.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/settings_tab.dart';

import '../helpers/test_storage.dart';

// жалоба с Android TV 30.10.2026: дошёл пультом до масштаба, и обратно наверх не уйти
Future<FocusNode> _focusScaleSlider(
  WidgetTester tester, {
  bool tabsAbove = true,
  Future<void> Function(AppSettings)? onSave,
}) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = const Size(1920, 1080);
  addTearDown(tester.view.reset);
  const settings = AppSettings();
  final storage = await tester.runAsync(() => buildStorageService(
        initialValues: {'keqdis_settings': settings.toJsonString()},
      ));
  final tab = appearanceGeneralTabForTest(settings, onSave: onSave);
  await tester.pumpWidget(ProviderScope(
    overrides: [storageProvider.overrideWithValue(storage!)],
    child: KeqdisApp(
      // кнопка сверху вместо вкладок экрана
      home: Scaffold(
        body: tabsAbove
            ? Column(
                children: [
                  TextButton(onPressed: () {}, child: const Text('tabs')),
                  Expanded(child: tab),
                ],
              )
            : tab,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  final node = tester
      .widget<FocusableActionDetector>(find.descendant(
          of: find.byType(Slider), matching: find.byType(FocusableActionDetector)))
      .focusNode!;
  node.requestFocus();
  await tester.pumpAndSettle();
  expect(node.hasPrimaryFocus, isTrue);
  return node;
}

void main() {
  setUp(() {
    PlatformBootstrap.debugIsDesktopOverride = false;
    PlatformBootstrap.debugIsTelevisionOverride = true;
  });
  tearDown(() {
    PlatformBootstrap.debugIsDesktopOverride = null;
    PlatformBootstrap.debugIsTelevisionOverride = null;
  });

  for (final key in [LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowDown]) {
    testWidgets('на телевизоре ${key.keyLabel} уводит пульт с ползунка масштаба, не трогая его', (tester) async {
      final node = await _focusScaleSlider(tester);
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      expect(node.hasPrimaryFocus, isFalse);
      expect(find.text('100%'), findsOneWidget);
    });
  }

  testWidgets('на телевизоре вправо по-прежнему крутит масштаб', (tester) async {
    final node = await _focusScaleSlider(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(node.hasPrimaryFocus, isTrue);
    expect(find.text('105%'), findsOneWidget);
  });

  testWidgets('на телевизоре шрифт выбирается пультом: вверх с масштаба встаёт на шрифт, OK его выбирает', (tester) async {
    final saved = <AppSettings>[];
    await _focusScaleSlider(tester, tabsAbove: false, onSave: (s) async => saved.add(s));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(saved, hasLength(1));
    expect(saved.single.fontId, isNot(const AppSettings().fontId));
  });

  testWidgets('на телевизоре форма значков выбирается пультом: вниз с масштаба и OK', (tester) async {
    final saved = <AppSettings>[];
    await _focusScaleSlider(tester, onSave: (s) async => saved.add(s));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(saved, hasLength(1));
    expect(saved.single.iconShapeId, isNot(const AppSettings().iconShapeId));
  });
}
