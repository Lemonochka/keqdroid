// во Flutter 3.44 слоя M3 Expressive нет, токены свои
library;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

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

  static const double full = 9999;

  static const double _renderedFull = 999;

  static BorderRadius radius(double corner) =>
      BorderRadius.circular(corner == full ? _renderedFull : corner);

  static RoundedRectangleBorder border(double corner) =>
      RoundedRectangleBorder(borderRadius: radius(corner));

  static OutlineInputBorder inputBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: radius(extraSmall),
        borderSide: BorderSide(color: color, width: width),
      );

  static ShapeBorder pressedMorph(double corner, double t) =>
      ShapeBorder.lerp(border(corner), border(pressedCorner(corner)), t)!;

  static double pressedCorner(double corner) => switch (corner) {
        full => full,
        // пилюля приходит радиусом 999, морфить её нельзя: почти вся анимация круглая, в конце рывок
        >= _renderedFull => corner,
        >= extraLarge => largeIncreased,
        >= large => medium,
        >= small => extraSmall,
        _ => corner,
      };

  static BorderRadius pressedRadius(BorderRadius base) => BorderRadius.only(
        topLeft: Radius.circular(pressedCorner(base.topLeft.x)),
        topRight: Radius.circular(pressedCorner(base.topRight.x)),
        bottomLeft: Radius.circular(pressedCorner(base.bottomLeft.x)),
        bottomRight: Radius.circular(pressedCorner(base.bottomRight.x)),
      );
}

abstract final class ExpressiveSpacing {
  static const double none = 0;

  static const double hairline = 2;

  static const double extraSmall = 4;
  static const double small = 8;
  static const double medium = 12;
  static const double large = 16;
  static const double largeIncreased = 20;
  static const double extraLarge = 24;
  static const double extraLargeIncreased = 32;
  static const double extraExtraLarge = 48;
}

abstract final class ExpressiveIconSize {
  static const double inline = 16;

  static const double small = 18;

  static const double medium = 20;

  static const double large = 24;

  static const double extraLarge = 40;
}

enum ExpressiveAccent {
  primary,
  secondary,
  tertiary;

  static ExpressiveAccent cycle(int index) =>
      values[index % values.length];

  Color container(ColorScheme scheme) => switch (this) {
        ExpressiveAccent.primary => scheme.primaryContainer,
        ExpressiveAccent.secondary => scheme.secondaryContainer,
        ExpressiveAccent.tertiary => scheme.tertiaryContainer,
      };

  Color onContainer(ColorScheme scheme) => switch (this) {
        ExpressiveAccent.primary => scheme.onPrimaryContainer,
        ExpressiveAccent.secondary => scheme.onSecondaryContainer,
        ExpressiveAccent.tertiary => scheme.onTertiaryContainer,
      };
}

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

  static const durationFast = Duration(milliseconds: 200);
  static const durationDefault = Duration(milliseconds: 350);
  static const durationSlow = Duration(milliseconds: 500);

  static const emphasized = Cubic(0.2, 0.0, 0.0, 1.0);
  static const emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1.0);
  static const emphasizedAccelerate = Cubic(0.3, 0.0, 0.8, 0.15);

  static TickerFuture springTo(
    AnimationController controller,
    double target, {
    SpringDescription spring = spatialDefault,
    bool snapToEnd = false,
  }) =>
      controller.animateWith(
        SpringSimulation(
          spring,
          controller.value,
          target,
          0,
          snapToEnd: snapToEnd,
        ),
      );
}

extension ExpressiveText on TextTheme {
  TextStyle? emphasized(TextStyle? style) => style?.copyWith(
        fontWeight: switch (style.fontWeight) {
          FontWeight.w400 || null => FontWeight.w500,
          _ => FontWeight.w700,
        },
        letterSpacing: switch ((style.fontSize, style.fontWeight)) {
          (57, _) => 0,
          (16, _) => 0.15,
          (14, FontWeight.w400 || null) => 0.25,
          _ => style.letterSpacing,
        },
      );
}

TextTheme buildExpressiveTextTheme(Brightness brightness) {
  const regular = FontWeight.w400;
  const medium = FontWeight.w500;

  return const TextTheme(
    displayLarge: TextStyle(fontSize: 57, height: 64 / 57, letterSpacing: -0.2, fontWeight: regular),
    displayMedium: TextStyle(fontSize: 45, height: 52 / 45, letterSpacing: 0, fontWeight: regular),
    displaySmall: TextStyle(fontSize: 36, height: 44 / 36, letterSpacing: 0, fontWeight: regular),
    headlineLarge: TextStyle(fontSize: 32, height: 40 / 32, letterSpacing: 0, fontWeight: regular),
    headlineMedium: TextStyle(fontSize: 28, height: 36 / 28, letterSpacing: 0, fontWeight: regular),
    headlineSmall: TextStyle(fontSize: 24, height: 32 / 24, letterSpacing: 0, fontWeight: regular),
    titleLarge: TextStyle(fontSize: 22, height: 28 / 22, letterSpacing: 0, fontWeight: regular),
    titleMedium: TextStyle(fontSize: 16, height: 24 / 16, letterSpacing: 0.2, fontWeight: medium),
    titleSmall: TextStyle(fontSize: 14, height: 20 / 14, letterSpacing: 0.1, fontWeight: medium),
    bodyLarge: TextStyle(fontSize: 16, height: 24 / 16, letterSpacing: 0.5, fontWeight: regular),
    bodyMedium: TextStyle(fontSize: 14, height: 20 / 14, letterSpacing: 0.2, fontWeight: regular),
    bodySmall: TextStyle(fontSize: 12, height: 16 / 12, letterSpacing: 0.4, fontWeight: regular),
    labelLarge: TextStyle(fontSize: 14, height: 20 / 14, letterSpacing: 0.1, fontWeight: medium),
    labelMedium: TextStyle(fontSize: 12, height: 16 / 12, letterSpacing: 0.5, fontWeight: medium),
    labelSmall: TextStyle(fontSize: 11, height: 16 / 11, letterSpacing: 0.5, fontWeight: medium),
  );
}

({
  AppBarThemeData appBar,
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
  InputDecorationThemeData inputDecoration,
  PopupMenuThemeData popupMenu,
  SegmentedButtonThemeData segmentedButton,
  ProgressIndicatorThemeData progressIndicator,
  SliderThemeData slider,
}) buildExpressiveComponentThemes(ColorScheme scheme) {
  final buttonShape = ExpressiveShape.border(ExpressiveShape.full);
  final buttonPadding = const EdgeInsets.symmetric(horizontal: 24, vertical: 16);

  return (
    appBar: AppBarThemeData(
      backgroundColor: WidgetStateColor.resolveWith(
        (states) => states.contains(WidgetState.scrolledUnder)
            ? scheme.surfaceContainer
            : scheme.surface,
      ),
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(
        color: scheme.onSurface,
        size: ExpressiveIconSize.large,
      ),
      actionsIconTheme: IconThemeData(
        color: scheme.onSurfaceVariant,
        size: ExpressiveIconSize.large,
      ),
    ),
    card: CardThemeData(
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
      shape: ExpressiveShape.border(ExpressiveShape.largeIncreased),
      sizeConstraints: const BoxConstraints.tightFor(width: 68, height: 68),
      extendedSizeConstraints: const BoxConstraints.tightFor(height: 68),
      extendedPadding: const EdgeInsets.symmetric(horizontal: 24),
      extendedIconLabelSpacing: 12,
      iconSize: ExpressiveIconSize.large,
      elevation: 3,
      focusElevation: 3,
      hoverElevation: 4,
      highlightElevation: 3,
    ),
    navigationBar: NavigationBarThemeData(
      surfaceTintColor: Colors.transparent,
      backgroundColor: scheme.surfaceContainer,
      elevation: 0,
      indicatorShape: ExpressiveShape.border(ExpressiveShape.full),
      indicatorColor: scheme.secondaryContainer,
      labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
    ),
    listTile: ListTileThemeData(
      shape: ExpressiveShape.border(ExpressiveShape.large),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
    inputDecoration: InputDecorationThemeData(
      filled: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: ExpressiveShape.inputBorder(scheme.outline),
      enabledBorder: ExpressiveShape.inputBorder(scheme.outline),
      focusedBorder: ExpressiveShape.inputBorder(scheme.primary, width: 2),
      errorBorder: ExpressiveShape.inputBorder(scheme.error),
      focusedErrorBorder: ExpressiveShape.inputBorder(scheme.error, width: 2),
      disabledBorder: ExpressiveShape.inputBorder(
        scheme.onSurface.withValues(alpha: 0.12),
      ),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      helperStyle: TextStyle(color: scheme.onSurfaceVariant),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      floatingLabelStyle: TextStyle(color: scheme.primary),
      prefixIconColor: scheme.onSurfaceVariant,
      suffixIconColor: scheme.onSurfaceVariant,
    ),
    segmentedButton: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        shape: buttonShape,
        side: BorderSide(color: scheme.outlineVariant),
        selectedBackgroundColor: scheme.secondaryContainer,
        selectedForegroundColor: scheme.onSecondaryContainer,
        foregroundColor: scheme.onSurfaceVariant,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    ),
    // флаг устаревший, но без него виджеты рисуются по спеке 2023
    // ignore: deprecated_member_use
    progressIndicator: const ProgressIndicatorThemeData(year2023: false),
    // ignore: deprecated_member_use
    slider: const SliderThemeData(year2023: false),
    popupMenu: PopupMenuThemeData(
      color: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shape: ExpressiveShape.border(ExpressiveShape.medium),
    ),
  );
}
