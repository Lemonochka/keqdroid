import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/bidi.dart';

/// Технические значения в RTL-локали.
///
/// Проверяется не текст, а ГЕОМЕТРИЯ: обе ошибки этого класса — про порядок на
/// экране при полностью правильных строках, и обычный `expect(find.text(...))`
/// их не видит вовсе.
const _usedKey = Key('used');
const _limitKey = Key('limit');

Future<void> _pumpUsageRow(
  WidgetTester tester, {
  required TextDirection direction,
  required bool wrapInLtrBlock,
}) async {
  const row = Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('621.8 GiB', key: _usedKey),
      SizedBox(width: 8),
      Text('/ 100 GiB', key: _limitKey),
    ],
  );
  await tester.pumpWidget(
    Directionality(
      textDirection: direction,
      child: Align(
        alignment: AlignmentDirectional.topStart,
        child: wrapInLtrBlock ? const LtrBlock(child: row) : row,
      ),
    ),
  );
}

double _dx(WidgetTester tester, Key key) => tester.getTopLeft(find.byKey(key)).dx;

void main() {
  group('subscription usage reads left-to-right in Farsi', () {
    testWidgets('a bare Row mirrors the parts — this was the bug',
        (tester) async {
      // Страховка от «починили и не заметили, что чинить было нечего»: без
      // LtrBlock порядок действительно обратный.
      await _pumpUsageRow(
        tester,
        direction: TextDirection.rtl,
        wrapInLtrBlock: false,
      );
      expect(_dx(tester, _usedKey), greaterThan(_dx(tester, _limitKey)));
    });

    testWidgets('LtrBlock keeps used before the limit', (tester) async {
      await _pumpUsageRow(
        tester,
        direction: TextDirection.rtl,
        wrapInLtrBlock: true,
      );
      expect(_dx(tester, _usedKey), lessThan(_dx(tester, _limitKey)));
    });

    testWidgets('LtrBlock changes nothing in an LTR locale', (tester) async {
      await _pumpUsageRow(
        tester,
        direction: TextDirection.ltr,
        wrapInLtrBlock: true,
      );
      expect(_dx(tester, _usedKey), lessThan(_dx(tester, _limitKey)));
    });

    testWidgets('the block still hugs the RTL start edge', (tester) async {
      // Смысл LtrBlock — только внутренний порядок. Если он утащит блок к
      // левому краю, персидская карточка развалится по-другому.
      const wide = Size(400, 200);
      await tester.binding.setSurfaceSize(wide);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pumpUsageRow(
        tester,
        direction: TextDirection.rtl,
        wrapInLtrBlock: true,
      );

      final right = tester.getTopRight(find.byKey(_limitKey)).dx;
      expect(right, closeTo(wide.width, 1));
    });
  });

  testWidgets('LtrBlock does not touch the string itself', (tester) async {
    // Выделяемый и копируемый текст можно чинить только направлением: изолят
    // дописал бы в буфер обмена невидимые управляющие символы.
    const address = '203.0.113.9:443';
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.rtl,
        child: LtrBlock(child: Text(address)),
      ),
    );
    expect(find.text(address), findsOneWidget);
    expect(ltrIsolate(address), isNot(address));
  });
}
