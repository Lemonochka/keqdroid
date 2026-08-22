import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/subscription_card_theme.dart';
import 'package:keqdroid/services/subscription_accent_service.dart';

/// Серверы подписки перекрашиваются под её карточку. Проверяем ровно то, из-за
/// чего эта затея могла бы испортить экран: контраст, чужеродный цвет и
/// стоимость пересчёта.
void main() {
  ColorScheme schemeOf(Brightness brightness) => ColorScheme.fromSeed(
        seedColor: const Color(0xFF6750A4),
        brightness: brightness,
      );

  group('палитровая тема', () {
    test('акцент берётся из той же роли, что нарисована на карточке', () async {
      final scheme = schemeOf(Brightness.light);
      final accent = await SubscriptionAccentService.resolve(
        themeId: 'sunset',
        scheme: scheme,
      );

      expect(accent, isNotNull);
      // Sunset рисуется от primary — акцент группы обязан прийти оттуда же,
      // иначе карточка и её серверы разъедутся по цвету.
      expect(
        accent!.seed,
        CardPalette.sunset.colors(scheme).first.harmonizeWith(scheme.primary),
      );
    });

    test('тема «без подложки» акцента не даёт', () async {
      expect(
        await SubscriptionAccentService.resolve(
          themeId: '',
          scheme: schemeOf(Brightness.light),
        ),
        isNull,
      );
    });

    test('неизвестный id не роняет экран, а просто оставляет группу обычной',
        () async {
      expect(
        await SubscriptionAccentService.resolve(
          themeId: 'темы-больше-нет',
          scheme: schemeOf(Brightness.dark),
        ),
        isNull,
      );
    });
  });

  group('контраст', () {
    // Главный риск затеи: покрасить плитку «цветом с картинки» и утопить в нём
    // текст. Роли берутся из тональной схемы, поэтому пара обязана проходить
    // порог WCAG AA для крупного текста с большим запасом.
    test('текст на заливке активного сервера читается', () async {
      for (final brightness in Brightness.values) {
        final accent = await SubscriptionAccentService.resolve(
          themeId: 'ember',
          scheme: schemeOf(brightness),
        );
        final ratio = _contrast(accent!.onContainer, accent.container);
        expect(
          ratio,
          greaterThan(4.5),
          reason: 'контраст ${ratio.toStringAsFixed(2)} при $brightness',
        );
      }
    });

    // Подложка группы — намёк, а не заливка: перекрась она фон заметно, и
    // список групп рассыпался бы на разноцветные острова.
    test('подложка группы почти не уводит фон от темы', () async {
      final scheme = schemeOf(Brightness.dark);
      final accent = await SubscriptionAccentService.resolve(
        themeId: 'mint',
        scheme: scheme,
      );
      final base = scheme.surfaceContainerHigh;
      final tinted = accent!.surface(base);

      expect(tinted, isNot(base));
      expect(_contrast(tinted, base), lessThan(1.1));
    });

    test('рамка, наоборот, видна — на тонкой линии слабый тон пропадает',
        () async {
      final scheme = schemeOf(Brightness.light);
      final accent = await SubscriptionAccentService.resolve(
        themeId: 'aurora',
        scheme: scheme,
      );
      final base = scheme.outlineVariant;
      expect(accent!.outline(base), isNot(base));
      expect(SubscriptionAccent.outlineTint,
          greaterThan(SubscriptionAccent.surfaceTint));
    });
  });

  group('кэш', () {
    test('повторный запрос отдаёт тот же объект — без пересчёта', () async {
      final scheme = schemeOf(Brightness.light);
      final first = await SubscriptionAccentService.resolve(
        themeId: 'dusk',
        scheme: scheme,
      );
      expect(
        SubscriptionAccentService.cached(themeId: 'dusk', scheme: scheme),
        same(first),
      );
    });

    // Один ключ на обе яркости подсунул бы тёмные контейнеры светлой теме.
    test('светлая и тёмная тема кэшируются раздельно', () async {
      final light = await SubscriptionAccentService.resolve(
        themeId: 'dusk',
        scheme: schemeOf(Brightness.light),
      );
      final dark = await SubscriptionAccentService.resolve(
        themeId: 'dusk',
        scheme: schemeOf(Brightness.dark),
      );
      expect(light!.container, isNot(dark!.container));
    });

    test('до первого счёта кэш пуст — экран рисуется без ожидания', () {
      expect(
        SubscriptionAccentService.cached(
          themeId: 'ещё-не-считали',
          scheme: schemeOf(Brightness.light),
        ),
        isNull,
      );
    });
  });
}

/// Контраст по WCAG: (L1 + 0.05) / (L2 + 0.05).
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
