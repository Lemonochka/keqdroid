import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import '../models/subscription_card_theme.dart';

/// Цвета подписки, выведенные из её карточки, — чтобы серверы этой подписки
/// узнавались по виду, а не только по заголовку группы.
///
/// Схема, а не один цвет: раскрашивать плитку «цветом с картинки» напрямую
/// нельзя — под произвольным тоном текст либо тонет, либо жжёт глаза. M3
/// решает это тональными палитрами, поэтому из сида собирается обычная
/// [ColorScheme], и дальше берутся её РОЛИ (`secondaryContainer` и парный к
/// нему `onSecondaryContainer`), у которых контраст уже выверен.
class SubscriptionAccent {
  const SubscriptionAccent({required this.seed, required this.scheme});

  /// Опорный цвет: доминанта картинки либо цвет роли у палитровой темы. Уже
  /// гармонизирован с темой приложения.
  final Color seed;

  /// Тональная схема, построенная из [seed] в яркости приложения.
  final ColorScheme scheme;

  /// Заливка поднятого (активного) сервера.
  Color get container => scheme.secondaryContainer;

  /// Текст и иконки на [container].
  Color get onContainer => scheme.onSecondaryContainer;

  /// Насколько сильно акцент проступает на фоне группы.
  ///
  /// Три процента — намеренно на грани заметности: подложка должна намекать на
  /// родство с карточкой подписки, а не спорить с ней. Всё, что выше, начинает
  /// читаться как «другая тема приложения», и список групп рассыпается на
  /// разноцветные острова вместо одной поверхности с оттенками.
  static const surfaceTint = 0.03;

  /// Обводка группы: тот же приём, но заметнее — линия тонкая, на ней слабый
  /// оттенок не виден вовсе.
  static const outlineTint = 0.35;

  /// Фон группы серверов этой подписки.
  Color surface(Color base) =>
      Color.alphaBlend(seed.withValues(alpha: surfaceTint), base);

  /// Рамка группы.
  Color outline(Color base) =>
      Color.alphaBlend(seed.withValues(alpha: outlineTint), base);
}

/// Достаёт [SubscriptionAccent] из темы карточки подписки.
///
/// Извлечение из картинки — дорогая операция (квантование пикселей), поэтому
/// результат кэшируется: список серверов перестраивается на каждый пинг, и
/// пересчитывать доминанту обоев на каждом кадре немыслимо.
class SubscriptionAccentService {
  SubscriptionAccentService._();

  /// Ключ учитывает не только тему карточки, но и яркость с `primary`
  /// приложения: одна и та же картинка даёт РАЗНЫЕ схемы в светлой и тёмной
  /// теме, а гармонизация привязана к `primary`. Общий ключ подсунул бы тёмные
  /// контейнеры на светлой теме и акцент, сдвинутый к прошлой теме, — после
  /// смены обоев на динамической теме это выглядело бы как застрявший цвет.
  static final Map<String, SubscriptionAccent?> _cache = {};

  /// Кэш живёт всё время работы приложения, а ключей у него столько же,
  /// сколько (картинок × перебранных тем). Перебор тем в настройках — обычное
  /// дело, поэтому старые записи вытесняем.
  static const _cacheLimit = 64;

  static String _key(String themeId, Brightness brightness, Color primary) =>
      '$themeId|${brightness.name}|${primary.toARGB32()}';

  /// Готовый акцент, если он уже посчитан. Синхронный: список серверов
  /// рисуется без ожидания, а первый кадр после запуска просто останется без
  /// подсветки — до того, как [resolve] досчитает.
  static SubscriptionAccent? cached({
    required String themeId,
    required ColorScheme scheme,
  }) =>
      _cache[_key(themeId, scheme.brightness, scheme.primary)];

  /// Считает акцент и кладёт в кэш. Возвращает null, когда выводить его не из
  /// чего: тема «без подложки», картинка удалена, файл не читается.
  static Future<SubscriptionAccent?> resolve({
    required String themeId,
    required ColorScheme scheme,
  }) async {
    final key = _key(themeId, scheme.brightness, scheme.primary);
    if (_cache.containsKey(key)) return _cache[key];

    final accent = await _compute(themeId, scheme);
    _cache[key] = accent;
    while (_cache.length > _cacheLimit) {
      _cache.remove(_cache.keys.first);
    }
    return accent;
  }

  static Future<SubscriptionAccent?> _compute(
    String themeId,
    ColorScheme scheme,
  ) async {
    final theme = resolveCardTheme(themeId);
    if (theme.isPlain) return null;

    final seed = await _seed(theme, scheme);
    if (seed == null) return null;

    // Гармонизация обязательна, а не «для красоты»: сид приходит с чужой
    // картинки и о теме приложения не знает ничего. Без сдвига к `primary`
    // ярко-розовая обложка на зелёной теме превращает свою группу в чужое
    // приложение внутри списка. Тот же приём, что у AppTheme.harmonize для
    // цветов протоколов.
    final harmonized = seed.harmonizeWith(scheme.primary);

    return SubscriptionAccent(
      seed: harmonized,
      scheme: ColorScheme.fromSeed(
        seedColor: harmonized,
        brightness: scheme.brightness,
      ),
    );
  }

  static Future<Color?> _seed(
    SubscriptionCardTheme theme,
    ColorScheme scheme,
  ) async {
    // Палитровая тема уже описана ролями текущей схемы — доминанту искать не
    // надо и нельзя: она бы разошлась с тем, что нарисовано на карточке.
    final palette = theme.palette;
    if (palette != null) return palette.colors(scheme).first;

    final asset = theme.asset;
    if (asset == null) return null;

    try {
      // Штатный извлекатель Flutter: внутри тот же квантователь, которым
      // Material You выводит тему из обоев, — значит и результат совпадает с
      // ожиданиями от системы, а не с самодельным «средним цветом», который
      // на любой пёстрой картинке даёт серо-бурый.
      final fromImage = await ColorScheme.fromImageProvider(
        provider: theme.id.startsWith(SubscriptionCardTheme.filePrefix)
            ? FileImage(File(asset)) as ImageProvider
            : AssetImage(asset),
        brightness: scheme.brightness,
      );
      return fromImage.primary;
    } catch (_) {
      // Картинку выкинули из сборки, файл удалили, декодер не справился —
      // группа остаётся обычной. Ровно как сама карточка в этом случае.
      return null;
    }
  }
}
