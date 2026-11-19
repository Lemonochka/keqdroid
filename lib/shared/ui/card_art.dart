import 'dart:math' as math;

import 'package:androidx_graphics_shapes/material_shapes.dart';
import 'package:androidx_graphics_shapes/shapes.dart';
import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

enum CardArt {
  halftone,
  depth,
  cookieLayers,
  cookieShift,
  shapePattern,
  shapeEdge,
  shapeAccent,
}

class CardArtPainter extends CustomPainter {
  const CardArtPainter(this.art, this.scheme, {this.rtl = false});

  final CardArt art;
  final ColorScheme scheme;

  // текст карточки с начала строки, в RTL он справа
  final bool rtl;

  bool get _dark => scheme.brightness == Brightness.dark;

  // полупрозрачный цвет темы на сером фоне карточки выходит серым, поэтому тот же оттенок плотнее и насыщеннее
  Color _tone(Color of, double chroma, double tone) {
    final hct = Hct.fromInt(of.toARGB32());
    return Color(Hct.from(hct.hue, chroma, tone).toInt());
  }

  Color _p(double darkTone, double lightTone, {required double chroma}) =>
      _tone(scheme.primary, chroma, _dark ? darkTone : lightTone);

  Color _t(double darkTone, double lightTone, {required double chroma}) =>
      _tone(scheme.tertiary, chroma, _dark ? darkTone : lightTone);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    if (rtl) {
      canvas
        ..translate(size.width, 0)
        ..scale(-1, 1);
    }
    switch (art) {
      case CardArt.halftone:
        _halftone(canvas, size);
      case CardArt.depth:
        _depth(canvas, size);
      case CardArt.cookieLayers:
        _cookieLayers(canvas, size);
      case CardArt.cookieShift:
        _cookieShift(canvas, size);
      case CardArt.shapePattern:
        _shapePattern(canvas, size);
      case CardArt.shapeEdge:
        _shapeEdge(canvas, size);
      case CardArt.shapeAccent:
        _shapeAccent(canvas, size);
    }
    canvas.restore();
  }

  // в боковой панели ПК подложка выше самой плашки (320), фигуры по высоте разрослись бы на всю панель
  double _unit(Size size) => math.min(size.height, size.width * 0.57);

  double _surface(
    double x, {
    required double base,
    required double amp,
    required double length,
    required double phase,
  }) {
    final swell = 1 + 0.15 * math.sin(2 * math.pi * x / 530 + phase * 0.7);
    return base - amp * swell * math.sin(2 * math.pi * x / length - phase);
  }

  Path _water(Size size, double Function(double x) surface) {
    final path = Path()..moveTo(0, surface(0));
    for (double x = 2; x < size.width; x += 2) {
      path.lineTo(x, surface(x));
    }
    return path
      ..lineTo(size.width, surface(size.width))
      ..lineTo(size.width, size.height + 2)
      ..lineTo(0, size.height + 2)
      ..close();
  }

  // RoundedPolygonBorder строит контур на каждый вызов, а узору их нужны десятки за кадр, пока карточка сворачивается
  static final Map<RoundedPolygon, Path> _unitPaths = {};

  Path _shape(
    RoundedPolygon polygon,
    double size, {
    required Offset at,
    double degrees = 0,
  }) {
    final unit = _unitPaths.putIfAbsent(
      polygon,
      () => RoundedPolygonBorder(polygon: polygon).getOuterPath(
        Rect.fromCenter(center: Offset.zero, width: 1, height: 1),
      ),
    );
    final m = Matrix4.identity()
      ..translateByDouble(at.dx, at.dy, 0, 1)
      ..rotateZ(degrees * math.pi / 180)
      ..scaleByDouble(size, size, 1, 1);
    return unit.transform(m.storage);
  }

  static Paint _fill(Color c) => Paint()..color = c;

  static Paint _stroke(Color c, double width) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeJoin = StrokeJoin.round
    ..color = c;

  // растр и узор лежат под одной волной и тают к тексту
  (double, double) _under(double x, double y, Size size) {
    final surface =
        _surface(x, base: size.height * 0.36, amp: 10, length: 160, phase: 1.3);
    if (y < surface) return (0, 0);
    final depth =
        ((y - surface) / math.max(size.height - surface, 1)).clamp(0.0, 1.0);
    final right =
        math.pow((x / size.width).clamp(0.0, 1.0), 1.8).toDouble();
    return (depth, right);
  }

  void _halftone(Canvas canvas, Size size) {
    const step = 8.0;
    final from = _p(58, 64, chroma: 56);
    final to = _t(60, 66, chroma: 56);
    for (double x = step / 2; x < size.width + step; x += step) {
      final dots = Path();
      for (double y = step / 2; y < size.height + step; y += step) {
        final (depth, right) = _under(x, y, size);
        final r = step * 0.52 * math.sqrt(depth * right);
        if (r < 0.5) continue;
        dots.addOval(Rect.fromCircle(center: Offset(x, y), radius: r));
      }
      final color =
          Color.lerp(from, to, (x / size.width).clamp(0.0, 1.0))!;
      canvas.drawPath(dots, _fill(color.withValues(alpha: 0.6)));
    }
  }

  void _depth(Canvas canvas, Size size) {
    final h = size.height;
    // дальние волны короче и ниже
    final layers = [
      (0.38, 1.6, 60.0, 0.5, _p(19, 90, chroma: 20)),
      (0.52, 2.4, 80.0, 2.0, _p(21, 88, chroma: 26)),
      (0.66, 3.4, 110.0, 3.4, _p(23, 86, chroma: 32)),
      (0.81, 4.6, 150.0, 1.2, _p(26, 83, chroma: 38)),
    ];
    for (final (level, amp, length, phase, color) in layers) {
      canvas.drawPath(
        _water(
          size,
          (x) => _surface(x, base: h * level, amp: amp, length: length, phase: phase),
        ),
        _fill(color),
      );
    }
  }

  (Offset, double) _cookieSpot(Size size) => (
        Offset(size.width * 0.93, size.height * 0.34),
        _unit(size) * 1.5,
      );

  void _cookieLayers(Canvas canvas, Size size) {
    final (at, s) = _cookieSpot(size);
    const steps = [1.0, 0.76, 0.54, 0.34];
    for (final (i, k) in steps.indexed) {
      canvas.drawPath(
        _shape(MaterialShapes.cookie9Sided, s * k, at: at, degrees: 14 + i * 9.0),
        _fill(_p(20 + i * 2.5, 89 - i * 2.5, chroma: 22 + i * 7.0)),
      );
    }
  }

  void _cookieShift(Canvas canvas, Size size) {
    final (at, s) = _cookieSpot(size);
    canvas
      ..drawPath(
        _shape(MaterialShapes.cookie9Sided, s, at: at + const Offset(-12, 9), degrees: 14),
        _fill(_t(24, 86, chroma: 34).withValues(alpha: 0.9)),
      )
      ..drawPath(
        _shape(MaterialShapes.cookie9Sided, s, at: at, degrees: 14),
        _fill(_p(23, 86, chroma: 34)),
      )
      ..drawPath(
        _shape(MaterialShapes.cookie9Sided, s, at: at + const Offset(10, -8), degrees: 14),
        _stroke(_p(60, 62, chroma: 40).withValues(alpha: 0.5), 1.6),
      );
  }

  static final _patternShapes = [
    MaterialShapes.cookie7Sided,
    MaterialShapes.flower,
    MaterialShapes.clover4Leaf,
    MaterialShapes.sunny,
    MaterialShapes.puffy,
    MaterialShapes.softBurst,
    MaterialShapes.gem,
    MaterialShapes.cookie4Sided,
  ];

  void _shapePattern(Canvas canvas, Size size) {
    const step = 22.0;
    final from = _p(56, 62, chroma: 44);
    final to = _t(58, 64, chroma: 44);
    var row = 0;
    for (double y = step / 2; y < size.height + step; y += step * 0.86, row++) {
      var col = 0;
      for (double x = row.isOdd ? step : step / 2; x < size.width + step; x += step, col++) {
        final (depth, right) = _under(x, y, size);
        final k = math.sqrt(depth) * right;
        if (k < 0.1) continue;
        final color =
            Color.lerp(from, to, (y / size.height).clamp(0.0, 1.0))!;
        canvas.drawPath(
          _shape(
            _patternShapes[(row * 3 + col) % _patternShapes.length],
            13,
            at: Offset(x, y),
            degrees: ((row * 37 + col * 19) % 90).toDouble(),
          ),
          _stroke(color.withValues(alpha: 0.8 * k), 1.6),
        );
      }
    }
  }

  void _shapeEdge(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final u = _unit(size);
    final top = _shape(MaterialShapes.flower, u, at: Offset(w, h * 0.06), degrees: 12);
    final bottom = _shape(
      MaterialShapes.clover4Leaf,
      u * 0.78,
      at: Offset(w * 0.84, h * 1.06),
      degrees: 20,
    );
    canvas
      ..drawPath(top, _fill(_p(22, 87, chroma: 30)))
      ..drawPath(top, _stroke(_p(58, 62, chroma: 42).withValues(alpha: 0.55), 2))
      ..drawPath(bottom, _fill(_t(21, 88, chroma: 26)))
      ..drawPath(bottom, _stroke(_t(58, 64, chroma: 42).withValues(alpha: 0.55), 2));
  }

  void _shapeAccent(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final u = _unit(size);
    final big = _shape(
      MaterialShapes.flower,
      u * 1.15,
      at: Offset(w * 0.88, h * 0.5),
      degrees: -6,
    );
    canvas
      ..drawPath(big, _fill(_p(20, 89, chroma: 24)))
      ..drawPath(big, _stroke(_p(58, 62, chroma: 42).withValues(alpha: 0.55), 2))
      ..drawPath(
        _shape(MaterialShapes.sunny, u * 0.2, at: Offset(w * 0.62, h * 0.8), degrees: 15),
        _fill(_t(52, 70, chroma: 52)),
      );
  }

  @override
  bool shouldRepaint(CardArtPainter old) =>
      old.art != art || old.scheme != scheme || old.rtl != rtl;
}
