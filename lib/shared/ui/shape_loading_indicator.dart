import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'on_screen.dart';
import 'shape_morph.dart';

class ShapeLoadingIndicator extends StatefulWidget {
  const ShapeLoadingIndicator({
    super.key,
    this.size = containerSize,
    this.color,
  });

  static const double containerSize = 48;

  // вытянутые фигуры на 45° вылезают углами за квадрат, отсюда 38 из 48
  static const double activeScale = 38 / 48;

  final double size;

  final Color? color;

  @override
  State<ShapeLoadingIndicator> createState() => _ShapeLoadingIndicatorState();
}

class _ShapeLoadingIndicatorState extends State<ShapeLoadingIndicator>
    with TickerProviderStateMixin {
  late final ShapeMorphCycle _cycle = ShapeMorphCycle(vsync: this);
  late final AppLifecycleListener _lifecycle;
  ValueListenable<TickerModeData>? _ticking;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: (_) => _sync());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ticking?.removeListener(_sync);
    _ticking = TickerMode.getValuesNotifier(context)..addListener(_sync);
    _sync();
  }

  void _sync() => _cycle.asleep = !onScreen(_ticking);

  @override
  void dispose() {
    _ticking?.removeListener(_sync);
    _lifecycle.dispose();
    _cycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AppTheme.accent(context);
    return SizedBox.square(
      dimension: widget.size,
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
