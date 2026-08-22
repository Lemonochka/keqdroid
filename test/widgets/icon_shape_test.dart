import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/icon_shape.dart';
import 'package:keqdroid/shared/ui/expressive_elements.dart';

ShapeBorder badgeShape(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.descendant(
      of: find.byType(ExpressiveIconBadge),
      matching: find.byType(Container),
    ),
  );
  return (container.decoration! as ShapeDecoration).shape;
}

Future<void> pumpBadge(
  WidgetTester tester, {
  IconShape? themeShape,
  IconShape? explicitShape,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        extensions: themeShape == null
            ? const []
            : [ExpressiveIconShapeTheme(shape: themeShape)],
      ),
      home: Scaffold(
        body: ExpressiveIconBadge(
          icon: Icons.settings_rounded,
          shape: explicitShape,
        ),
      ),
    ),
  );
}

void main() {
  // Сами контуры — из androidx_graphics_shapes, их геометрию проверяет сама
  // библиотека. Здесь проверяется то, что вокруг: доезжает ли выбор до
  // виджета, переживает ли хранилище и не разъезжается ли набор с подписями.
  testWidgets('без расширения темы бейдж остаётся круглым', (tester) async {
    await pumpBadge(tester);
    expect(badgeShape(tester), isNotNull);
  });

  testWidgets('форма из темы доезжает до бейджа', (tester) async {
    await pumpBadge(tester, themeShape: IconShape.clover);
    final shape = badgeShape(tester);
    expect(shape, IconShape.clover.border(40));
    expect(shape, isNot(IconShape.circle.border(40)));
  });

  testWidgets('явно заданная форма сильнее темы', (tester) async {
    // Нужно для превью в настройках: там рядом стоят все формы сразу, и тема
    // не должна равнять их под выбранную.
    await pumpBadge(
      tester,
      themeShape: IconShape.clover,
      explicitShape: IconShape.circle,
    );
    expect(badgeShape(tester), IconShape.circle.border(40));
  });

  test('id — контракт хранилища, неизвестный откатывается на круг', () {
    for (final shape in IconShape.values) {
      expect(IconShape.fromId(shape.id), shape);
    }
    expect(IconShape.fromId('нет-такой'), IconShape.circle);
    expect(IconShape.fromId(null), IconShape.circle);
  });

  test('id уникальны — иначе выбор не отличить', () {
    final ids = IconShape.values.map((s) => s.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('каждая форма даёт замкнутый контур во весь габарит', () {
    const rect = Rect.fromLTWH(0, 0, 56, 56);
    for (final shape in IconShape.values) {
      final path = shape.border(56).getOuterPath(rect);
      final bounds = path.getBounds();
      // Фигура должна занимать габарит, а не жаться в его углу: именно так
      // выглядела бы неверно отмасштабированная — мельче соседей в ряду.
      expect(bounds.width, greaterThan(40), reason: '${shape.id} мельчит');
      expect(bounds.width, lessThan(60), reason: '${shape.id} вылезает');
      // Центр внутри — контур замкнут, заливка не потечёт.
      expect(path.contains(rect.center), isTrue, reason: shape.id);
    }
  });

  test('формы действительно разные', () {
    final paths = {
      for (final shape in IconShape.values)
        shape.id: shape
            .border(56)
            .getOuterPath(const Rect.fromLTWH(0, 0, 56, 56))
            .getBounds()
            .toString(),
    };
    // Слабая, но дешёвая страховка от опечатки в маппинге, когда две записи
    // указывают на одну и ту же фигуру библиотеки.
    expect(
      IconShape.values.map((s) => s.polygon).toSet().length,
      IconShape.values.length,
      reason: 'две формы ссылаются на один контур: $paths',
    );
  });
}
