import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/shared/ui/accent_edge_card.dart';

/// Карточка всегда живёт в вертикальном списке, а он раздаёт детям
/// неограниченную высоту — проверять её в чём-то с конечной высотой
/// бессмысленно: так не видно ни переполнения, ни бесконечных constraint'ов.
Widget _inList(Widget child) => MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7B61FF),
          brightness: Brightness.dark,
        ),
      ),
      home: Scaffold(
        body: ListView(children: [child]),
      ),
    );

void main() {
  group('AccentEdgeCard', () {
    // Регрессия №1: цветная полоска была левой стороной Border вместе с
    // borderRadius — такую рамку Flutter не рисует и бросает в paint-фазе.
    // Регрессия №2: полоску во всю высоту нельзя делать через Row со stretch —
    // в списке это tightFor(height: infinity) и падение уже в layout.
    // Оба раза исключение глотается на уровне render object'а: приложение живо,
    // но содержимое карточки не доходит до экрана, и экран «Соединения»
    // выглядит пустым при непустом счётчике.
    testWidgets('lays out and paints inside a list without throwing',
        (tester) async {
      await tester.pumpWidget(
        _inList(
          const AccentEdgeCard(
            edgeColor: Color(0xFF4CAF50),
            child: Text('tcp:example.com:443'),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('tcp:example.com:443'), findsOneWidget);
    });

    testWidgets('height follows the content, not the incoming constraints',
        (tester) async {
      await tester.pumpWidget(
        _inList(
          const AccentEdgeCard(
            edgeColor: Color(0xFF4CAF50),
            child: SizedBox(height: 120),
          ),
        ),
      );

      // 120 содержимое + 12 padding сверху и снизу + 1 рамка сверху и снизу.
      expect(tester.getSize(find.byType(AccentEdgeCard)).height, 146);
    });

    testWidgets('accent stripe spans the full inner height', (tester) async {
      await tester.pumpWidget(
        _inList(
          const AccentEdgeCard(
            edgeColor: Color(0xFF4CAF50),
            child: SizedBox(height: 120),
          ),
        ),
      );

      final stripe = tester.getSize(
        find.descendant(
          of: find.byType(AccentEdgeCard),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(stripe.width, 3);
      // Внутренняя высота карточки: всё, кроме рамки сверху и снизу.
      expect(stripe.height, 144);
    });
  });
}
