import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import '../models/subscription_card_theme.dart';

class SubscriptionAccent {
  const SubscriptionAccent({required this.seed, required this.scheme});

  final Color seed;

  final ColorScheme scheme;

  Color get container => scheme.secondaryContainer;

  Color get onContainer => scheme.onSecondaryContainer;

  static const surfaceTint = 0.03;

  static const outlineTint = 0.35;

  Color surface(Color base) =>
      Color.alphaBlend(seed.withValues(alpha: surfaceTint), base);

  Color outline(Color base) =>
      Color.alphaBlend(seed.withValues(alpha: outlineTint), base);
}

class SubscriptionAccentService {
  SubscriptionAccentService._();

  // в ключе яркость и primary: одна картинка даёт разные схемы, а гармонизация привязана к primary
  static final Map<String, SubscriptionAccent?> _cache = {};

  static const _cacheLimit = 64;

  static String _key(String themeId, Brightness brightness, Color primary) =>
      '$themeId|${brightness.name}|${primary.toARGB32()}';

  static SubscriptionAccent? cached({
    required String themeId,
    required ColorScheme scheme,
  }) =>
      _cache[_key(themeId, scheme.brightness, scheme.primary)];

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
    final palette = theme.palette;
    if (palette != null) return palette.colors(scheme).first;

    final asset = theme.still;
    if (asset == null) return null;

    try {
      final fromImage = await ColorScheme.fromImageProvider(
        provider: theme.id.startsWith(SubscriptionCardTheme.filePrefix)
            ? SubscriptionCardTheme.coverImage(asset)
            : AssetImage(asset),
        brightness: scheme.brightness,
      );
      return fromImage.primary;
    } catch (_) {
      return null;
    }
  }
}
