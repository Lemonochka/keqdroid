import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/shared/ui/scroll_jump_overlay.dart';

/// Кружок «на другой конец списка» на телефоне.
///
/// Половина ценного в нём — про «чтобы не мешался»: появляется от настоящей
/// прокрутки, только когда до цели далеко, и уходит сам. Вторая половина — про
/// направление: за серединой списка кнопка ведёт обратно наверх, иначе после
/// первого же нажатия она бесполезна, а возвращаться приходится свайпами.
Finder get _button => find.byIcon(Icons.arrow_downward_rounded);

double _opacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(
      find.ancestor(of: _button, matching: find.byType(AnimatedOpacity)),
    )
    .opacity;

/// Пол-оборота — та же стрелка, развёрнутая наверх.
double _turns(WidgetTester tester) => tester
    .widget<AnimatedRotation>(
      find.ancestor(of: _button, matching: find.byType(AnimatedRotation)),
    )
    .turns;

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
        body: ScrollJumpOverlay(
          enabled: enabled,
          endLabel: 'К концу списка',
          topLabel: 'К началу списка',
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

/// Прокрутка на [offset] с добавочным свайпом: кнопка обязана подниматься от
/// НАСТОЯЩЕГО движения, и тест ходит тем же путём, что палец.
Future<void> _scrollTo(
  WidgetTester tester,
  ScrollController controller,
  double offset,
) async {
  controller.jumpTo(offset);
  await tester.pump();
  await tester.drag(find.byType(ListView), const Offset(0, -20));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
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

  testWidgets('до середины списка ведёт вниз и увозит в самый конец', (
    tester,
  ) async {
    final controller = await _pump(tester);

    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_turns(tester), 0);

    await tester.tap(_button);
    await tester.pumpAndSettle();

    expect(controller.offset, controller.position.maxScrollExtent);
  });

  testWidgets('за серединой разворачивается и увозит к началу', (tester) async {
    final controller = await _pump(tester);
    final middle = controller.position.maxScrollExtent / 2;

    await _scrollTo(tester, controller, middle + 200);

    expect(_opacity(tester), 1);
    // Та же стрелка, развёрнутая на пол-оборота, — не вторая кнопка.
    expect(_turns(tester), 0.5);

    await tester.tap(_button);
    await tester.pumpAndSettle();

    expect(controller.offset, controller.position.minScrollExtent);
  });

  testWidgets('у самого конца кнопка остаётся — она уже ведёт наверх', (
    tester,
  ) async {
    final controller = await _pump(tester);

    await _scrollTo(tester, controller, controller.position.maxScrollExtent);

    // Раньше здесь кнопки не было вовсе: расстояние считалось до конца списка,
    // а он уже под ногами. Наверх при этом — весь список.
    expect(_opacity(tester), 1);
    expect(_turns(tester), 0.5);
  });

  testWidgets('когда обе цели близко, кнопки нет — докрутить проще', (
    tester,
  ) async {
    // 25 строк по 60 — прокрутки 900 при пороге 600: дальше середины до начала
    // 500, до конца 400, и целиться в кнопку дольше, чем свайпнуть.
    final controller = await _pump(tester, items: 25);

    await _scrollTo(tester, controller, 500);

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
