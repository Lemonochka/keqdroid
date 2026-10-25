import 'dart:ui' as ui;

import 'package:flutter/material.dart';

// кривая прозрачности из двух отрезков Эрмита: значения и наклоны в точках 0, mid и 1
class FadeCurve {
  FadeCurve._(this.alphas, this.mid, this.slopes);

  // ровно стоит до start, потом мягко входит и мягко выходит
  factory FadeCurve.eased(double from, double to, {double start = 0}) =>
      FadeCurve._([from, from, to], start, const [0, 0, 0]);

  factory FadeCurve.linear(double from, double to) {
    final slope = to - from;
    return FadeCurve._([from, (from + to) / 2, to], 0.5, [slope, slope, slope]);
  }

  // начинает как прямая и гаснет к концу без излома
  factory FadeCurve.settle(double from, double to) =>
      FadeCurve._([from, to, to], 1, [to - from, 0, 0]);

  // через три точки, в средней без излома
  factory FadeCurve.through(List<double> alphas, double mid) {
    final left = (alphas[1] - alphas[0]) / mid;
    final right = (alphas[2] - alphas[1]) / (1 - mid);
    final middle = left.sign == right.sign ? (left + right) / 2 : 0.0;
    return FadeCurve._(alphas, mid, [left, middle, right]);
  }

  final List<double> alphas;
  final double mid;
  final List<double> slopes;

  double at(double t) {
    final s = slopes;
    if (t < mid) {
      return _hermite(t / mid, mid, alphas[0], alphas[1], s[0], s[1]);
    }
    final h = 1 - mid;
    if (h <= 0) return alphas[2];
    return _hermite((t - mid) / h, h, alphas[1], alphas[2], s[1], s[2]);
  }

  static double _hermite(
    double s,
    double h,
    double va,
    double vb,
    double ma,
    double mb,
  ) {
    final s2 = s * s;
    final s3 = s2 * s;
    return (2 * s3 - 3 * s2 + 1) * va +
        (s3 - 2 * s2 + s) * h * ma +
        (-2 * s3 + 3 * s2) * vb +
        (s3 - s2) * h * mb;
  }

  @override
  bool operator ==(Object other) =>
      other is FadeCurve &&
      other.mid == mid &&
      _listEquals(other.alphas, alphas) &&
      _listEquals(other.slopes, slopes);

  @override
  int get hashCode =>
      Object.hash(mid, Object.hashAll(alphas), Object.hashAll(slopes));

  static bool _listEquals(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// затухания считаются по пикселю с шумом в один пиксель: LinearGradient в 8 битах
// распадается на полосы тона, а на стыках отрезков глаз видит ступеньку
abstract final class SmoothFade {
  static ui.FragmentProgram? _fade;
  static ui.FragmentProgram? _edge;
  static Future<void>? _loading;

  static Future<void> load() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      _fade = await ui.FragmentProgram.fromAsset('shaders/smooth_fade.frag');
      _edge = await ui.FragmentProgram.fromAsset('shaders/edge_fade.frag');
    } catch (_) {}
  }

  static ui.FragmentShader? newFadeShader() => _fade?.fragmentShader();


  static Shader shader(
    ui.FragmentShader? program,
    Rect rect, {
    required Alignment begin,
    required Alignment end,
    required Color color,
    required FadeCurve curve,
    required double devicePixelRatio,
  }) {
    if (program == null) {
      const samples = 16;
      return LinearGradient(
        begin: begin,
        end: end,
        colors: [
          for (var i = 0; i <= samples; i++)
            color.withValues(alpha: curve.at(i / samples).clamp(0.0, 1.0)),
        ],
        stops: [for (var i = 0; i <= samples; i++) i / samples],
      ).createShader(rect);
    }
    final from = begin.withinRect(rect);
    final to = end.withinRect(rect);
    final slopes = curve.slopes;
    var i = 0;
    for (final v in [
      from.dx,
      from.dy,
      to.dx,
      to.dy,
      curve.mid,
      ...curve.alphas,
      ...slopes,
      color.r,
      color.g,
      color.b,
      devicePixelRatio,
    ]) {
      program.setFloat(i++, v);
    }
    return program;
  }
}

class SmoothFadeBox extends StatefulWidget {
  const SmoothFadeBox({
    super.key,
    required this.begin,
    required this.end,
    required this.color,
    required this.curve,
  });

  final AlignmentGeometry begin;
  final AlignmentGeometry end;
  final Color color;
  final FadeCurve curve;

  @override
  State<SmoothFadeBox> createState() => _SmoothFadeBoxState();
}

class _SmoothFadeBoxState extends State<SmoothFadeBox> {
  final ui.FragmentShader? _shader = SmoothFade.newFadeShader();

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    return CustomPaint(
      size: Size.infinite,
      painter: _SmoothFadePainter(
        shader: _shader,
        begin: widget.begin.resolve(direction),
        end: widget.end.resolve(direction),
        color: widget.color,
        curve: widget.curve,
        devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
      ),
    );
  }
}

class _SmoothFadePainter extends CustomPainter {
  _SmoothFadePainter({
    required this.shader,
    required this.begin,
    required this.end,
    required this.color,
    required this.curve,
    required this.devicePixelRatio,
  });

  final ui.FragmentShader? shader;
  final Alignment begin;
  final Alignment end;
  final Color color;
  final FadeCurve curve;
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = SmoothFade.shader(
          shader,
          rect,
          begin: begin,
          end: end,
          color: color,
          curve: curve,
          devicePixelRatio: devicePixelRatio,
        ),
    );
  }

  @override
  bool shouldRepaint(_SmoothFadePainter old) =>
      old.shader != shader ||
      old.begin != begin ||
      old.end != end ||
      old.color != color ||
      old.curve != curve ||
      old.devicePixelRatio != devicePixelRatio;
}

// края содержимого уходят в прозрачность: полоса цвета фона поверх читалась прямоугольником
class EdgeFadeMask extends StatefulWidget {
  const EdgeFadeMask({
    super.key,
    this.top = 0,
    this.bottom = 0,
    this.bottomHidden = 0,
    this.side = 0,
    this.topOutline,
    required this.child,
  });

  final double top;
  final double bottom;

  // полностью скрытая полоса под нижним затуханием
  final double bottomHidden;
  final double side;

  // что стоит над краем: затухание идёт по его контуру, а не прямой линией
  final EdgeFadeOutline? topOutline;
  final Widget child;

  @override
  State<EdgeFadeMask> createState() => _EdgeFadeMaskState();
}

class _EdgeFadeMaskState extends State<EdgeFadeMask> {
  final ui.FragmentShader? _shader = SmoothFade._edge?.fragmentShader();

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        final shader = _shader;
        if (shader != null) {
          var i = 0;
          for (final v in [
            widget.top,
            widget.bottom,
            widget.bottomHidden,
            widget.side,
            bounds.width,
            bounds.height,
            dpr,
            widget.topOutline?.inset ?? 0,
            widget.topOutline?.radius ?? 0,
            widget.topOutline?.gap ?? 0,
          ]) {
            shader.setFloat(i++, v);
          }
          return shader;
        }
        final h = bounds.height;
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Color(0x00000000),
            Color(0xFF000000),
            Color(0xFF000000),
            Color(0x00000000),
            Color(0x00000000),
          ],
          stops: [
            0,
            (widget.top / h).clamp(0.0, 1.0),
            ((h - widget.bottomHidden - widget.bottom) / h).clamp(0.0, 1.0),
            ((h - widget.bottomHidden) / h).clamp(0.0, 1.0),
            1,
          ],
        ).createShader(bounds);
      },
      // край маски на дробном пикселе Impeller сглаживает, и в половинке строки маска не
      // действует: со счётчиками под шапкой горела строка карточек. срез на 1 dp внутри
      child: ClipRect(
        clipper: EdgeFadeInset(
          EdgeInsets.fromLTRB(
            widget.side > 0 ? 1 : 0,
            widget.top > 0 ? 1 : 0,
            widget.side > 0 ? 1 : 0,
            widget.bottom > 0 || widget.bottomHidden > 0 ? 1 : 0,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

// карточка над краем: отступ от боков, скругление нижних углов, зазор до края
class EdgeFadeOutline {
  const EdgeFadeOutline({
    required this.inset,
    required this.radius,
    required this.gap,
  });

  final double inset;
  final double radius;
  final double gap;
}

@visibleForTesting
class EdgeFadeInset extends CustomClipper<Rect> {
  const EdgeFadeInset(this.inset);

  final EdgeInsets inset;

  @override
  Rect getClip(Size size) => inset.deflateRect(Offset.zero & size);

  @override
  bool shouldReclip(EdgeFadeInset oldClipper) => oldClipper.inset != inset;
}
