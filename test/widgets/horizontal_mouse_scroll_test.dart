import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/shared/ui/horizontal_mouse_scroll.dart';

/// Колесо над горизонтальной лентой внутри вертикальной страницы (выбор картинки подписки на ПК):
/// листало страницу вниз, а карусель с привязкой возвращалась к той же картинке.

Future<(ScrollController, CarouselController)> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(500, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final page = ScrollController();
  final carousel = CarouselController();
  addTearDown(page.dispose);
  addTearDown(carousel.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          controller: page,
          child: Column(
            children: [
              SizedBox(
                height: 160,
                child: HorizontalMouseScroll(
                  controller: carousel,
                  child: CarouselView.weighted(
                    controller: carousel,
                    flexWeights: const [3, 2, 1],
                    itemSnapping: true,
                    children: [for (var i = 0; i < 8; i++) Text('card $i')],
                  ),
                ),
              ),
              const SizedBox(height: 1600),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (page, carousel);
}

Future<void> _wheel(WidgetTester tester, Offset at, double dy) async {
  final mouse = TestPointer(1, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(mouse.hover(at));
  await tester.sendEventToBinding(mouse.scroll(Offset(0, dy)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('колесо над каруселью листает её по картинке, а не страницу', (tester) async {
    final (page, carousel) = await _pump(tester);
    final at = tester.getCenter(find.byType(CarouselView));
    await _wheel(tester, at, 50);
    expect(carousel.leadingItem, 1);
    expect(page.offset, 0);
    await _wheel(tester, at, 50);
    expect(carousel.leadingItem, 2);
    await _wheel(tester, at, -50);
    expect(carousel.leadingItem, 1);
    expect(page.offset, 0);
  });

  testWidgets('у начала карусели колесо вверх отдаётся странице', (tester) async {
    final (page, carousel) = await _pump(tester);
    page.jumpTo(40);
    await tester.pump();
    // карусель ещё на экране: 160 высотой, уехала вверх на 40
    await _wheel(tester, const Offset(250, 60), -50);
    expect(carousel.leadingItem, 0);
    expect(page.offset, lessThan(40));
  });

  testWidgets('колесо мимо карусели листает страницу', (tester) async {
    final (page, _) = await _pump(tester);
    await _wheel(tester, const Offset(250, 400), 120);
    expect(page.offset, greaterThan(0));
  });
}
