import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/shared/ui/shape_morph.dart';

/// Жалоба звучала так: пингуешь пачку серверов, крутилки идут, прокручиваешь
/// список — и анимация будто начинается заново. Так и было: тайлы строятся
/// лениво, уехавший из кадра умирает вместе со своим циклом, а новый заводился
/// с первой фигуры и нулевого угла.
///
/// Время двигаем кадрами по 16 мс, а не одним прыжком: фаза считается от часов
/// планировщика, и они идут именно кадрами — как в живом приложении.
Future<void> _run(WidgetTester tester, Duration total) async {
  const frame = Duration(milliseconds: 16);
  for (var left = total; left > Duration.zero; left -= frame) {
    await tester.pump(frame);
  }
}

int _indexOf(ShapeMorphCycle cycle) =>
    ShapeMorphCycle.morphs.indexWhere((m) => identical(m, cycle.morph));

void main() {
  testWidgets('цикл, заведённый позже, идёт в фазе с уже работающим', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());

    final first = ShapeMorphCycle(vsync: const TestVSync());
    ShapeMorphCycle? later;
    try {
      // Полтора шага морфинга: старый цикл успевает уйти с той фигуры, на
      // которой начал, и разница между «продолжил» и «начал заново» видна.
      await _run(tester, const Duration(milliseconds: 975));

      later = ShapeMorphCycle(vsync: const TestVSync());
      expect(
        _indexOf(later),
        _indexOf(first),
        reason: 'фигура должна быть та же, что у соседей',
      );
      // Угол сходится с точностью до кадра оборота (360° за 4666 мс).
      expect(later.degrees % 360, closeTo(first.degrees % 360, 5));
    } finally {
      first.dispose();
      later?.dispose();
    }
  });

  testWidgets('шаги не разъезжаются со временем', (tester) async {
    await tester.pumpWidget(const SizedBox());

    final first = ShapeMorphCycle(vsync: const TestVSync());
    final second = ShapeMorphCycle(vsync: const TestVSync());
    try {
      // Десяток шагов: periodic-таймеры двух циклов за это время расходятся, и
      // если бы шаг считался инкрементом, фигуры разъехались бы.
      await _run(tester, const Duration(milliseconds: 6500));

      expect(_indexOf(second), _indexOf(first));
    } finally {
      first.dispose();
      second.dispose();
    }
  });
}
