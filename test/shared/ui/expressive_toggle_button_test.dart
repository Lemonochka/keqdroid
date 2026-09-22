import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/shared/ui/expressive_toggle_button.dart';

/// Жалоба: морф у «Авто» выглядел так, будто края прыгают, достраивая
/// квадрат, а не меняется форма. Так и было — радиус ехал от 9999 к 8, и
/// видимая часть перехода сваливалась в последние проценты анимации.
Widget _host({required bool selected, VoidCallback? onPressed}) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            height: 40,
            width: 300,
            child: Align(
              alignment: Alignment.centerLeft,
              child: ExpressiveToggleButton(
                selected: selected,
                label: 'Auto',
                onPressed: onPressed ?? () {},
              ),
            ),
          ),
        ),
      ),
    );

double _corner(WidgetTester tester) {
  final material = tester.widget<Material>(
    find
        .descendant(
          of: find.byType(FilledButton),
          matching: find.byType(Material),
        )
        .first,
  );
  final shape = material.shape! as RoundedRectangleBorder;
  return shape.borderRadius.resolve(TextDirection.ltr).topLeft.x;
}

void main() {
  test('углы по спеке XS: пилюля, квадрат 12, нажатие 8', () {
    expect(ExpressiveToggleButton.cornerAt(selected: 0, pressed: 0), 16);
    expect(ExpressiveToggleButton.cornerAt(selected: 1, pressed: 0), 12);
    expect(ExpressiveToggleButton.cornerAt(selected: 0, pressed: 1), 8);
    expect(ExpressiveToggleButton.cornerAt(selected: 1, pressed: 1), 8);
  });

  testWidgets('форма меняется с первых кадров, а не рывком в конце', (
    tester,
  ) async {
    await tester.pumpWidget(_host(selected: false));
    expect(_corner(tester), 16);

    await tester.pumpWidget(_host(selected: true));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    final mid = _corner(tester);
    expect(mid, lessThan(15.5), reason: 'через два кадра уже не пилюля');
    expect(mid, greaterThan(12.5), reason: 'и ещё не квадрат');

    await tester.pumpAndSettle();
    expect(_corner(tester), closeTo(12, 0.01));
  });

  testWidgets('ширина одна в обоих состояниях', (tester) async {
    await tester.pumpWidget(_host(selected: false));
    final off = tester.getSize(find.byType(FilledButton));
    await tester.pumpWidget(_host(selected: true));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(FilledButton)), off);
  });

  testWidgets('кнопка 32dp, а палец ловится по всей высоте строки', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(_host(selected: false, onPressed: () => taps++));
    final visual = find
        .descendant(of: find.byType(FilledButton), matching: find.byType(Material))
        .first;
    final box = tester.getRect(visual);
    expect(box.height, ExpressiveToggleButton.height);

    // Два пикселя над нарисованной кнопкой — ещё её зона.
    await tester.tapAt(Offset(box.center.dx, box.top - 2));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('состояние слышно и читалке экрана', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(selected: true));
    expect(
      tester.getSemantics(find.byType(ExpressiveToggleButton)),
      isSemantics(isButton: true, isToggled: true, label: 'Auto'),
    );
    handle.dispose();
  });
}
