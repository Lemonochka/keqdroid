import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/app/app.dart';

ColorScheme _scheme(Brightness brightness) => ColorScheme.fromSeed(
      seedColor: const Color(0xFF6750A4),
      brightness: brightness,
    );

void main() {
  test('светлую схему не трогаем', () {
    final light = _scheme(Brightness.light);
    expect(applyAmoledBlack(light), same(light));
  });

  test('фон уходит в чистый чёрный', () {
    final amoled = applyAmoledBlack(_scheme(Brightness.dark));
    expect(amoled.surface, const Color(0xFF000000));
    expect(amoled.surfaceDim, const Color(0xFF000000));
  });

  test('карточки НЕ темнеют вслед за фоном', () {
    // Первая версия тянула к чёрному и лестницу тоже — карточки сливались с
    // фоном. Контраст карточки к фону обязан вырасти, а не упасть.
    final base = _scheme(Brightness.dark);
    final amoled = applyAmoledBlack(base);

    expect(amoled.surfaceContainerLow, base.surfaceContainerLow);
    expect(amoled.surfaceContainer, base.surfaceContainer);
    expect(amoled.surfaceContainerHigh, base.surfaceContainerHigh);
    expect(amoled.surfaceContainerHighest, base.surfaceContainerHighest);

    double gap(ColorScheme s) =>
        s.surfaceContainerHigh.computeLuminance() - s.surface.computeLuminance();
    expect(gap(amoled), greaterThan(gap(base)));
  });

  test('вставка внутри карточки не проваливается в фон', () {
    // AppTheme.inset — это surfaceContainerLowest. Если покрасить его чёрным,
    // вставки внутри карточек выглядят дырами до фона страницы.
    final amoled = applyAmoledBlack(_scheme(Brightness.dark));
    expect(amoled.surfaceContainerLowest, isNot(amoled.surface));
    expect(
      amoled.surfaceContainerLowest.computeLuminance(),
      greaterThan(amoled.surface.computeLuminance()),
    );
  });

  test('лестница поверхностей остаётся возрастающей по светлоте', () {
    final amoled = applyAmoledBlack(_scheme(Brightness.dark));
    final steps = [
      amoled.surface,
      amoled.surfaceContainerLowest,
      amoled.surfaceContainerLow,
      amoled.surfaceContainer,
      amoled.surfaceContainerHigh,
      amoled.surfaceContainerHighest,
    ].map((c) => c.computeLuminance()).toList();

    for (var i = 1; i < steps.length; i++) {
      expect(
        steps[i],
        greaterThan(steps[i - 1]),
        reason: 'ступень $i темнее предыдущей — иерархия перевёрнута',
      );
    }
  });

  test('содержательные цвета остаются нетронутыми', () {
    final base = _scheme(Brightness.dark);
    final amoled = applyAmoledBlack(base);
    expect(amoled.primary, base.primary);
    expect(amoled.onSurface, base.onSurface);
    expect(amoled.error, base.error);
  });
}
