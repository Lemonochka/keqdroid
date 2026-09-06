import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import '../tetromino.dart';

/// Цвета игры.
///
/// Компромисс между двумя требованиями, которые тянут в разные стороны: фигуры
/// обязаны быть узнаваемыми по канону Guideline, а экран — жить в теме
/// приложения. Поэтому канонические цвета берутся как есть по оттенку, но
/// прогоняются через HCT и сажаются на тон, уместный текущей яркости темы.
/// Оттенок остаётся каноническим, светлота — темы.
///
/// Всё остальное (стакан, сетка, панели, текст) — обычные роли [ColorScheme].
class KeqtrisSkin {
  final ColorScheme scheme;
  final Map<Tetromino, Color> pieces;
  final Color well;
  final Color wellOutline;
  final Color gridLine;
  final Color ghost;

  const KeqtrisSkin({
    required this.scheme,
    required this.pieces,
    required this.well,
    required this.wellOutline,
    required this.gridLine,
    required this.ghost,
  });

  /// Канон Guideline. Ниже они пересаживаются на тон темы, но оттенок — отсюда.
  static const Map<Tetromino, int> canon = {
    Tetromino.i: 0xFF00F0F0,
    Tetromino.j: 0xFF0000F0,
    Tetromino.l: 0xFFF0A000,
    Tetromino.o: 0xFFF0F000,
    Tetromino.s: 0xFF00F000,
    Tetromino.t: 0xFFA000F0,
    Tetromino.z: 0xFFF00000,
  };

  /// Тон фигур в светлой теме: плотные блоки на светлом фоне.
  static const double _toneLight = 56;

  /// В тёмной — светлее фона, но не слепящие.
  static const double _toneDark = 72;

  factory KeqtrisSkin.fromScheme(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    final tone = dark ? _toneDark : _toneLight;
    return KeqtrisSkin(
      scheme: scheme,
      pieces: {
        for (final entry in canon.entries)
          entry.key: _retone(entry.value, tone),
      },
      well: scheme.surfaceContainerLowest,
      wellOutline: scheme.outlineVariant,
      // Сетка обязана быть на грани различимости: заметная превращает стакан в
      // таблицу и спорит с фигурами за внимание.
      gridLine: scheme.outlineVariant.withValues(alpha: dark ? 0.22 : 0.30),
      ghost: scheme.onSurfaceVariant.withValues(alpha: 0.30),
    );
  }

  factory KeqtrisSkin.of(BuildContext context) =>
      KeqtrisSkin.fromScheme(Theme.of(context).colorScheme);

  Color colorOf(Tetromino piece) => pieces[piece]!;

  static Color _retone(int canonColor, double tone) {
    final hct = Hct.fromInt(canonColor);
    hct.tone = tone;
    return Color(hct.toInt());
  }
}

/// Пружины M3 Expressive.
///
/// Числа продублированы из слоя токенов приложения, а не взяты импортом: пакет
/// не зависит от keqdroid и не должен. Дубль здесь честнее зависимости —
/// расходится он только если менять характер движения, а это делают осознанно.
abstract final class KeqtrisMotion {
  /// Spatial недодемпфирована и обязана перелетать за цель — в этом и есть
  /// «выразительность» M3E.
  static const spatialFast = SpringDescription(
    mass: 1,
    stiffness: 800,
    damping: 0.6 * 2 * 28.28,
  );

  /// Длительность вспышки на месте убранных строк.
  static const clearDuration = Duration(milliseconds: 260);

  /// Гонит [controller] к [target] пружиной.
  ///
  /// Контроллер обязан быть `AnimationController.unbounded`: обычный зажат в
  /// [0, 1] и срежет перелёт, ради которого пружину и берут.
  static TickerFuture springTo(
    AnimationController controller,
    double target, {
    SpringDescription spring = spatialFast,
  }) => controller.animateWith(
    SpringSimulation(spring, controller.value, target, 0),
  );
}
