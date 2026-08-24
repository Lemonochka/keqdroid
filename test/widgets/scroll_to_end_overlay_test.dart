import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/shared/ui/scroll_to_end_overlay.dart';

/// Кружок «в конец списка» на телефоне.
///
/// Всё ценное в нём — про «чтобы не мешался»: появляется от настоящей
/// прокрутки, только когда до конца далеко, и уходит сам. Кнопка, висящая
/// поверх списка постоянно, была бы хуже отсутствия кнопки.
Finder get _button => find.byIcon(Icons.keyboard_double_arrow_down_rounded);

double _opacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(
      find.ancestor(of: _button, matching: find.byType(AnimatedOpacity)),
    )
    .opacity;

Future<ScrollController> _pump(
  WidgetTester tester, {
  bool enabled = true,
  int items = 60,
  double minRemainingExtent = 600,
}) async {
  final controller = ScrollController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ScrollToEndOverlay(
          enabled: enabled,
          label: 'К концу списка',
          minRemainingExtent: minRemainingExtent,
          child: ListView.builder(
            controller: controller,
            itemCount: items,
            itemBuilder: (context, i) =>
                SizedBox(height: 60, child: Text('item $i')),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('без прокрутки кнопки не видно', (tester) async {
    await _pump(tester);

    expect(_opacity(tester), 0);
  });

  testWidgets('появляется от прокрутки и уходит сама', (tester) async {
    await _pump(tester);

    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_opacity(tester), 1);

    // Прокрутка кончилась — через паузу кнопка обязана убраться сама.
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(_opacity(tester), 0);
  });

  testWidgets('нажатие увозит в самый конец', (tester) async {
    final controller = await _pump(tester);

    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(_button);
    await tester.pumpAndSettle();

    expect(controller.offset, controller.position.maxScrollExtent);
  });

  testWidgets('у конца списка не показывается — докрутить проще', (
    tester,
  ) async {
    final controller = await _pump(tester);

    controller.jumpTo(controller.position.maxScrollExtent - 100);
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(_opacity(tester), 0);
  });

  testWidgets('на коротком списке не появляется вовсе', (tester) async {
    await _pump(tester, items: 8);

    await tester.drag(find.byType(ListView), const Offset(0, -60));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(_opacity(tester), 0);
  });

  testWidgets('невидимая кнопка не перехватывает тапы по списку', (
    tester,
  ) async {
    await _pump(tester);

    final ignoring = tester
        .widgetList<IgnorePointer>(
          find.ancestor(of: _button, matching: find.byType(IgnorePointer)),
        )
        .any((w) => w.ignoring);
    expect(ignoring, isTrue);
  });

  testWidgets('выключенная обёртка не рисует ничего', (tester) async {
    await _pump(tester, enabled: false);

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(_button, findsNothing);
  });
}
