import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/app/app.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + .05) / (lo + .05);
}

void main() {
  final preset = resolveThemePreset('pumpkin_night');

  test('«Тыква и ночь» есть в списке тем и разрешается сама в себя', () {
    expect(preset.id, 'pumpkin_night');
  });

  for (final brightness in Brightness.values) {
    group(brightness.name, () {
      final s = buildPresetScheme(preset, brightness);

      test('текст читается на фоне, кнопках и выбранном', () {
        // роли собраны вручную из двух семей, поэтому контраст сторожим явно:
        // ошибка в номере тона дала бы нечитаемый текст без единого падения
        for (final (fg, bg, what) in [
          (s.onSurface, s.surface, 'текст на фоне'),
          (
            s.onSurfaceVariant,
            s.surfaceContainerHigh,
            'второстепенный текст на карточке',
          ),
          (s.onPrimary, s.primary, 'текст на кнопке'),
          (s.onPrimaryContainer, s.primaryContainer, 'значок на кнопке «+»'),
          (s.onSecondaryContainer, s.secondaryContainer, 'текст выбранного'),
        ]) {
          expect(_contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: what);
        }
      });

      test('выбранное и фон фиолетовые — этим тема и отличается от Amber', () {
        // тыквенный сид сам по себе дал бы близнеца Amber, отличие держит фиолет
        for (final role in [s.secondaryContainer, s.surfaceContainerHigh]) {
          final hue = Hct.fromInt(role.toARGB32()).hue;
          expect(hue, inInclusiveRange(270, 320));
        }
      });
    });
  }
}
