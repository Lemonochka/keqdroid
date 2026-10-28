import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platform/platform_bootstrap.dart';
import '../../../providers/halloween_provider.dart';

// подмена только внутри этой границы: значки общие на всё приложение, и без неё
// сеть в настройках LAN тоже стала бы амулетом
class HalloweenIconScope extends ConsumerWidget {
  const HalloweenIconScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _HalloweenIcons(enabled: ref.watch(halloweenActiveProvider), child: child);
}

class _HalloweenIcons extends InheritedWidget {
  const _HalloweenIcons({required this.enabled, required super.child});

  final bool enabled;

  @override
  bool updateShouldNotify(_HalloweenIcons old) => old.enabled != enabled;
}

// замены нарисованы контурами: алхимических знаков Unicode нет во многих системных шрифтах Android
class SeasonalIcon extends StatelessWidget {
  const SeasonalIcon(this.icon, {super.key, this.size, this.color, this.semanticLabel});

  final IconData? icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_HalloweenIcons>();
    final glyph = scope != null && scope.enabled && icon != null ? _glyphFor(icon!) : null;
    if (glyph == null) {
      return Icon(icon, size: size, color: color, semanticLabel: semanticLabel);
    }
    final theme = IconTheme.of(context);
    final side = size ?? theme.size ?? 24;
    var ink = color ?? theme.color ?? const Color(0xFF000000);
    if (color == null && theme.opacity != null) ink = ink.withValues(alpha: ink.a * theme.opacity!);
    // знак по центру, как у Icon: узкая боковая панель на ПК растягивает рамку на всю ячейку
    final mark = SizedBox.square(dimension: side, child: CustomPaint(painter: _GlyphPainter(glyph, ink)));
    return Semantics(
      label: semanticLabel,
      child: SizedBox.square(dimension: side, child: Center(child: mark)),
    );
  }
}

// шестерёнка настроек и пуск/пауза в строке сервера остаются своими: замена мешала узнаванию
_Glyph? _glyphFor(IconData d) {
  if (d == Icons.arrow_upward_rounded) return _Glyph.air;
  if (d == Icons.arrow_downward_rounded) return _Glyph.earth;
  if (d == Icons.data_usage_rounded) return _Glyph.cauldron;
  if (d == Icons.schedule_rounded) return _Glyph.hourglass;
  // на телефоне это раздел Серверы, на ПК режим Proxy
  if (d == Icons.lan_rounded) return PlatformBootstrap.isDesktop ? _Glyph.amulet : _Glyph.crystalBall;
  if (d == Icons.dns_rounded || d == Icons.dns_outlined) return _Glyph.crystalBall;
  if (d == Icons.vpn_lock_rounded) return _Glyph.ward;
  if (d == Icons.language_rounded ||
      d == Icons.subscriptions_rounded ||
      d == Icons.subscriptions_outlined ||
      d == Icons.cloud_rounded) {
    return _Glyph.scroll;
  }
  if (d == Icons.refresh_rounded) return _Glyph.ouroboros;
  if (d == Icons.sort_rounded) return _Glyph.candles;
  if (d == Icons.network_ping_rounded) return _Glyph.eye;
  if (d == Icons.add_rounded) return _Glyph.sparkle;
  if (d == Icons.push_pin_rounded) return _Glyph.seal;
  return null;
}

enum _Glyph { air, earth, cauldron, hourglass, crystalBall, scroll, ouroboros, candles, eye, sparkle, amulet, ward, seal }

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.glyph, this.color);

  final _Glyph glyph;
  final Color color;

  static Path _circle(double x, double y, double r) => Path()..addOval(Rect.fromCircle(center: Offset(x, y), radius: r));

  static Path _roundedTriangle(List<Offset> pts, double r) {
    final p = Path();
    for (var i = 0; i < pts.length; i++) {
      final prev = pts[(i - 1 + pts.length) % pts.length], cur = pts[i], next = pts[(i + 1) % pts.length];
      final a = cur + (prev - cur) / (prev - cur).distance * r;
      final b = cur + (next - cur) / (next - cur).distance * r;
      if (i == 0) {
        p.moveTo(a.dx, a.dy);
      } else {
        p.lineTo(a.dx, a.dy);
      }
      p.quadraticBezierTo(cur.dx, cur.dy, b.dx, b.dy);
    }
    return p..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final s = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final f = Paint()..color = color;
    switch (glyph) {
      case _Glyph.air:
        canvas.drawPath(_roundedTriangle(const [Offset(12, 5), Offset(20, 18.5), Offset(4, 18.5)], 2.6), s);
        canvas.drawLine(const Offset(6, 13.2), const Offset(18, 13.2), s);
      case _Glyph.earth:
        canvas.drawPath(_roundedTriangle(const [Offset(4, 5.5), Offset(20, 5.5), Offset(12, 19)], 2.6), s);
        canvas.drawLine(const Offset(6, 10.8), const Offset(18, 10.8), s);
      case _Glyph.cauldron:
        canvas.drawLine(const Offset(3.5, 9.5), const Offset(20.5, 9.5), s);
        canvas.drawPath(Path()..moveTo(5, 9.5)..cubicTo(5, 15.5, 7.5, 19, 12, 19)..cubicTo(16.5, 19, 19, 15.5, 19, 9.5), s);
        canvas.drawLine(const Offset(7.5, 18), const Offset(6.5, 21), s);
        canvas.drawLine(const Offset(16.5, 18), const Offset(17.5, 21), s);
        canvas.drawPath(_circle(10, 5.6, 1.4), f);
        canvas.drawPath(_circle(14.2, 3.6, 1.1), f);
      case _Glyph.hourglass:
        canvas.drawLine(const Offset(6, 3.8), const Offset(18, 3.8), s);
        canvas.drawLine(const Offset(6, 20.2), const Offset(18, 20.2), s);
        canvas.drawPath(Path()
          ..moveTo(7.8, 3.8)..lineTo(16.2, 3.8)
          ..cubicTo(16.2, 8.2, 13.2, 10, 13.2, 12)..cubicTo(13.2, 14, 16.2, 15.8, 16.2, 20.2)
          ..lineTo(7.8, 20.2)
          ..cubicTo(7.8, 15.8, 10.8, 14, 10.8, 12)..cubicTo(10.8, 10, 7.8, 8.2, 7.8, 3.8)..close(), s);
        canvas.drawPath(Path()..moveTo(9.4, 20)..quadraticBezierTo(12, 15.6, 14.6, 20)..close(), f);
      case _Glyph.crystalBall:
        canvas.drawPath(_circle(12, 10, 6.8), s);
        canvas.drawPath(Path()..moveTo(7.6, 16)..lineTo(6, 20.5)..lineTo(18, 20.5)..lineTo(16.4, 16), s);
        canvas.drawPath(Path()..moveTo(8.8, 9)..quadraticBezierTo(9.3, 6.8, 11.5, 6.2), s);
      case _Glyph.scroll:
        canvas.drawPath(Path()
          ..moveTo(9.2, 4.4)..lineTo(18.2, 4.4)
          ..cubicTo(20.7, 4.4, 20.9, 7.6, 18.9, 7.6)..cubicTo(17.6, 7.6, 17.7, 5.9, 18.8, 6.0), s);
        canvas.drawLine(const Offset(9.2, 4.4), const Offset(4.8, 17.2), s);
        canvas.drawLine(const Offset(18.9, 7.6), const Offset(15.4, 17.2), s);
        canvas.drawPath(Path()
          ..moveTo(15.4, 17.2)..lineTo(4.8, 17.2)
          ..cubicTo(2.9, 17.2, 2.9, 20.6, 4.8, 20.6)..lineTo(15.2, 20.6)
          ..cubicTo(17.2, 20.6, 17.3, 17.9, 15.6, 17.9)..cubicTo(14.6, 17.9, 14.6, 19.3, 15.4, 19.3), s);
        canvas.drawLine(const Offset(10.6, 8.4), const Offset(16.2, 8.4), s);
        canvas.drawLine(const Offset(9.4, 11.4), const Offset(14.2, 11.4), s);
        canvas.drawLine(const Offset(8.2, 14.2), const Offset(11.4, 14.2), s);
      case _Glyph.ouroboros:
        const r = 7.0, start = -75 * math.pi / 180, sweep = 320 * math.pi / 180;
        canvas.drawArc(Rect.fromCircle(center: const Offset(12, 12.5), radius: r), start, sweep, false, s);
        canvas.drawPath(_circle(12 + r * math.cos(start + sweep), 12.5 + r * math.sin(start + sweep), 2.3), f);
      case _Glyph.candles:
        for (final (x, top) in const [(6.0, 8.5), (12.0, 12.0), (18.0, 15.5)]) {
          canvas.drawRRect(RRect.fromLTRBR(x - 1.7, top, x + 1.7, 20.5, const Radius.circular(.8)), f);
          canvas.drawPath(Path()
            ..moveTo(x, top - 5)..cubicTo(x + 1.6, top - 3, x + 1.4, top - 1.2, x, top - 1)
            ..cubicTo(x - 1.4, top - 1.2, x - 1.6, top - 3, x, top - 5)..close(), f);
        }
      case _Glyph.eye:
        // без треугольника вокруг, чтобы не вышло всевидящее око
        canvas.drawPath(Path()
          ..moveTo(3, 12)..cubicTo(5.2, 7.6, 8.4, 5.5, 12, 5.5)..cubicTo(15.6, 5.5, 18.8, 7.6, 21, 12)
          ..cubicTo(18.8, 16.4, 15.6, 18.5, 12, 18.5)..cubicTo(8.4, 18.5, 5.2, 16.4, 3, 12)..close(), s);
        canvas.drawPath(_circle(12, 12, 3.3), f);
      case _Glyph.sparkle:
        canvas.drawPath(Path()
          ..moveTo(12, 3)..quadraticBezierTo(13, 11, 21, 12)..quadraticBezierTo(13, 13, 12, 21)
          ..quadraticBezierTo(11, 13, 3, 12)..quadraticBezierTo(11, 11, 12, 3)..close(), f);
      case _Glyph.amulet:
        canvas.drawPath(Path()..moveTo(6.5, 3)..quadraticBezierTo(12, 10, 17.5, 3), s);
        canvas.drawPath(_circle(12, 14.5, 5.5), s);
        canvas.drawPath(Path()..moveTo(12, 11.6)..lineTo(14.2, 14.5)..lineTo(12, 17.4)..lineTo(9.8, 14.5)..close(), f);
      case _Glyph.ward:
        canvas.drawPath(_circle(12, 12, 8.5), s);
        canvas.drawPath(_circle(12, 12, 4.5), s);
        for (final (x, y) in const [(12.0, 5.5), (18.5, 12.0), (12.0, 18.5), (5.5, 12.0)]) {
          canvas.drawPath(_circle(x, y, 1.1), f);
        }
      case _Glyph.seal:
        canvas.drawPath(Path()..moveTo(9, 15)..lineTo(7.5, 21)..lineTo(10, 19.8)..lineTo(11, 16), f);
        canvas.drawPath(Path()..moveTo(15, 15)..lineTo(16.5, 21)..lineTo(14, 19.8)..lineTo(13, 16), f);
        canvas.drawPath(
          Path.combine(PathOperation.difference, _circle(12, 10, 7),
              Path.combine(PathOperation.difference, _circle(12, 10, 4.6), _circle(12, 10, 3.2))),
          f,
        );
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.glyph != glyph || old.color != color;
}
