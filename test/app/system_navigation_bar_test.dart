import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/app/app.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/providers/providers.dart';

import '../helpers/test_storage.dart';

// на HyperOS панель навигации без явного стиля красилась по теме системы и в тёмной теме
// приложения оставалась белой
Future<SystemUiOverlayStyle?> _styleFor(WidgetTester tester, {required bool dark}) async {
  final settings = const AppSettings().copyWith(darkTheme: dark);
  final storage = await tester.runAsync(() => buildStorageService(
        initialValues: {'keqdis_settings': settings.toJsonString()},
      ));
  await tester.pumpWidget(ProviderScope(
    overrides: [storageProvider.overrideWithValue(storage!)],
    child: const KeqdisApp(home: Scaffold(body: SizedBox.expand())),
  ));
  await tester.pumpAndSettle();
  return SystemChrome.latestStyle;
}

void main() {
  testWidgets('в тёмной теме панель навигации тёмная, кнопки светлые', (tester) async {
    final style = await _styleFor(tester, dark: true);
    expect(style?.systemNavigationBarIconBrightness, Brightness.light);
    expect(style!.systemNavigationBarColor!.computeLuminance(), lessThan(0.2));
    // заданная одна панель на Pixel перекрашивала значки сверху в тёмные
    expect(style.statusBarIconBrightness, Brightness.light);
  });

  testWidgets('в светлой теме панель светлая, кнопки тёмные', (tester) async {
    final style = await _styleFor(tester, dark: false);
    expect(style?.systemNavigationBarIconBrightness, Brightness.dark);
    expect(style!.systemNavigationBarColor!.computeLuminance(), greaterThan(0.5));
    expect(style.statusBarIconBrightness, Brightness.dark);
  });
}
