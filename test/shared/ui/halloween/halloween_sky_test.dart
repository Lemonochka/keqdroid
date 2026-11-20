import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/shared/ui/halloween/halloween_sky.dart';

Widget _sky(Brightness brightness) => MaterialApp(
  theme: ThemeData(brightness: brightness),
  home: const Center(
    child: HalloweenSky(child: SizedBox.square(dimension: 136)),
  ),
);

RawImage _image(WidgetTester tester) => tester.widget<RawImage>(
  find.descendant(
    of: find.byType(HalloweenSky),
    matching: find.byType(RawImage),
  ),
);

void main() {
  testWidgets(
    'небо выводится готовой картинкой, а не рисуется заново в каждом кадре тыквы',
    (tester) async {
      await tester.pumpWidget(_sky(Brightness.dark));
      expect(_image(tester).image, isNotNull);
    },
  );

  testWidgets('смена темы перерисовывает картинку, перерисовка тыквы нет', (
    tester,
  ) async {
    await tester.pumpWidget(_sky(Brightness.dark));
    final night = _image(tester).image;
    await tester.pumpWidget(_sky(Brightness.dark));
    expect(_image(tester).image, same(night));
    await tester.pumpWidget(_sky(Brightness.light));
    await tester.pumpAndSettle();
    expect(_image(tester).image, isNot(same(night)));
  });
}
