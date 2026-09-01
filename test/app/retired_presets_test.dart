import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/app/app.dart';

/// Forest, Ruby и Cobalt убраны как копии Mint, Sunset и Ocean: `tonalSpot`
/// строит палитру по тону сида, и на выходе у них были одни и те же роли.
///
/// Id удалённых пресетов остаются в сохранённых настройках и в резервных копиях
/// НАВСЕГДА, поэтому они обязаны и дальше разрешаться — в близнеца, а не в
/// дефолт: удаляли копию, и внешне у человека не должно измениться ничего.
void main() {
  const retired = {'forest': 'mint', 'ruby': 'sunset', 'cobalt': 'ocean'};

  test('удалённые пресеты уводят к своему близнецу, а не к дефолту', () {
    for (final entry in retired.entries) {
      final resolved = resolveThemePreset(entry.key);
      expect(
        resolved.id,
        entry.value,
        reason: '${entry.key} должен разрешаться в ${entry.value}',
      );
    }
  });

  test('замена выглядит так же, как удалённый пресет', () {
    // То самое, ради чего удаление вообще безопасно: у близнеца те же роли.
    const removedSeeds = {
      'mint': Color(0xFF2A9D8F), // сид прежнего Forest
      'sunset': Color(0xFFDC2F45), // сид прежнего Ruby
      'ocean': Color(0xFF4361EE), // сид прежнего Cobalt
    };

    for (final entry in removedSeeds.entries) {
      final survivor = buildPresetScheme(
        resolveThemePreset(entry.key),
        Brightness.dark,
      );
      final removed = ColorScheme.fromSeed(
        seedColor: entry.value,
        brightness: Brightness.dark,
      );
      // Разница по акцентным ролям — единицы из 255. У заведомо разных тем в
      // списке она больше десяти.
      double delta(Color a, Color b) =>
          ((a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs()) / 3 * 255;

      expect(delta(survivor.primary, removed.primary), lessThan(8));
      expect(
        delta(survivor.primaryContainer, removed.primaryContainer),
        lessThan(8),
      );
    }
  });

  test('неизвестный id по-прежнему падает в дефолт', () {
    expect(resolveThemePreset('нет-такого').id, kThemePresets.first.id);
  });

  test('живые пресеты не пересекаются с таблицей удалённых', () {
    for (final preset in kThemePresets) {
      expect(
        retired.containsKey(preset.id),
        isFalse,
        reason: '${preset.id} и удалён, и присутствует в списке',
      );
    }
  });
}
