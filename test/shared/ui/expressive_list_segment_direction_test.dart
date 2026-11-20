import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/shared/ui/expressive_group.dart';

// Сетка из двух колонок, собранная так же, как список серверов и плитки тем:
// зазор набирают поля самих сегментов, у сетки своих отступов нет.
Widget _grid(TextDirection direction, {required double spacing}) {
  return Directionality(
    textDirection: direction,
    child: CustomScrollView(
      slivers: [
        SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: 100,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => Padding(
              padding: ExpressiveListSegment.segmentMargin(
                index: i,
                columns: 2,
                spacing: spacing,
              ),
              child: SizedBox.expand(key: ValueKey(i)),
            ),
            childCount: 2,
          ),
        ),
      ],
    ),
  );
}

void main() {
  const spacing = 8.0;

  for (final direction in TextDirection.values) {
    testWidgets('зазор и края сетки одинаковы при $direction', (tester) async {
      await tester.pumpWidget(_grid(direction, spacing: spacing));

      final width = tester.getSize(find.byType(CustomScrollView)).width;
      final first = tester.getRect(find.byKey(const ValueKey(0)));
      final second = tester.getRect(find.byKey(const ValueKey(1)));
      final firstIsLeft = first.left < second.left;
      final left = firstIsLeft ? first : second;
      final right = firstIsLeft ? second : first;

      expect(right.left - left.right, spacing, reason: 'зазор между колонками');
      expect(left.left, spacing, reason: 'поле у левого края');
      expect(width - right.right, spacing, reason: 'поле у правого края');
    });
  }

  test('внешние углы первой плитки сетки следуют направлению текста', () {
    const outer = Radius.circular(ExpressiveListSegment.outerCorner);
    const inner = Radius.circular(ExpressiveListSegment.innerCorner);
    final radius = ExpressiveListSegment.segmentRadius(
      index: 0,
      count: 4,
      columns: 2,
    );

    // На фарси первая плитка стоит справа, и край группы у неё справа.
    final rtl = radius.resolve(TextDirection.rtl);
    expect(rtl.topRight, outer);
    expect(rtl.topLeft, inner);

    final ltr = radius.resolve(TextDirection.ltr);
    expect(ltr.topLeft, outer);
    expect(ltr.topRight, inner);
  });
}
