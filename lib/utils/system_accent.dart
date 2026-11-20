import 'dart:ui' show Color;

import 'package:material_color_utilities/material_color_utilities.dart';

// уезжает в лог: иначе жалобу на цвета системы не отличить от прошивки, которая отдаёт одну константу
enum SystemAccentSource {
  // Settings.Secure.theme_customization_overlay_packages, сид, из которого раскрашена система
  themeSetting,

  // пусто при живых обоях: onComputeColors() у них необязателен, а на китайских прошивках такие стоят из коробки
  wallpaper,

  // android.R.color.system_accent1_500; его перекрашивает ThemeOverlayController, а где OEM его не включил,
  // остаётся палитра AOSP
  systemResource,
}

class SystemAccentCandidates {
  const SystemAccentCandidates({
    this.themeSetting,
    this.wallpaper,
    this.systemResource,
  });

  const SystemAccentCandidates.empty()
    : themeSetting = null,
      wallpaper = null,
      systemResource = null;

  final int? themeSetting;
  final int? wallpaper;
  final int? systemResource;

  static SystemAccentCandidates fromMap(Map<Object?, Object?>? map) {
    if (map == null) return const SystemAccentCandidates.empty();
    int? at(String key) {
      final value = map[key];
      return value is int && value != 0 ? value : null;
    }

    return SystemAccentCandidates(
      themeSetting: at('themeSetting'),
      wallpaper: at('wallpaper'),
      systemResource: at('systemResource'),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SystemAccentCandidates &&
          themeSetting == other.themeSetting &&
          wallpaper == other.wallpaper &&
          systemResource == other.systemResource;

  @override
  int get hashCode => Object.hash(themeSetting, wallpaper, systemResource);
}

typedef SystemAccent = ({Color color, SystemAccentSource source});

// этим сидом AOSP заполняет палитру, когда извлекать не из чего (frameworks/base)
const aospFallbackSeed = 0xFF1B6EF3;

// считаем из сида тем же алгоритмом, что система: переписанная руками константа разошлась бы молча
final int aospDefaultAccent = () {
  final cam = Cam16.fromInt(aospFallbackSeed);
  return TonalPalette.of(cam.hue, cam.chroma).get(50);
}();

// допуск в один шаг на канал: прошивки расходятся на единицу округления
bool looksLikeAospDefault(int argb) {
  int channel(int value, int shift) => (value >> shift) & 0xFF;
  for (final shift in const [16, 8, 0]) {
    if ((channel(argb, shift) - channel(aospDefaultAccent, shift)).abs() > 1) {
      return false;
    }
  }
  return true;
}

// Порядок по тому, насколько источник знает выбор пользователя: настройка темы, обои, ресурс палитры. Ресурс берём
// только перекрашенный: константа AOSP в роли цвета системы и даёт жалобу у меня всегда один цвет
SystemAccent? pickSystemAccent(SystemAccentCandidates candidates) {
  final fromSetting = candidates.themeSetting;
  if (fromSetting != null) {
    return (color: Color(fromSetting), source: SystemAccentSource.themeSetting);
  }
  final fromWallpaper = candidates.wallpaper;
  if (fromWallpaper != null) {
    return (color: Color(fromWallpaper), source: SystemAccentSource.wallpaper);
  }
  final fromResource = candidates.systemResource;
  if (fromResource != null && !looksLikeAospDefault(fromResource)) {
    return (
      color: Color(fromResource),
      source: SystemAccentSource.systemResource,
    );
  }
  return null;
}
