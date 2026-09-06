import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqtris/keqtris.dart';

/// Экран игры целиком, без приложения вокруг.
///
/// Пять нажатий по версии, которыми игра открывается, тестом не накрыты: экран
/// «О приложении» берёт данные из приватного провайдера, подменить который
/// снаружи нечем, и он показывает спиннер вместо строк. Мокать ради счётчика
/// нажатий половину платформенных каналов — размен не в нашу пользу; тот вход
/// проверяется руками.
Widget _host({int best = 0, ValueChanged<int>? onGameOver}) => MaterialApp(
  theme: ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB2BDFF)),
  ),
  home: KeqtrisScreen(
    bestScore: best,
    onGameOver: onGameOver ?? (_) {},
  ),
);

Future<void> _advance(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('раскладка сходится на телефоне без переполнений', (
    tester,
  ) async {
    await phone(tester);
    await tester.pumpWidget(_host());
    await _advance(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('переданный рекорд показывается сразу', (tester) async {
    await phone(tester);
    await tester.pumpWidget(_host(best: 4200));
    await _advance(tester);

    expect(find.text('4200'), findsOneWidget);
  });

  testWidgets('подписи приходят снаружи', (tester) async {
    await phone(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: KeqtrisScreen(
          bestScore: 0,
          onGameOver: (_) {},
          labels: const KeqtrisLabels(score: 'СЧЁТ', best: 'РЕКОРД'),
        ),
      ),
    );
    await _advance(tester);

    expect(find.text('СЧЁТ'), findsOneWidget);
    expect(find.text('РЕКОРД'), findsOneWidget);
  });

  testWidgets('экран просит кадры, пока партия идёт', (tester) async {
    await phone(tester);
    await tester.pumpWidget(_host());
    await _advance(tester);

    expect(tester.binding.transientCallbackCount, greaterThan(0));
  });
}
