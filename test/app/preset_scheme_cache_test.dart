import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/app/app.dart';

/// Схемы пресетов обязаны считаться ОДИН раз на пару (пресет, яркость).
///
/// Это не микрооптимизация: экран выбора темы держит на себе все двенадцать
/// превью сразу, а `AnimatedTheme` внутри MaterialApp пересобирает поддерево на
/// каждом кадре перехода светлая↔тёмная. Без кеша двенадцать `fromSeed`
/// попадали на каждый такой кадр — 8 мс расчёта на десктопе, втрое больше на
/// телефоне, — и смена темы гарантированно роняла кадры.
void main() {
  test('одна и та же пара (пресет, яркость) отдаёт тот же объект', () {
    for (final preset in kThemePresets) {
      for (final brightness in Brightness.values) {
        expect(
          buildPresetScheme(preset, brightness),
          same(buildPresetScheme(preset, brightness)),
          reason: '${preset.id}/${brightness.name} пересчитывается заново',
        );
      }
    }
  });

  test('кеш не путает яркости и пресеты между собой', () {
    for (final preset in kThemePresets) {
      final light = buildPresetScheme(preset, Brightness.light);
      final dark = buildPresetScheme(preset, Brightness.dark);
      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
    }

    final ocean = buildPresetScheme(
      resolveThemePreset('ocean'),
      Brightness.dark,
    );
    final sunset = buildPresetScheme(
      resolveThemePreset('sunset'),
      Brightness.dark,
    );
    expect(ocean.primary, isNot(sunset.primary));
  });

  test('AMOLED не портит закешированную схему', () {
    // applyAmoledBlack возвращает копию — но если бы он правил оригинал,
    // почернел бы фон у всех, кто взял ту же схему из кеша.
    final preset = resolveThemePreset('ocean');
    final base = buildPresetScheme(preset, Brightness.dark);
    final surfaceBefore = base.surface;

    applyAmoledBlack(base);

    expect(buildPresetScheme(preset, Brightness.dark).surface, surfaceBefore);
  });
}
