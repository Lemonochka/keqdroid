import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/shared/ui/smooth_fade.dart';

double _slope(FadeCurve c, double t, {double d = 1e-4}) =>
    (c.at(t + d) - c.at(t - d)) / (2 * d);

void main() {
  group('кривая без изломов', () {
    test('мягкая: стоит до начала, входит и выходит с нулевым наклоном', () {
      final c = FadeCurve.eased(0, 1, start: 0.4);
      expect(c.at(0), 0);
      expect(c.at(0.3), 0);
      expect(c.at(1), closeTo(1, 1e-9));
      expect(_slope(c, 0.4 + 1e-3).abs(), lessThan(0.05));
      expect(_slope(c, 1 - 1e-3).abs(), lessThan(0.05));
      for (var t = 0.0; t < 1; t += 0.01) {
        expect(c.at(t + 0.01), greaterThanOrEqualTo(c.at(t) - 1e-9));
      }
    });

    test('через три точки: проходит через них, в средней без излома', () {
      for (final alphas in [
        [0.62, 0.38, 0.1],
        [0.9, 0.62, 0.22],
        [0.98, 0.86, 0.5],
      ]) {
        final c = FadeCurve.through(alphas, 0.45);
        expect(c.at(0), closeTo(alphas[0], 1e-9));
        expect(c.at(0.45), closeTo(alphas[1], 1e-9));
        expect(c.at(1), closeTo(alphas[2], 1e-9));
        // у ломаной наклоны слева и справа от средней точки разные
        expect(
          (_slope(c, 0.45 - 1e-3) - _slope(c, 0.45 + 1e-3)).abs(),
          lessThan(0.02),
        );
        for (var t = 0.0; t < 1; t += 0.01) {
          expect(c.at(t + 0.01), lessThanOrEqualTo(c.at(t) + 1e-9));
        }
      }
    });

    test('вода начинает как прямая и гаснет к низу без излома', () {
      final c = FadeCurve.settle(0.16, 0);
      expect(c.at(0), closeTo(0.16, 1e-9));
      expect(c.at(1), closeTo(0, 1e-9));
      expect(_slope(c, 1e-3), closeTo(-0.16, 0.01));
      expect(_slope(c, 1 - 1e-3).abs(), lessThan(0.01));
      for (var t = 0.0; t < 1; t += 0.01) {
        expect(c.at(t + 0.01), lessThanOrEqualTo(c.at(t) + 1e-9));
      }
    });

    test('линейная остаётся прямой', () {
      final c = FadeCurve.linear(0.16, 0);
      for (final t in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        expect(c.at(t), closeTo(0.16 * (1 - t), 1e-9));
      }
    });
  });

  testWidgets('шейдер смешивает цвет как обычная прозрачность', (tester) async {
    await tester.runAsync(SmoothFade.load);
    // без загруженного шейдера проверялся бы запасной градиент
    final probe = SmoothFade.newFadeShader();
    expect(probe, isNotNull);
    probe!.dispose();
    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: 100,
              height: 40,
              child: ColoredBox(
                color: Colors.black,
                child: SmoothFadeBox(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  color: Colors.white,
                  curve: FadeCurve.linear(0.5, 0.5),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!;
    });
    final mean = [
      for (var i = 0; i < bytes!.lengthInBytes; i += 4) bytes.getUint8(i),
    ].reduce((a, b) => a + b) /
        (bytes.lengthInBytes / 4);
    // белый с прозрачностью 0,5 на чёрном: около 128, а не 64 от двойного умножения
    expect(mean, closeTo(128, 4));
  });

  testWidgets('у затухающих краёв содержимое срезано на пиксель внутрь', (
    tester,
  ) async {
    // на телефоне край маски на дробном пикселе пропускал строку содержимого,
    // тестовый рендер этого не повторяет, поэтому проверяется сам срез
    Future<EdgeInsets> inset(EdgeFadeMask mask) async {
      await tester.pumpWidget(
        Directionality(textDirection: TextDirection.ltr, child: mask),
      );
      final clip = tester.widget<ClipRect>(
        find.descendant(
          of: find.byType(EdgeFadeMask),
          matching: find.byType(ClipRect),
        ),
      );
      return (clip.clipper! as EdgeFadeInset).inset;
    }

    const child = SizedBox.expand();
    expect(
      await inset(const EdgeFadeMask(top: 20, bottom: 28, child: child)),
      const EdgeInsets.fromLTRB(0, 1, 0, 1),
    );
    expect(
      await inset(const EdgeFadeMask(bottom: 28, child: child)),
      const EdgeInsets.fromLTRB(0, 0, 0, 1),
    );
    expect(
      await inset(const EdgeFadeMask(side: 40, child: child)),
      const EdgeInsets.fromLTRB(1, 0, 1, 0),
    );
  });
}
