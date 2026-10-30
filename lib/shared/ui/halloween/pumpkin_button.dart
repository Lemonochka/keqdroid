import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../haptics.dart';
import '../tv_focus.dart';

// движение и тайминги перенесены из согласованного прототипа один в один
class PumpkinConnectButton extends StatefulWidget {
  const PumpkinConnectButton({
    super.key,
    required this.isConnected,
    required this.isConnecting,
    required this.isError,
    required this.onTap,
  });

  final bool isConnected;
  final bool isConnecting;
  final bool isError;
  final VoidCallback? onTap;

  // сторона как у обычной кнопки, иначе шапка прыгает при смене оформления
  static const double size = 136;

  @override
  State<PumpkinConnectButton> createState() => _PumpkinConnectButtonState();
}

enum _Mode { off, connecting, on, error }

abstract final class _Curves {
  static const ease = Cubic(.25, .1, .25, 1);
  static const easeOut = Cubic(0, 0, .58, 1);
  static const easeInOut = Cubic(.42, 0, .58, 1);
  static const emphasized = Cubic(.2, 0, 0, 1);
  static const overshoot = Cubic(.34, 1.56, .64, 1);
}

class _PumpkinConnectButtonState extends State<PumpkinConnectButton> with TickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  final _frame = ValueNotifier<int>(0);

  // без границ, иначе при отпускании срежется перелёт пружинистой кривой
  late final AnimationController _press = AnimationController.unbounded(vsync: this)..addListener(_repaint);

  _Mode _mode = _Mode.off;
  Duration _tick = Duration.zero;
  Duration _entry = Duration.zero;

  // значения на входе в состояние: переход начинается с застигнутого кадра,
  // иначе мигание и покачивание обрывались бы скачком
  List<double> _faceFrom = _Face.sleep;
  Color? _tintFrom;
  double _opacityFrom = 1;
  double _litFrom = 0;
  double _tiltFrom = 0;

  Color _sleepInk = const Color(0xFF888888);

  bool get _calm => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  _Mode get _targetMode {
    if (widget.isConnecting) return _Mode.connecting;
    if (widget.isConnected) return _Mode.on;
    if (widget.isError) return _Mode.error;
    return _Mode.off;
  }

  @override
  void initState() {
    super.initState();
    // первый кадр сразу в нужном состоянии: открытый экран не зажигает заново горящую тыкву
    _mode = _targetMode;
    _faceFrom = _faceTarget(_mode);
    _litFrom = _mode == _Mode.on ? 1 : 0;
    _opacityFrom = _mode == _Mode.connecting ? .5 : 1;
    if (_mode == _Mode.connecting || _mode == _Mode.on) _ticker.start();
  }

  @override
  void didUpdateWidget(PumpkinConnectButton old) {
    super.didUpdateWidget(old);
    final next = _targetMode;
    if (next == _mode) return;
    // системный диалог разрешения VPN забирает окно, и отпускание пальца может не дойти:
    // тыква осталась бы сплющенной до следующего касания
    _setPressed(false);
    final t = _sinceEntry;
    _faceFrom = _faceAt(t);
    _tintFrom = _tintAt(t);
    _opacityFrom = _opacityAt(t);
    _litFrom = _litAt(t);
    _tiltFrom = _tiltAt(t);
    _mode = next;
    if (!_ticker.isActive) {
      _tick = Duration.zero;
      _ticker.start();
    }
    _entry = _tick;
    _repaint();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _press.dispose();
    _frame.dispose();
    super.dispose();
  }

  double get _sinceEntry => (_tick - _entry).inMicroseconds / 1000;

  void _onTick(Duration elapsed) {
    _tick = elapsed;
    _repaint();
    // тикер только для бесконечных анимаций, иначе неподвижная тыква жгла бы батарею
    final endless = !_calm && (_mode == _Mode.connecting || _mode == _Mode.on);
    if (!endless && _sinceEntry > 1600) _ticker.stop();
  }

  void _repaint() => _frame.value++;

  void _setPressed(bool pressed) {
    if (pressed) {
      _press.animateTo(1, duration: const Duration(milliseconds: 80), curve: _Curves.easeOut);
    } else {
      _press.animateTo(0, duration: const Duration(milliseconds: 450), curve: _Curves.overshoot);
    }
  }

  static double _progress(double t, double delay, double duration, Curve curve) =>
      curve.transform(((t - delay) / duration).clamp(0.0, 1.0));

  static List<double> _faceTarget(_Mode m) => switch (m) {
        _Mode.off => _Face.sleep,
        _Mode.connecting || _Mode.on => _Face.lit,
        _Mode.error => _Face.sad,
      };

  List<double> _faceAt(double t) {
    final (delay, duration) = switch (_mode) {
      _Mode.off => (0.0, 450.0),
      _Mode.connecting || _Mode.on => (0.0, 600.0),
      _Mode.error => (450.0, 800.0),
    };
    final k = _progress(t, delay, duration, _Curves.emphasized);
    final to = _faceTarget(_mode);
    return [for (var i = 0; i < to.length; i++) lerpDouble(_faceFrom[i], to[i], k)!];
  }

  Color _tintAt(double t) {
    final to = _tintTarget(_mode);
    final from = _tintFrom;
    if (from == null) return to;
    final k = _mode == _Mode.error
        ? _progress(t, 0, 1200, _Curves.easeInOut)
        : _progress(t, 0, 350, _Curves.ease);
    return Color.lerp(from, to, k)!;
  }

  Color _tintTarget(_Mode m) => switch (m) {
        _Mode.connecting => _Colors.glowDim,
        _Mode.on => _Colors.glow,
        _Mode.off || _Mode.error => _sleepInk,
      };

  double _opacityAt(double t) {
    switch (_mode) {
      case _Mode.off:
        if (_calm) return 1;
        return lerpDouble(_opacityFrom, 1, _progress(t, 0, 450, _Curves.easeOut))!;
      case _Mode.connecting:
        if (_calm || t < 350) return lerpDouble(_opacityFrom, .5, _progress(t, 0, 300, _Curves.ease))!;
        return _Keys.flicker((t - 350) % 1100 / 1100);
      case _Mode.on:
        if (_calm) return 1;
        return _Keys.candle(t % 2600 / 2600);
      case _Mode.error:
        if (_calm) return 1;
        return _Keys.dying(_opacityFrom, _progress(t, 0, 1400, _Curves.easeOut));
    }
  }

  double _litAt(double t) {
    final to = _mode == _Mode.on ? 1.0 : 0.0;
    return lerpDouble(_litFrom, to, _progress(t, 0, 350, _Curves.emphasized))!;
  }

  double _tiltAt(double t) {
    if (_mode != _Mode.connecting || _calm) return 0;
    return _Keys.wobble(t % 900 / 900) * math.pi / 180;
  }

  ({double tilt, double dy, double sx, double sy}) _poseAt(double t) {
    if (_calm) return (tilt: 0, dy: 0, sx: 1, sy: 1);
    switch (_mode) {
      case _Mode.connecting:
        return (tilt: _tiltAt(t), dy: 0, sx: 1, sy: 1);
      case _Mode.on:
        if (t >= 500) return (tilt: 0, dy: 0, sx: 1, sy: 1);
        final p = t / 500;
        final (k, from, to) = p < .35
            ? (_Curves.overshoot.transform(p / .35), 0.0, 1.0)
            : (_Curves.overshoot.transform((p - .35) / .65), 1.0, 0.0);
        final w = lerpDouble(from, to, k)!;
        return (tilt: 0, dy: -8 * w, sx: 1 - .03 * w, sy: 1 + .04 * w);
      case _Mode.error:
        if (t >= 1000) return (tilt: 0, dy: 0, sx: 1, sy: 1);
        final p = _Curves.emphasized.transform(t / 1000);
        if (p < .55) {
          final k = p / .55;
          return (tilt: _tiltFrom * (1 - k), dy: 0, sx: 1 + .03 * k, sy: 1 - .06 * k);
        }
        final k = (p - .55) / .45;
        return (tilt: 0, dy: 0, sx: 1.03 - .03 * k, sy: .94 + .06 * k);
      case _Mode.off:
        return (tilt: 0, dy: 0, sx: 1, sy: 1);
    }
  }

  void _activate() {
    AppHaptics.impact();
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    // цвета снаружи обёртки фокуса: внутри тело спящей тыквы инвертировалось бы в цвет самой заливки
    final scheme = Theme.of(context).colorScheme;
    _sleepInk = scheme.onSurfaceVariant;
    final enabled = widget.onTap != null;
    return TvFocusHighlight(
      radius: BorderRadius.circular(PumpkinConnectButton.size / 2),
      // на одном GestureDetector фокус не вставал, и пультом Android TV тыква не включалась
      child: FocusableActionDetector(
        enabled: enabled,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => _activate()),
        },
        child: Semantics(
          button: true,
          enabled: enabled,
          child: MouseRegion(
            cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: enabled ? (_) => _setPressed(true) : null,
              onTapUp: enabled ? (_) => _setPressed(false) : null,
              onTapCancel: enabled ? () => _setPressed(false) : null,
              onTap: enabled ? _activate : null,
              child: SizedBox.square(
                dimension: PumpkinConnectButton.size,
                child: CustomPaint(
                  painter: _PumpkinPainter(
                    state: this,
                    sleepInk: scheme.onSurfaceVariant,
                    idleBody: scheme.surfaceContainerHighest,
                    idleRibs: scheme.outlineVariant,
                    repaint: _frame,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

abstract final class _Colors {
  static const body = Color(0xFFFF7518);
  static const ribs = Color(0xFFC55500);
  static const stem = Color(0xFF6E8B3D);
  static const glow = Color(0xFFFFE08A);
  static const glowDim = Color(0xFFFFB347);
}

abstract final class _Keys {
  static const _flicker = [(0.0, .15), (.12, .5), (.20, .25), (.35, .65), (.48, .35), (.62, .7), (.75, .3), (.88, .55)];

  static double flicker(double p) {
    var v = _flicker.first.$2;
    for (final (at, value) in _flicker) {
      if (p >= at) v = value;
    }
    return v;
  }

  static double candle(double p) => _smooth(p, const [(0, 1), (.4, .86), (.55, .97), (.7, .9), (1, 1)]);

  // в градусах
  static double wobble(double p) => _smooth(p, const [(0, -1.5), (.5, 1.5), (1, -1.5)]);

  static double dying(double from, double p) =>
      _linear(p, [(0, from), (.15, .6), (.3, .3), (.45, .5), (.6, .4), (1, 1)]);

  static double _smooth(double p, List<(double, double)> keys) => _interp(p, keys, _Curves.easeInOut);

  static double _linear(double p, List<(double, double)> keys) => _interp(p, keys, Curves.linear);

  static double _interp(double p, List<(double, double)> keys, Curve curve) {
    for (var i = 1; i < keys.length; i++) {
      final (a, va) = keys[i - 1];
      final (b, vb) = keys[i];
      if (p <= b) return lerpDouble(va, vb, curve.transform(((p - a) / (b - a)).clamp(0.0, 1.0)))!;
    }
    return keys.last.$2;
  }
}

// лица перетекают по точкам, поэтому набор команд пути у всех трёх одинаков,
// иначе при засыпании глаза закручиваются крючками; последнее число толщина обводки
@visibleForTesting
bool debugPumpkinFacesShareShape() => _Face.sameShape;

abstract final class _Face {
  static const _litContours = [
    'M40 72 Q36 72 38 68 L47 54 Q50 50 52 54 L57 68 Q58 72 54 72 Z',
    'M96 72 Q100 72 98 68 L89 54 Q86 50 84 54 L79 68 Q78 72 82 72 Z',
    'M38 84 Q52 90 63 91 L63 97 L72 97 L72 91 Q86 90 98 84 C98 102 86 115 68 115 L57 113 L55 106 L47 104 C42 99 38 92 38 84 Z',
  ];

  static const _sleepContours = [
    'M40 66 Q40 66 40 66 L40 66 Q47 72 54 66 L54 66 Q47 72 40 66 Z',
    'M96 66 Q96 66 96 66 L96 66 Q89 72 82 66 L82 66 Q89 72 96 66 Z',
    'M60 90 Q64 92.5 68 92.5 L68 92.5 L68 92.5 L68 92.5 Q72 92.5 76 90 C73.33 91.67 70.67 92.5 68 92.5 L68 92.5 L68 92.5 L68 92.5 C65.33 92.5 62.67 91.67 60 90 Z',
  ];

  static const _sadContours = [
    'M40 75 Q36 75 38 71 L48 61 Q52 57 54 60 L57 69 Q58 73 54 73 Z',
    'M96 75 Q100 75 98 71 L88 61 Q84 57 82 60 L79 69 Q78 73 82 73 Z',
    'M42 108 Q54 92 63 91 L63 96 L72 96 L72 91 Q84 92 94 108 C86 104 78 103 68 103 L60 103.5 L59 99.5 L52 100.5 C48 103 45 105 42 108 Z',
  ];

  static final lit = _numbers(_litContours, 0);
  static final sleep = _numbers(_sleepContours, 3.5);
  static final sad = _numbers(_sadContours, 0);

  static final commands = _commands(_litContours);

  static bool get sameShape =>
      _same(_commands(_sleepContours), commands) && _same(_commands(_sadContours), commands);

  static bool _same(List<String> a, List<String> b) =>
      a.length == b.length && [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);

  static List<double> _numbers(List<String> contours, double stroke) => [
        for (final d in contours) ...RegExp(r'-?\d*\.?\d+').allMatches(d).map((m) => double.parse(m[0]!)),
        stroke,
      ];

  static List<String> _commands(List<String> contours) =>
      [for (final d in contours) RegExp('[MLQCZ]').allMatches(d).map((m) => m[0]!).join()];

  static Path path(List<double> v) {
    final p = Path();
    var i = 0;
    double n() => v[i++];
    for (final contour in commands) {
      for (final cmd in contour.split('')) {
        switch (cmd) {
          case 'M':
            p.moveTo(n(), n());
          case 'L':
            p.lineTo(n(), n());
          case 'Q':
            p.quadraticBezierTo(n(), n(), n(), n());
          case 'C':
            p.cubicTo(n(), n(), n(), n(), n(), n());
          case 'Z':
            p.close();
        }
      }
    }
    return p;
  }
}

class _PumpkinPainter extends CustomPainter {
  _PumpkinPainter({
    required this.state,
    required this.sleepInk,
    required this.idleBody,
    required this.idleRibs,
    required super.repaint,
  });

  final _PumpkinConnectButtonState state;
  final Color sleepInk;
  final Color idleBody;
  final Color idleRibs;

  static final _stem = Path()
    ..moveTo(61, 21)..cubicTo(62, 12, 61, 4, 58, -6)..lineTo(70, -7)
    ..cubicTo(71, 3, 73, 12, 75, 21)..quadraticBezierTo(68, 18, 61, 21)..close();
  static final _body = Path()
    ..moveTo(48, 23)..cubicTo(26, 13, 3, 30, 3, 74)..cubicTo(3, 112, 26, 134, 46, 130)
    ..quadraticBezierTo(57, 127, 68, 131)..quadraticBezierTo(79, 127, 90, 130)
    ..cubicTo(110, 134, 133, 112, 133, 74)..cubicTo(133, 30, 110, 13, 88, 23)
    ..cubicTo(82, 18, 75, 16, 68, 16)..cubicTo(61, 16, 54, 18, 48, 23)..close();
  static final _ribs = Path()
    ..moveTo(34, 50)..cubicTo(40, 38, 50, 28, 60, 24)
    ..moveTo(102, 50)..cubicTo(96, 38, 86, 28, 76, 24);

  static const _origin = Offset(68, 131);

  @override
  void paint(Canvas canvas, Size size) {
    final s = state;
    final t = s._sinceEntry;
    final lit = s._litAt(t);
    final pose = s._poseAt(t);
    final press = s._press.value;
    final face = s._faceAt(t);
    final tint = s._tintAt(t);
    final opacity = s._opacityAt(t).clamp(0.0, 1.0);

    canvas.scale(size.width / PumpkinConnectButton.size);
    canvas
      ..translate(_origin.dx, _origin.dy)
      ..translate(0, pose.dy)
      ..rotate(pose.tilt)
      ..scale(pose.sx * (1 + .05 * press), pose.sy * (1 - .08 * press))
      ..translate(-_origin.dx, -_origin.dy);

    canvas.drawPath(_stem, Paint()..color = _Colors.stem);
    canvas.drawPath(_body, Paint()..color = Color.lerp(idleBody, _Colors.body, lit)!);
    canvas.drawPath(
      _ribs,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(idleRibs, _Colors.ribs, lit)!,
    );

    // лицо одним слоем с общей прозрачностью, иначе обводка и заливка темнеют на перекрытии
    final path = _Face.path(face);
    final stroke = face.last;
    final layer = opacity < 1;
    if (layer) {
      canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, opacity));
    }
    canvas.drawPath(path, Paint()..color = tint);
    if (stroke > .01) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..color = sleepInk,
      );
    }
    if (layer) canvas.restore();
  }

  @override
  bool shouldRepaint(_PumpkinPainter old) =>
      old.state != state || old.sleepInk != sleepInk || old.idleBody != idleBody || old.idleRibs != idleRibs;
}
