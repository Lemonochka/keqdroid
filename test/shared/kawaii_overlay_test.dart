import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/app/app.dart';
import 'package:keqdroid/shared/ui/kawaii_decorations.dart';

void main() {
  Widget host(KawaiiFlavor flavor, Brightness brightness) => MaterialApp(
        theme: ThemeData(brightness: brightness),
        darkTheme: ThemeData(brightness: Brightness.dark),
        themeMode: brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        home: KawaiiOverlay(flavor: flavor, child: const SizedBox.expand()),
      );

  testWidgets('overlay paints stickers and rain without exceptions', (tester) async {
    for (final flavor in [KawaiiFlavor.sakura, KawaiiFlavor.lavender]) {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(host(flavor, brightness));
        // Прогоняем анимацию по нескольким фазам цикла: все стикеры успевают
        // побывать на экране, вся path-математика исполняется.
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(seconds: 10));
          expect(tester.takeException(), isNull);
        }
      }
    }
    // Останавливаем бесконечный тикер перед завершением теста.
    await tester.pumpWidget(const SizedBox());
  });

  test('kawaii presets: sakura is single-tone pink, lavender exists', () {
    final sakura = resolveThemePreset('sakura_sky');
    expect(sakura.flair, isTrue);
    expect(sakura.kawaii, KawaiiFlavor.sakura);

    // Однотонность: primary и secondary из одного розового seed, без
    // подмешивания чужой (голубой) схемы.
    final light = buildPresetScheme(sakura, Brightness.light);
    final seedOnly = ColorScheme.fromSeed(
      seedColor: sakura.seed,
      brightness: Brightness.light,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    expect(light.primary, seedOnly.primary);
    expect(light.secondary, seedOnly.secondary);

    final lavender = resolveThemePreset('lavender_milk');
    expect(lavender.id, 'lavender_milk');
    expect(lavender.flair, isTrue);
    expect(lavender.kawaii, KawaiiFlavor.lavender);

    // Неизвестный id падает на дефолтный пресет.
    expect(resolveThemePreset('nope').id, kThemePresets.first.id);
  });
}
