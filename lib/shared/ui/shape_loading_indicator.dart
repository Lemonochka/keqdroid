import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'shape_morph.dart';

/// Индикатор загрузки M3 Expressive: фигура пружиной перещёлкивается в
/// следующую, доворачиваясь на четверть оборота, поверх непрерывного вращения.
///
/// Вся механика (числа, пружина, последовательность фигур) живёт в
/// [ShapeMorphCycle] — тем же циклом морфится фигура внутри кнопки подключения.
///
/// Показывает только факт работы, без прогресса: доля выполненного здесь не
/// выражается никак.
class ShapeLoadingIndicator extends StatefulWidget {
  const ShapeLoadingIndicator({
    super.key,
    this.size = containerSize,
    this.color,
  });

  /// Сторона контейнера. Сама фигура занимает [activeScale] от неё.
  ///
  /// Спека допускает от 24 до 240 — размер выбирается по месту, 48 это
  /// значение по умолчанию.
  static const double containerSize = 48;

  /// Размер фигуры внутри контейнера у androidx: 38 из 48.
  ///
  /// Это не отступ ради красоты. Фигуры нормализованы по своему
  /// ограничивающему прямоугольнику, а мы их вращаем — вытянутые (`pill`,
  /// `oval`) на 45° вылезают за исходный квадрат углами и обрезались бы краем
  /// виджета.
  static const double activeScale = 38 / 48;

  final double size;

  /// По умолчанию — акцент темы, как у остальных индикаторов приложения.
  final Color? color;

  @override
  State<ShapeLoadingIndicator> createState() => _ShapeLoadingIndicatorState();
}

class _ShapeLoadingIndicatorState extends State<ShapeLoadingIndicator>
    with TickerProviderStateMixin {
  late final ShapeMorphCycle _cycle = ShapeMorphCycle(vsync: this);

  @override
  void dispose() {
    _cycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AppTheme.accent(context);
    return SizedBox.square(
      dimension: widget.size,
      // Перерисовка идёт каждый кадр — boundary не даёт ей тянуть за собой
      // содержимое вокруг (индикатор почти всегда стоит внутри списка).
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _cycle,
          builder: (context, _) => CustomPaint(
            painter: MorphPainter(
              morph: _cycle.morph,
              progress: _cycle.progress,
              degrees: _cycle.degrees,
              scale: ShapeLoadingIndicator.activeScale,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}
