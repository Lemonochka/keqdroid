import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/shared/ui/expressive.dart';

/// Шкала обязана совпадать с `TypeScaleTokens` из androidx.compose.material3:
/// выразительность M3E живёт в дельте между базой и усиленным вариантом, и
/// если поднять базу, дельта схлопывается — экран снова читается «одним весом».
void main() {
  final scale = buildExpressiveTextTheme(Brightness.dark);

  group('база лёгкая', () {
    test('headline и titleLarge — Regular', () {
      expect(scale.headlineMedium!.fontWeight, FontWeight.w400);
      expect(scale.titleLarge!.fontWeight, FontWeight.w400);
    });

    test('title поменьше и label — Medium', () {
      expect(scale.titleMedium!.fontWeight, FontWeight.w500);
      expect(scale.titleSmall!.fontWeight, FontWeight.w500);
      expect(scale.labelLarge!.fontWeight, FontWeight.w500);
      expect(scale.labelSmall!.fontWeight, FontWeight.w500);
    });

    test('body — Regular', () {
      expect(scale.bodyLarge!.fontWeight, FontWeight.w400);
      expect(scale.bodySmall!.fontWeight, FontWeight.w400);
    });
  });

  group('emphasized поднимает на шаг', () {
    test('Regular → Medium', () {
      expect(scale.emphasized(scale.headlineMedium)!.fontWeight,
          FontWeight.w500);
      expect(scale.emphasized(scale.titleLarge)!.fontWeight, FontWeight.w500);
      expect(scale.emphasized(scale.bodyLarge)!.fontWeight, FontWeight.w500);
    });

    test('Medium → Bold', () {
      expect(scale.emphasized(scale.titleMedium)!.fontWeight, FontWeight.w700);
      expect(scale.emphasized(scale.titleSmall)!.fontWeight, FontWeight.w700);
      expect(scale.emphasized(scale.labelLarge)!.fontWeight, FontWeight.w700);
    });

    test('null не ломает вызов', () {
      expect(scale.emphasized(null), isNull);
    });
  });

  // Трекинг меняют только три роли; паттерны в switch сравнивают int-константу
  // с `double? fontSize`, поэтому проверяем, что совпадение вообще срабатывает.
  group('трекинг усиленных вариантов', () {
    test('displayLarge −0.2 → 0', () {
      expect(scale.displayLarge!.letterSpacing, -0.2);
      expect(scale.emphasized(scale.displayLarge)!.letterSpacing, 0);
    });

    test('оба 16sp → 0.15', () {
      expect(scale.emphasized(scale.titleMedium)!.letterSpacing, 0.15);
      expect(scale.emphasized(scale.bodyLarge)!.letterSpacing, 0.15);
    });

    test('bodyMedium 0.2 → 0.25', () {
      expect(scale.emphasized(scale.bodyMedium)!.letterSpacing, 0.25);
    });

    test('14sp Medium свой трекинг сохраняет', () {
      expect(scale.emphasized(scale.titleSmall)!.letterSpacing, 0.1);
      expect(scale.emphasized(scale.labelLarge)!.letterSpacing, 0.1);
    });
  });
}
