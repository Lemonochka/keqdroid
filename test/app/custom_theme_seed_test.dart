import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/app/app.dart';
import 'package:keqdroid/models/app_settings.dart';

/// Своя тема: цвет приходит строкой из настроек, из резервной копии и из чужих
/// рук, а на выходе обязан быть палитрой — либо своей, либо честным дефолтом.
void main() {
  group('разбор цвета', () {
    test('шесть цифр, с решёткой и без, в любом регистре', () {
      const violet = Color(0xFF7B2CBF);
      expect(parseThemeSeed('7B2CBF'), violet);
      expect(parseThemeSeed('#7b2cbf'), violet);
      expect(parseThemeSeed('  7B2CBF  '), violet);
    });

    test('восемь цифр принимаются, но непрозрачность своя', () {
      // Полупрозрачный сид дал бы палитру с прозрачными ролями — фон сквозь
      // кнопки. Альфу навязываем, а не доверяем строке.
      expect(parseThemeSeed('007B2CBF'), const Color(0xFF7B2CBF));
    });

    test('не цвет — это null, а не чёрный', () {
      // Чёрный на месте ошибки разбора выглядел бы как «выбрал цвет, получил
      // монохром», а не как «строка не подошла».
      expect(parseThemeSeed(''), isNull);
      expect(parseThemeSeed('7B2CB'), isNull);
      expect(parseThemeSeed('качели'), isNull);
      expect(parseThemeSeed('#ZZZZZZ'), isNull);
    });

    test('туда и обратно без потерь', () {
      const hex = '2EC4B6';
      expect(formatThemeSeed(parseThemeSeed(hex)!), hex);
    });
  });

  group('выбор темы', () {
    test('свой цвет применяется', () {
      final preset = themePresetFor(const AppSettings(
        themePresetId: kCustomThemePresetId,
        customThemeSeed: '2EC4B6',
      ));
      expect(preset.seed, const Color(0xFF2EC4B6));
    });

    test('пустой или испорченный цвет не роняет на чужой пресет', () {
      for (final broken in ['', 'нет']) {
        final preset = themePresetFor(AppSettings(
          themePresetId: kCustomThemePresetId,
          customThemeSeed: broken,
        ));
        expect(preset.seed, kCustomThemeDefaultSeed);
        expect(preset.id, startsWith(kCustomThemePresetId));
      }
    });

    test('готовые пресеты своей темой не задеты', () {
      expect(
        themePresetFor(const AppSettings(themePresetId: 'sunset')).id,
        'sunset',
      );
      // Цвет своей темы хранится всегда, в том числе пока выбран готовый
      // пресет: человек возвращается к своему оттенку, а не набирает заново.
      expect(
        themePresetFor(const AppSettings(
          themePresetId: 'sunset',
          customThemeSeed: '2EC4B6',
        )).id,
        'sunset',
      );
    });
  });

  test('смена своего цвета меняет палитру, а не отдаёт прежнюю из кеша', () {
    // Схемы кешируются по id пресета, и у всех своих тем он был бы один и тот
    // же — первый выбранный цвет остался бы в кеше навсегда.
    final mint = buildPresetScheme(
      themePresetFor(const AppSettings(
        themePresetId: kCustomThemePresetId,
        customThemeSeed: '2EC4B6',
      )),
      Brightness.dark,
    );
    final violet = buildPresetScheme(
      themePresetFor(const AppSettings(
        themePresetId: kCustomThemePresetId,
        customThemeSeed: '7B2CBF',
      )),
      Brightness.dark,
    );
    expect(mint.primary, isNot(violet.primary));
  });

  group('вариант палитры', () {
    test('имя варианта разбирается, мусор и пустое — спокойный tonalSpot', () {
      // Дефолт тот же, что был единственным вариантом до появления выбора: у
      // того, кто уже подобрал свой цвет, палитра от обновления не поедет.
      expect(parseThemeVariant(''), DynamicSchemeVariant.tonalSpot);
      expect(parseThemeVariant('нет такого'), DynamicSchemeVariant.tonalSpot);
      expect(parseThemeVariant('tonalSpot'), DynamicSchemeVariant.tonalSpot);
      expect(parseThemeVariant('vibrant'), DynamicSchemeVariant.vibrant);
      expect(parseThemeVariant(' fidelity '), DynamicSchemeVariant.fidelity);
    });

    test('умолчание настроек — прежняя спокойная палитра', () {
      expect(
        themePresetFor(const AppSettings(themePresetId: kCustomThemePresetId))
            .variant,
        DynamicSchemeVariant.tonalSpot,
      );
    });

    test('выбранный вариант доезжает до пресета', () {
      expect(
        themePresetFor(const AppSettings(
          themePresetId: kCustomThemePresetId,
          customThemeSeed: '2EC4B6',
          customThemeVariant: 'fidelity',
        )).variant,
        DynamicSchemeVariant.fidelity,
      );
    });

    test('смена варианта меняет палитру, а не отдаёт прежнюю из кеша', () {
      // Тот же капкан, что и со сменой цвета: схемы кешируются по id пресета,
      // и без варианта в id первый выбранный так и остался бы в кеше.
      ColorScheme schemeFor(String variant) => buildPresetScheme(
            themePresetFor(AppSettings(
              themePresetId: kCustomThemePresetId,
              customThemeSeed: '2EC4B6',
              customThemeVariant: variant,
            )),
            Brightness.dark,
          );
      // Схемы целиком, а не одна роль: где именно расходятся варианты,
      // зависит от цвета и яркости. У бирюзы в тёмной, например,
      // `primaryContainer` у спокойной и яркой совпадает до байта, а `primary`
      // разъезжается на 141 из 765 по сумме каналов.
      final calm = schemeFor('tonalSpot');
      final vibrant = schemeFor('vibrant');
      final exact = schemeFor('fidelity');
      expect(calm, isNot(vibrant));
      expect(calm, isNot(exact));
      expect(vibrant, isNot(exact));
    });

    test('ползунки насыщенности и яркости живут только на «точной»', () {
      // Ради этого выбор и появился: на tonalSpot Материал приводит цвет к
      // своим тонам, и два ползунка из трёх не делали ничего.
      int distance(Color a, Color b) {
        int channel(Color c, int shift) => (c.toARGB32() >> shift) & 0xFF;
        return [16, 8, 0]
            .map((s) => (channel(a, s) - channel(b, s)).abs())
            .reduce((a, b) => a + b);
      }

      Color primaryFor(String variant, double saturation) => buildPresetScheme(
            themePresetFor(AppSettings(
              themePresetId: kCustomThemePresetId,
              customThemeSeed: formatThemeSeed(
                HSVColor.fromAHSV(1, 210, saturation, 0.9).toColor(),
              ),
              customThemeVariant: variant,
            )),
            Brightness.light,
          ).primary;

      final calm = distance(primaryFor('tonalSpot', 0.9),
          primaryFor('tonalSpot', 0.15));
      final exact = distance(primaryFor('fidelity', 0.9),
          primaryFor('fidelity', 0.15));
      // Числа из замера: 28 против 147 по сумме каналов (0..765).
      expect(calm, lessThan(40));
      expect(exact, greaterThan(100));
    });

    test('вариант переживает сохранение настроек', () {
      const settings = AppSettings(
        themePresetId: kCustomThemePresetId,
        customThemeSeed: '7B2CBF',
        customThemeVariant: 'fidelity',
      );
      expect(
        AppSettings.fromJson(settings.toJson()).customThemeVariant,
        'fidelity',
      );
      // Копия постарше варианта не знает — она открывается спокойной палитрой,
      // а не падает и не уезжает в чужую.
      final old = settings.toJson()..remove('customThemeVariant');
      expect(AppSettings.fromJson(old).customThemeVariant, 'tonalSpot');
    });
  });

  test('цвет переживает сохранение настроек', () {
    const settings = AppSettings(
      themePresetId: kCustomThemePresetId,
      customThemeSeed: '7B2CBF',
    );
    expect(
      AppSettings.fromJson(settings.toJson()).customThemeSeed,
      '7B2CBF',
    );
  });
}
