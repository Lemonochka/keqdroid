import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/shared/ui/bottom_nav.dart';

/// Геометрия нижней навигации.
///
/// Функциональные тесты (переключение вкладки, бейдж) проходили и на полностью
/// сломанной раскладке: пилюля выбранного пункта растягивалась на весь экран,
/// потому что `Align` с `widthFactor`, но без `heightFactor`, растёт в высоту до
/// максимума ограничений — а `bottomNavigationBar` получает от `Scaffold`
/// высоту всего экрана. Здесь проверяем именно размеры.
Future<void> _pumpNav(
  WidgetTester tester, {
  required int index,
  required Size screen,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = screen;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        bottomNavigationBar: AppBottomNav(
          index: index,
          showConnectedBadge: true,
          onTap: (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('nav bar stays a bar and does not fill the screen', (
    tester,
  ) async {
    await _pumpNav(tester, index: 0, screen: const Size(360, 800));

    final size = tester.getSize(find.byType(AppBottomNav));
    expect(size.height, lessThan(120));
    // Цель нажатия M3 — не меньше 48 логических пикселей.
    expect(size.height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected label is laid out in full, not clipped', (
    tester,
  ) async {
    await _pumpNav(tester, index: 0, screen: const Size(360, 800));

    final label = find.text('Servers');
    expect(label, findsOneWidget);

    // Ширина, которую подпись получила, против ширины, которая ей нужна.
    // Обрезка проявляется как первая заметно меньше второй.
    final rendered = tester.getSize(label).width;
    final intrinsic = (tester.renderObject(label) as RenderBox)
        .getMaxIntrinsicWidth(double.infinity);
    expect(rendered, greaterThanOrEqualTo(intrinsic - 0.5));
  });

  testWidgets('narrow window with long labels does not overflow', (
    tester,
  ) async {
    // Меню трея сжимает то же окно примерно до 288 px, а немецкие подписи
    // ощутимо длиннее английских.
    for (var index = 0; index < 3; index++) {
      await _pumpNav(
        tester,
        index: index,
        screen: const Size(288, 700),
        locale: const Locale('de'),
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'пункт $index переполняет ряд',
      );
      expect(tester.getSize(find.byType(AppBottomNav)).height, lessThan(120));
    }
  });

  testWidgets('no overflow midway through the selection spring', (
    tester,
  ) async {
    // Самое опасное место не покой, а переход: доля ряда под пункт и его
    // отступы обязаны ехать вместе. Когда доля падала мгновенно, а отступы
    // ещё анимировались, пункт переполнял ряд на промежуточных кадрах —
    // покадровая проверка, а не pumpAndSettle.
    tester.view.physicalSize = const Size(288, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var index = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            bottomNavigationBar: AppBottomNav(
              index: index,
              showConnectedBadge: true,
              onTap: (i) => setState(() => index = i),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.language));
    for (var frame = 0; frame < 40; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        tester.takeException(),
        isNull,
        reason: 'переполнение на кадре $frame перехода',
      );
    }
    await tester.pumpAndSettle();
    expect(index, 1);
  });
}
