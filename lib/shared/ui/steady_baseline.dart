import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

// Skia ставит строку текста ровно в пиксель экрана: пока подпись ползёт вместе с обложкой, она стояла и разом
// прыгала на 1 px, а на середине пикселя сотые доли перекидывали её туда и обратно. На ходу строка рисуется
// чуть наклонённой, тогда Skia ставит её с долей пикселя, а встав, она доезжает до целого
class SteadyBaseline extends StatefulWidget {
  const SteadyBaseline({super.key, required this.child});

  final Widget child;

  @override
  State<SteadyBaseline> createState() => _SteadyBaselineState();
}

class _SteadyBaselineState extends State<SteadyBaseline>
    with SingleTickerProviderStateMixin {
  @override
  Widget build(BuildContext context) => _SteadyBaselineBox(
    vsync: this,
    devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    child: widget.child,
  );
}

class _SteadyBaselineBox extends SingleChildRenderObjectWidget {
  const _SteadyBaselineBox({
    required this.vsync,
    required this.devicePixelRatio,
    required super.child,
  });

  final TickerProvider vsync;
  final double devicePixelRatio;

  @override
  RenderSteadyBaseline createRenderObject(BuildContext context) =>
      RenderSteadyBaseline(vsync, devicePixelRatio);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSteadyBaseline renderObject,
  ) => renderObject
    ..vsync = vsync
    ..devicePixelRatio = devicePixelRatio;
}

class RenderSteadyBaseline extends RenderProxyBox {
  RenderSteadyBaseline(this._vsync, this.devicePixelRatio);

  static const _rest = Duration(milliseconds: 50);
  static const _settle = Duration(milliseconds: 150);

  // меньше 1/4096 Skia считает нулём и снова ставит строку в пиксель
  static final _tilt = Matrix4.identity()..setEntry(1, 0, 1e-3);

  double devicePixelRatio;

  TickerProvider _vsync;
  set vsync(TickerProvider value) {
    if (identical(value, _vsync)) return;
    _vsync = value;
    final ticker = _ticker;
    if (ticker != null) {
      final active = ticker.isActive;
      ticker.dispose();
      _ticker = value.createTicker(_tick);
      if (active) _ticker!.start();
    }
  }

  Ticker? _ticker;

  // строка стоит в целом пикселе _row, пока настоящее место не ушло от _still
  double? _row;
  double _still = 0;

  // на ходу строка рисуется на _bias от настоящего места
  double _bias = 0;
  double? _last;
  Duration _moved = Duration.zero;
  double _dy = 0;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _ticker = _vsync.createTicker(_tick);
  }

  @override
  void detach() {
    _ticker?.dispose();
    _ticker = null;
    super.detach();
  }

  void _tick(Duration _) {
    if (_row != null) {
      _ticker?.stop();
      return;
    }
    if (SchedulerBinding.instance.currentFrameTimeStamp - _moved >= _rest) {
      markNeedsPaint();
    }
  }

  double _baselineOnScreen(RenderBox child) {
    final toRoot = getTransformTo(null);
    final base = child.getDistanceToBaseline(TextBaseline.alphabetic) ?? 0;
    // корень может уже умножать на масштаб экрана, может и нет
    return MatrixUtils.transformPoint(toRoot, Offset(0, base)).dy *
        devicePixelRatio /
        toRoot.getMaxScaleOnAxis();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    final y = _baselineOnScreen(child);
    final now = SchedulerBinding.instance.currentFrameTimeStamp;
    final last = _last ?? y;
    if (_last == null) {
      _row = y.roundToDouble();
      _still = y;
    }
    _last = y;

    final row = _row;
    if (row != null) {
      // сотые доли от встречных сдвигов строку не трогают
      if ((y - _still).abs() <= 0.02) {
        _dy = (row - y) / devicePixelRatio;
        context.paintChild(child, offset.translate(0, _dy));
        return;
      }
      _row = null;
      _bias = row - last;
    }

    final step = y - last;
    if (step.abs() > 1e-3) {
      // долю до целого пикселя строка гасит на ходу, по четверти сдвига
      _bias = _bias.sign * math.max(0, _bias.abs() - step.abs() / 4);
      _moved = now;
      if (!(_ticker?.isActive ?? true)) _ticker!.start();
    } else if (now - _moved >= _rest) {
      final t = ((now - _moved - _rest).inMicroseconds / _settle.inMicroseconds)
          .clamp(0.0, 1.0);
      final landing = (y + _bias).roundToDouble() - y;
      final bias = _bias + (landing - _bias) * Curves.easeInOut.transform(t);
      if (t >= 1) {
        _row = y + landing;
        _still = y;
        _bias = 0;
        _dy = landing / devicePixelRatio;
        context.paintChild(child, offset.translate(0, _dy));
        return;
      }
      _dy = bias / devicePixelRatio;
      context.pushTransform(
        needsCompositing,
        offset.translate(0, _dy),
        _tilt,
        _paintChild,
      );
      return;
    }
    _dy = _bias / devicePixelRatio;
    context.pushTransform(
      needsCompositing,
      offset.translate(0, _dy),
      _tilt,
      _paintChild,
    );
  }

  void _paintChild(PaintingContext context, Offset offset) =>
      context.paintChild(child!, offset);

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) =>
      transform.translateByDouble(0, _dy, 0, 1);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintOffset(
        offset: Offset(0, _dy),
        position: position,
        hitTest: (result, position) =>
            child?.hitTest(result, position: position) ?? false,
      );
}
