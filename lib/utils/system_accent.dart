import 'dart:ui' show Color;

import 'package:material_color_utilities/material_color_utilities.dart';

/// Откуда взялся цвет системной темы. Уезжает в лог: жалоба «приложение не
/// следует цветам системы» без этого неотличима от «следует, но прошивка
/// отдаёт одну и ту же константу».
enum SystemAccentSource {
  /// `Settings.Secure.theme_customization_overlay_packages` — то, что выбрано
  /// в системных настройках темы. Самый прямой источник: не «похожий цвет», а
  /// ровно тот сид, из которого систему и раскрасили.
  themeSetting,

  /// Доминанта системных обоев. Работает на любой прошивке, но пусто при живых
  /// обоях: они не обязаны реализовывать `onComputeColors()`, а на китайских
  /// прошивках такие обои стоят из коробки.
  wallpaper,

  /// Ресурс `android.R.color.system_accent1_500`. Есть на любом API 31+, но
  /// перекрашивает его системный ThemeOverlayController — там, где OEM его не
  /// включил, остаётся палитра AOSP, см. [aospDefaultAccent].
  systemResource,
}

/// Что нативная сторона смогла добыть. Любое поле может быть пустым — это не
/// ошибка, а обычное состояние конкретной прошивки.
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

/// Выбранный сид и то, откуда он.
typedef SystemAccent = ({Color color, SystemAccentSource source});

/// Сид, которым AOSP заполняет палитру, когда извлекать не из чего
/// (`frameworks/base`, «If none of the provided colors meet the source color
/// requirement, the single source color should use the value 0xFF1B6EF3»).
const aospFallbackSeed = 0xFF1B6EF3;

/// Значение `system_accent1_500` на прошивке, где палитру никто не
/// перекрашивал.
///
/// Считаем, а не зашиваем: тон 50 выводится из сида ровно тем же алгоритмом,
/// которым его выводит система, и переписанная константа разошлась бы с
/// реальностью молча.
final int aospDefaultAccent = () {
  final cam = Cam16.fromInt(aospFallbackSeed);
  return TonalPalette.of(cam.hue, cam.chroma).get(50);
}();

/// Совпадает ли цвет с непеpекрашенной палитрой AOSP.
///
/// Допуск в один шаг на канал: у разных прошивок генерация тона может
/// разойтись на единицу округления, и точное сравнение пропустило бы дефолт
/// как «настоящий системный цвет».
bool looksLikeAospDefault(int argb) {
  int channel(int value, int shift) => (value >> shift) & 0xFF;
  for (final shift in const [16, 8, 0]) {
    if ((channel(argb, shift) - channel(aospDefaultAccent, shift)).abs() > 1) {
      return false;
    }
  }
  return true;
}

/// Какой из добытых цветов брать сидом темы.
///
/// Порядок не случаен и держится на том, насколько источник ЗНАЕТ, чего хотел
/// пользователь:
///
///  1. настройка темы — это его прямой выбор;
///  2. обои — то, из чего систему раскрасила бы сама;
///  3. ресурс палитры — уже вывод системы, и только если он вообще
///     перекрашен: непеpекрашенный отдаёт константу AOSP, а константа в роли
///     «цвета системы» и есть та самая жалоба «у меня всегда один цвет».
///
/// null — брать нечего, вызывающий останется на фирменном сиде.
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
