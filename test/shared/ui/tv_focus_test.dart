import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/platform/platform_bootstrap.dart';
import 'package:keqdroid/shared/ui/tv_focus.dart';

// Фокус пульта на телевизоре: элемент заливается инверсным цветом темы и
// подрастает на 5%. Главное, что здесь стережётся: фокус не пропадает в
// момент, когда обёртка перекрашивает содержимое. Перестройка дерева на
// фокусе пересоздала бы элемент, и пульт терял бы его на каждом шаге.
void main() {
  tearDown(() => PlatformBootstrap.debugIsTelevisionOverride = null);

  const boxKey = Key('box');

  Future<FocusNode> pumpRow(WidgetTester tester, {bool nested = false}) async {
    Widget row = InkWell(
      onTap: () {},
      child: const SizedBox(key: boxKey, width: 100, height: 40),
    );
    if (nested) row = TvFocusHighlight(child: row);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: TvFocusHighlight(
              radius: BorderRadius.circular(16),
              child: row,
            ),
          ),
        ),
      ),
    );
    // Узел самого InkWell: фокус берёт он, обёртка только слушает.
    return Focus.of(tester.element(find.byKey(boxKey)));
  }

  // Пружина гаснет до порога покоя, а не до точного значения.
  Matcher width(double w) => moreOrLessEquals(w, epsilon: 0.01);

  ColorScheme schemeAt(WidgetTester tester) =>
      Theme.of(tester.element(find.byKey(boxKey))).colorScheme;

  Color? fillAt(WidgetTester tester) =>
      TvFocusHighlight.containerOf(tester.element(find.byKey(boxKey)));

  testWidgets('на телевизоре фокус заливает элемент и не теряется', (
    tester,
  ) async {
    PlatformBootstrap.debugIsTelevisionOverride = true;
    final node = await pumpRow(tester);
    final base = schemeAt(tester);

    node.requestFocus();
    await tester.pumpAndSettle();

    expect(node.hasPrimaryFocus, isTrue);
    expect(fillAt(tester), base.inverseSurface);
    expect(schemeAt(tester).onSurface, base.onInverseSurface);
    expect(
      tester.getRect(find.byKey(boxKey)).width,
      width(100 * TvFocus.focusedScale),
    );

    node.unfocus();
    await tester.pumpAndSettle();

    expect(fillAt(tester), isNull);
    expect(schemeAt(tester).onSurface, base.onSurface);
    expect(tester.getRect(find.byKey(boxKey)).width, width(100));
  });

  testWidgets('вложенная обёртка не поднимает элемент второй раз', (
    tester,
  ) async {
    PlatformBootstrap.debugIsTelevisionOverride = true;
    final node = await pumpRow(tester, nested: true);

    node.requestFocus();
    await tester.pumpAndSettle();

    expect(node.hasPrimaryFocus, isTrue);
    expect(
      tester.getRect(find.byKey(boxKey)).width,
      width(100 * TvFocus.focusedScale),
    );
  });

  testWidgets('на телефоне обёртка ничего не делает', (tester) async {
    PlatformBootstrap.debugIsTelevisionOverride = false;
    final node = await pumpRow(tester);

    node.requestFocus();
    await tester.pumpAndSettle();

    expect(node.hasPrimaryFocus, isTrue);
    expect(fillAt(tester), isNull);
    expect(tester.getRect(find.byKey(boxKey)).width, 100);
  });
}
