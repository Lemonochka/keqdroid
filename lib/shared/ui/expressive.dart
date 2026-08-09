/// Токены Material 3 Expressive.
///
/// Во Flutter 3.44 выразительного слоя нет вовсе: ни `MotionScheme`, ни shape
/// morph, ни emphasized-типографики, ни button groups. Поэтому токены заводим
/// сами — по структуре спеки, чтобы экраны перестали жить на произвольных
/// числах (`fontSize: 11.5`, `BorderRadius.circular(14)`), из-за которых
/// приложение и читается как «почти M3».
///
/// Пользоваться так: размеры текста брать из `Theme.of(context).textTheme`
/// (усиленные варианты — через [ExpressiveText]), радиусы — из [ExpressiveShape],
/// анимации — из [ExpressiveMotion].
library;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// Шкала форм M3 Expressive. В отличие от M3 здесь есть промежуточные шаги
/// (`largeIncreased`, `extraLargeIncreased`) и очень крупный `extraExtraLarge` —
/// именно они дают выразительную разницу между «карточкой» и «героем».
abstract final class ExpressiveShape {
  static const double none = 0;
  static const double extraSmall = 4;
  static const double small = 8;
  static const double medium = 12;
  static const double large = 16;
  static const double largeIncreased = 20;
  static const double extraLarge = 28;
  static const double extraLargeIncreased = 32;
  static const double extraExtraLarge = 48;

  /// Полное скругление (пилюля/круг) — у M3E это рабочая форма кнопок и
  /// индикаторов выбора, а не исключение.
  static const double full = 9999;

  static BorderRadius radius(double corner) =>
      BorderRadius.circular(corner == full ? 999 : corner);

  static RoundedRectangleBorder border(double corner) =>
      RoundedRectangleBorder(borderRadius: radius(corner));

  /// Форма для нажатого состояния: M3E морфит углы к более «сжатой» форме.
  /// Морфинг делаем интерполяцией между двумя ShapeBorder — Flutter умеет
  /// лерпить RoundedRectangleBorder, отдельный shape-morph API не нужен.
  static ShapeBorder pressedMorph(double corner, double t) =>
      ShapeBorder.lerp(border(corner), border(_pressedCorner(corner)), t)!;

  static double _pressedCorner(double corner) {
    if (corner >= extraExtraLarge) return extraLarge;
    if (corner >= extraLarge) return largeIncreased;
    if (corner >= large) return medium;
    return small;
  }
}

/// Пружинная схема движения M3 Expressive.
///
/// Две группы, как в спеке:
///  - **spatial** — всё, что двигается и меняет размер. Недодемпфированы
///    (`damping < 1`), поэтому дают лёгкий отскок — это и есть «выразительность»;
///  - **effects** — цвет, прозрачность, тень. Критически задемпфированы
///    (`damping = 1`), колебание яркости выглядело бы дефектом.
///
/// Значения подобраны по характеру ролей спеки (fast/default/slow), а не
/// скопированы из закрытых токенов — при желании крутятся здесь одним местом.
abstract final class ExpressiveMotion {
  static const spatialFast = SpringDescription(
    mass: 1,
    stiffness: 800,
    damping: 0.6 * 2 * 28.28, // ζ≈0.6 при stiffness 800
  );
  static const spatialDefault = SpringDescription(
    mass: 1,
    stiffness: 380,
    damping: 0.8 * 2 * 19.49,
  );
  static const spatialSlow = SpringDescription(
    mass: 1,
    stiffness: 200,
    damping: 0.8 * 2 * 14.14,
  );

  static const effectsFast = SpringDescription(
    mass: 1,
    stiffness: 3800,
    damping: 2 * 61.64, // ζ=1, без перелёта
  );
  static const effectsDefault = SpringDescription(
    mass: 1,
    stiffness: 1600,
    damping: 2 * 40.0,
  );
  static const effectsSlow = SpringDescription(
    mass: 1,
    stiffness: 800,
    damping: 2 * 28.28,
  );

  /// Длительности для мест, где пружину не применить (AnimatedContainer и
  /// прочие implicit-анимации). Подобраны под ощущение соответствующих пружин.
  static const durationFast = Duration(milliseconds: 200);
  static const durationDefault = Duration(milliseconds: 350);
  static const durationSlow = Duration(milliseconds: 500);

  /// Кривая-заменитель для implicit-анимаций: у M3 это emphasized easing —
  /// медленный старт, быстрый разгон, мягкая остановка.
  static const emphasized = Cubic(0.2, 0.0, 0.0, 1.0);
  static const emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1.0);
  static const emphasizedAccelerate = Cubic(0.3, 0.0, 0.8, 0.15);

  /// Гонит [controller] к [target] пружиной, а не по кривой.
  static TickerFuture springTo(
    AnimationController controller,
    double target, {
    SpringDescription spring = spatialDefault,
  }) =>
      controller.animateWith(
        SpringSimulation(spring, controller.value, target, 0),
      );
}

/// Типографика M3 Expressive: та же шкала ролей, что у M3, но с усиленными
/// весами — именно вес, а не размер, делает интерфейс «экспрессивным».
///
/// [emphasized] отдаёт усиленный вариант роли: у M3E он есть у каждой.
extension ExpressiveText on TextTheme {
  TextStyle? emphasized(TextStyle? style) => style?.copyWith(
        fontWeight: switch (style.fontWeight) {
          FontWeight.w400 || null => FontWeight.w500,
          FontWeight.w500 => FontWeight.w600,
          _ => FontWeight.w700,
        },
        letterSpacing: (style.letterSpacing ?? 0) - 0.1,
      );
}

/// Шкала M3 с выразительными весами. Размеры — стандартные роли M3, веса
/// подняты по духу Expressive (заголовки тяжелее, лейблы плотнее).
TextTheme buildExpressiveTextTheme(Brightness brightness) {
  const displayW = FontWeight.w400;
  const headlineW = FontWeight.w600;
  const titleW = FontWeight.w600;
  const labelW = FontWeight.w600;

  return const TextTheme(
    displayLarge: TextStyle(fontSize: 57, height: 64 / 57, letterSpacing: -0.25, fontWeight: displayW),
    displayMedium: TextStyle(fontSize: 45, height: 52 / 45, fontWeight: displayW),
    displaySmall: TextStyle(fontSize: 36, height: 44 / 36, fontWeight: displayW),
    headlineLarge: TextStyle(fontSize: 32, height: 40 / 32, fontWeight: headlineW),
    headlineMedium: TextStyle(fontSize: 28, height: 36 / 28, fontWeight: headlineW),
    headlineSmall: TextStyle(fontSize: 24, height: 32 / 24, fontWeight: headlineW),
    titleLarge: TextStyle(fontSize: 22, height: 28 / 22, fontWeight: titleW),
    titleMedium: TextStyle(fontSize: 16, height: 24 / 16, letterSpacing: 0.15, fontWeight: titleW),
    titleSmall: TextStyle(fontSize: 14, height: 20 / 14, letterSpacing: 0.1, fontWeight: titleW),
    bodyLarge: TextStyle(fontSize: 16, height: 24 / 16, letterSpacing: 0.5),
    bodyMedium: TextStyle(fontSize: 14, height: 20 / 14, letterSpacing: 0.25),
    bodySmall: TextStyle(fontSize: 12, height: 16 / 12, letterSpacing: 0.4),
    labelLarge: TextStyle(fontSize: 14, height: 20 / 14, letterSpacing: 0.1, fontWeight: labelW),
    labelMedium: TextStyle(fontSize: 12, height: 16 / 12, letterSpacing: 0.5, fontWeight: labelW),
    labelSmall: TextStyle(fontSize: 11, height: 16 / 11, letterSpacing: 0.5, fontWeight: labelW),
  );
}

/// Компонентные темы по шкале форм. Собраны отдельно, чтобы `buildAppTheme`
/// не превращался в простыню, а правки формы жили в одном месте.
({
  CardThemeData card,
  DialogThemeData dialog,
  BottomSheetThemeData sheet,
  SnackBarThemeData snackBar,
  ChipThemeData chip,
  FilledButtonThemeData filledButton,
  OutlinedButtonThemeData outlinedButton,
  TextButtonThemeData textButton,
  FloatingActionButtonThemeData fab,
  NavigationBarThemeData navigationBar,
  ListTileThemeData listTile,
}) buildExpressiveComponentThemes(ColorScheme scheme) {
  // Кнопки у M3E — пилюли: это самая заметная форма всего языка.
  final buttonShape = ExpressiveShape.border(ExpressiveShape.full);
  final buttonPadding = const EdgeInsets.symmetric(horizontal: 24, vertical: 16);

  return (
    card: CardThemeData(
      // Тональную подсветку не используем: иерархию в M3E несут уровни
      // surfaceContainer и форма, а не тень с оттенком.
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      color: scheme.surfaceContainerHigh,
      shape: ExpressiveShape.border(ExpressiveShape.large),
      margin: EdgeInsets.zero,
    ),
    dialog: DialogThemeData(
      surfaceTintColor: Colors.transparent,
      backgroundColor: scheme.surfaceContainerHigh,
      shape: ExpressiveShape.border(ExpressiveShape.extraLarge),
    ),
    sheet: BottomSheetThemeData(
      surfaceTintColor: Colors.transparent,
      backgroundColor: scheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ExpressiveShape.extraLarge),
        ),
      ),
    ),
    snackBar: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: ExpressiveShape.border(ExpressiveShape.medium),
    ),
    chip: ChipThemeData(
      shape: ExpressiveShape.border(ExpressiveShape.small),
      side: BorderSide(color: scheme.outlineVariant),
    ),
    filledButton: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: buttonShape,
        padding: buttonPadding,
        minimumSize: const Size(48, 48),
      ),
    ),
    outlinedButton: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: buttonShape,
        padding: buttonPadding,
        minimumSize: const Size(48, 48),
      ),
    ),
    textButton: TextButtonThemeData(
      style: TextButton.styleFrom(shape: buttonShape),
    ),
    fab: FloatingActionButtonThemeData(
      // У M3E FAB заметно менее круглый, чем у M2 — это узнаваемая деталь.
      shape: ExpressiveShape.border(ExpressiveShape.large),
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
    ),
    navigationBar: NavigationBarThemeData(
      surfaceTintColor: Colors.transparent,
      backgroundColor: scheme.surfaceContainer,
      elevation: 0,
      // Индикатор выбранного пункта — пилюля под иконкой (анатомия M3).
      indicatorShape: ExpressiveShape.border(ExpressiveShape.full),
      indicatorColor: scheme.secondaryContainer,
      labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
    ),
    listTile: ListTileThemeData(
      shape: ExpressiveShape.border(ExpressiveShape.large),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
  );
}
