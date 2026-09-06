import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqtris/keqtris.dart';

/// Относительная яркость по WCAG.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

/// Коэффициент контраста по WCAG: от 1 (неразличимо) до 21 (чёрное на белом).
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  // Пресеты тем приложения дают самые разные акценты, поэтому проверяем не один
  // цвет, а разброс — включая крайности вроде почти-чёрного и почти-белого сида.
  const seeds = [
    Color(0xFFB2BDFF),
    Color(0xFFFFB2BD),
    Color(0xFF00FF00),
    Color(0xFFFFFF00),
    Color(0xFF000000),
    Color(0xFFFFFFFF),
    Color(0xFF7B1FA2),
    Color(0xFF00695C),
  ];

  group('карточка конца партии читается', () {
    // Регрессия: первая версия писала текст ролью `onPrimary` прямо на
    // затемнении. В тёмной теме `onPrimary` сам тёмный — надпись «Партия
    // окончена» сливалась с фоном и её было почти не видно.
    //
    // Порог 4.5:1 — уровень AA по WCAG для обычного текста. Заголовок здесь
    // крупный и формально допускал бы 3:1, но запас в полтора раза дешевле
    // ещё одного круга «не видно».
    for (final seed in seeds) {
      for (final brightness in Brightness.values) {
        test('сид ${seed.toARGB32().toRadixString(16)} / ${brightness.name}', () {
          final skin = KeqtrisSkin.fromScheme(
            ColorScheme.fromSeed(seedColor: seed, brightness: brightness),
          );

          expect(
            _contrast(skin.onOverlay, skin.overlay),
            greaterThanOrEqualTo(4.5),
            reason: 'основной текст карточки',
          );
          expect(
            _contrast(skin.scheme.primary, skin.overlay),
            greaterThanOrEqualTo(4.5),
            reason: 'заголовок нового рекорда',
          );
        });
      }
    }
  });

  group('стакан отличим от фигур', () {
    for (final brightness in Brightness.values) {
      test('фигуры видны на подложке стакана / ${brightness.name}', () {
        final skin = KeqtrisSkin.fromScheme(
          ColorScheme.fromSeed(
            seedColor: const Color(0xFFB2BDFF),
            brightness: brightness,
          ),
        );
        for (final piece in Tetromino.values) {
          // Порог ниже: это не текст, а заливка, и различать её надо от
          // подложки, а не читать. Но совсем сливаться она не должна.
          expect(
            _contrast(skin.colorOf(piece), skin.well),
            greaterThanOrEqualTo(1.5),
            reason: '$piece на подложке',
          );
        }
      });
    }
  });
}
