import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:androidx_graphics_shapes/material_shapes.dart';
import 'package:androidx_graphics_shapes/shapes.dart';
import 'package:flutter/material.dart';

import 'smooth_fade.dart';

enum LiquidPhase { idle, busy, active }

class LiquidLevels {
  const LiquidLevels({
    required this.idle,
    required this.busy,
    required this.quiet,
    required this.loud,
    this.inDp = false,
  });

  final double idle;
  final double busy;

  // при подключении вода стоит между ними: тихо без трафика, высоко при полной загрузке
  final double quiet;
  final double loud;

  // false: доля высоты от дна
  final bool inDp;

  double target(LiquidPhase phase, double load) => switch (phase) {
        LiquidPhase.idle => idle,
        LiquidPhase.busy => busy,
        LiquidPhase.active => quiet + (loud - quiet) * load,
      };
}

class _LiquidLayer {
  const _LiquidLayer(
    this.length,
    this.pace,
    this.swellLength,
    this.swellPace,
    this.breath,
  );

  final double length;
  final double pace;
  final double swellLength;
  final double swellPace;
  final double breath;
}

class LiquidWaveSim {
  double level = 0;
  double amplitude = 0;
  double alpha = 0;
  double speed = 0;
  double load = 0;
  double time = 0;

  // где кнопка, доля ширины слева направо: тут вода поднимается первой
  double splashAt = 0.5;

  final List<double> _phases = [0, 0.7 * pi, 0, 1.9];

  // уровень от состояния ходит на пружине, добавка от трафика без перелёта
  double _rest = 0;
  double _restSpeed = 0;
  double _lift = 0;

  static const _substep = 1 / 240;

  // уровень за последнюю секунду: дальние от кнопки места повторяют его с опозданием
  static const _historyRate = 120.0;
  static const _fillTravel = 1.1;
  final _history = List<double>.filled(150, 0);
  var _historyHead = 0;
  var _historyClock = 0.0;

  // при равной скорости слоёв картинка повторялась бы целиком каждые пару секунд
  static const _front = _LiquidLayer(90, 1.0, 530, 0.09, 11.3);
  static const _back = _LiquidLayer(140, 0.77, 710, 0.064, 16.7);

  static (double, double, double) _targets(LiquidPhase phase, double load) =>
      switch (phase) {
        LiquidPhase.idle => (1.5, 0.07, 1.5),
        LiquidPhase.busy => (6.0, 0.14, 4.5),
        LiquidPhase.active => (3.8 + 2.4 * load, 0.16, 3.2 + load),
      };

  // фон мессенджеров в пару десятков КБ/с воду не трогает, видео поднимает примерно наполовину
  static double loadFor(int bytesPerSec) {
    const floor = 32 * 1024;
    const ceiling = 8 * 1024 * 1024;
    if (bytesPerSec <= floor) return 0;
    final normalized =
        (log(bytesPerSec) - log(floor)) / (log(ceiling) - log(floor));
    return normalized.clamp(0.0, 1.0);
  }

  void snap(LiquidPhase phase, LiquidLevels levels, double targetLoad) {
    load = targetLoad;
    _rest = levels.target(phase, 0);
    _restSpeed = 0;
    _lift = levels.target(phase, load) - _rest;
    level = _rest + _lift;
    final (amp, a, s) = _targets(phase, load);
    amplitude = amp;
    alpha = a;
    speed = s;
    _history.fillRange(0, _history.length, level);
  }

  void step(
    double dt,
    LiquidPhase phase,
    LiquidLevels levels,
    double targetLoad,
  ) {
    final d = dt.clamp(0.0, 0.1);
    time += d;
    // скорость трафика приходит раз в секунду: без сглаживания вода скачет на каждом отсчёте
    load = _ease(load, targetLoad, d, targetLoad > load ? 1.5 : 3.5);
    final (amp, a, s) = _targets(phase, load);
    final rest = levels.target(phase, 0);
    _lift = _ease(_lift, levels.target(phase, load) - rest, d, 1.0);
    _spring(rest, d);
    amplitude = _ease(amplitude, amp, d, 1.0);
    alpha = _ease(alpha, a, d, 0.5);
    speed = _ease(speed, s, d, 0.8);
    // фаза копится, а не считается от времени: при смене скорости гребни не прыгают
    for (final (i, layer) in [_front, _back].indexed) {
      _phases[i] += layer.pace * speed * d;
      _phases[2 + i] += layer.swellPace * speed * d;
    }
  }

  static double _ease(double value, double target, double dt, double tau) =>
      value + (target - value) * (1 - exp(-dt / tau));

  // пружина, а не плавный доезд: ровный подъём выглядел топорно
  void _spring(double target, double dt) {
    const omega = 4.5;
    const zeta = 0.5;
    final n = max(1, (dt / _substep).ceil());
    final h = dt / n;
    for (var i = 0; i < n; i++) {
      _restSpeed +=
          (omega * omega * (target - _rest) - 2 * zeta * omega * _restSpeed) *
              h;
      _rest += _restSpeed * h;
      level = _rest + _lift;
      _historyClock += h;
      while (_historyClock >= 1 / _historyRate) {
        _historyClock -= 1 / _historyRate;
        _history[_historyHead] = level;
        _historyHead = (_historyHead + 1) % _history.length;
      }
    }
  }

  double levelAt(double fraction) {
    final n = _history.length;
    final lag = (fraction - splashAt).abs() / _fillTravel * _historyRate;
    final whole = lag.floor();
    if (whole >= n - 2) return _history[_historyHead];
    final t = lag - whole;
    final newer = _history[(_historyHead - 1 - whole + n) % n];
    // самое свежее значение ещё не в истории
    if (whole == 0) return level + (newer - level) * t;
    final older = _history[(_historyHead - 2 - whole + n) % n];
    return newer + (older - newer) * t;
  }

  double displacement(double x, {bool back = false}) {
    final layer = back ? _back : _front;
    final i = back ? 1 : 0;
    // гребни чуть разной высоты и медленно дышат, форма остаётся одной синусоидой
    final swell =
        1 + 0.15 * sin(2 * pi * x / layer.swellLength - _phases[2 + i]);
    final breathe = 1 + 0.1 * sin(2 * pi * time / layer.breath + 2.1 * i);
    return amplitude *
        swell *
        breathe *
        sin(2 * pi * x / layer.length - _phases[i]);
  }
}

enum LiquidShapeAnchor { top, side, low }

class LiquidShapeSpot {
  const LiquidShapeSpot(
    this.polygon, {
    required this.anchor,
    required this.x,
    required this.y,
    required this.size,
    this.degrees = 0,
    this.alpha = 0.1,
  });

  final RoundedPolygon polygon;
  final LiquidShapeAnchor anchor;

  // top и low: доля ширины; side: dp от дальнего края
  final double x;

  // top и side: dp от верха; low: dp от дна, вода при сильном трафике их подтапливает
  final double y;
  final double size;
  final double degrees;
  final double alpha;
}

// кнопка над водой: по центру шапки, верхом на shapesTop
class LiquidMirror {
  const LiquidMirror({
    required this.color,
    required this.size,
    required this.corner,
  });

  final Color color;
  final double size;
  final double corner;

  @override
  bool operator ==(Object other) =>
      other is LiquidMirror &&
      other.color == color &&
      other.size == size &&
      other.corner == corner;

  @override
  int get hashCode => Object.hash(color, size, corner);
}

class LiquidWave extends StatefulWidget {
  const LiquidWave({
    super.key,
    required this.clock,
    required this.phase,
    required this.levels,
    required this.load,
    required this.color,
    this.fade = false,
    this.shapePresets = const [],
    this.liveShapes = const [],
    this.shapeColor = Colors.transparent,
    this.lowZoneFree = true,
    this.shapesTop = 0,
    this.splashFromEnd,
    this.overhang = 0,
    this.mirror,
  });

  // тикает, пока шапка анимируется: волна стоит вместе с ней
  final AnimationController clock;
  final LiquidPhase phase;
  final LiquidLevels levels;
  final double load;
  final Color color;

  // уходит в прозрачность к низу, чтобы под шапкой не было края
  final bool fade;

  final List<List<LiquidShapeSpot>> shapePresets;

  // стоят на своих местах, но плавают и перетекают каждая в форму соседки
  final List<LiquidShapeSpot> liveShapes;
  final Color shapeColor;

  // фигуры у воды прячутся, когда над ней строка метрик
  final bool lowZoneFree;

  // сдвиг top и side вниз: в легаси над кнопкой ещё статус-бар
  final double shapesTop;

  // центр кнопки в dp от дальнего края, null: посередине
  final double? splashFromEnd;

  // сколько слоя свисает ниже шапки: уровни считаются от её низа, а вода гаснет до конца слоя
  final double overhang;

  final LiquidMirror? mirror;

  static ui.FragmentProgram? _reflection;
  static Future<void>? _loading;

  static Future<void> loadShaders() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      _reflection =
          await ui.FragmentProgram.fromAsset('shaders/reflection.frag');
    } catch (_) {}
  }

  static const presetEvery = Duration(seconds: 30);
  static const presetChange = Duration(milliseconds: 1400);

  @override
  State<LiquidWave> createState() => LiquidWaveState();
}

class LiquidWaveState extends State<LiquidWave>
    with SingleTickerProviderStateMixin {
  final sim = LiquidWaveSim();
  final _tick = ValueNotifier<int>(0);
  final _morphs = <LiquidShapeSpot, Morph>{};
  final _wholeShapes = <(LiquidShapeSpot, bool), Path>{};
  final ui.FragmentShader? _mirror = LiquidWave._reflection?.fragmentShader();
  final _paths = <LiquidShapeSpot, Path>{};
  // свой на каждый слой: значения шейдера меняются перед каждым рисованием
  final _fades = [SmoothFade.newFadeShader(), SmoothFade.newFadeShader()];
  Duration? _lastElapsed;
  Timer? _timer;
  var _from = 0;
  var _to = 1;

  // часы шапки встают через 2 с после отключения: фигурки к этому времени уже замедлились,
  // а не обрываются на полном ходу
  double _shapeTime = 0;
  late double _life = widget.phase == LiquidPhase.idle ? 0 : 1;

  // фигуры у воды тонут под строкой метрик и всплывают, а не пропадают
  late double _low = widget.lowZoneFree ? 1 : 0;

  late final AnimationController _change = AnimationController(
    vsync: this,
    duration: LiquidWave.presetChange,
  );

  @visibleForTesting
  int get shownPreset => _change.value >= 0.5 ? _to : _from;

  @visibleForTesting
  double get shapeLife => _life;

  @visibleForTesting
  double get lowShown => _low;

  @override
  void initState() {
    super.initState();
    sim.snap(widget.phase, widget.levels, widget.load);
    widget.clock.addListener(_onTick);
    _startPresets();
  }

  @override
  void didUpdateWidget(LiquidWave oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    if (old.clock != widget.clock) {
      old.clock.removeListener(_onTick);
      widget.clock.addListener(_onTick);
      _lastElapsed = null;
    }
    if (old.shapePresets.length != widget.shapePresets.length) {
      _from = 0;
      _to = widget.shapePresets.length > 1 ? 1 : 0;
      _change.value = 0;
      _startPresets();
    }
  }

  @override
  void dispose() {
    widget.clock.removeListener(_onTick);
    _timer?.cancel();
    _change.dispose();
    _tick.dispose();
    for (final fade in _fades) {
      fade?.dispose();
    }
    _mirror?.dispose();
    super.dispose();
  }

  void _startPresets() {
    _timer?.cancel();
    _timer = null;
    if (widget.shapePresets.length < 2) return;
    _timer = Timer.periodic(LiquidWave.presetEvery, (_) => _nextPreset());
  }

  void _nextPreset() {
    // за другой вкладкой не листаем: вернёшься, а наборы прокручены
    if (!mounted || !TickerMode.valuesOf(context).enabled) return;
    if (_change.isAnimating) return;
    if (_change.isCompleted) {
      setState(() {
        _from = _to;
        _to = (_to + 1) % widget.shapePresets.length;
      });
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _change.value = 1;
    } else {
      _change.forward(from: 0);
    }
  }

  void _onTick() {
    final elapsed = widget.clock.lastElapsedDuration;
    final last = _lastElapsed;
    _lastElapsed = elapsed;
    // контроллер перезапускался: время пошло с нуля, берём один кадр
    final dt = elapsed != null && last != null && elapsed > last
        ? (elapsed - last).inMicroseconds / Duration.microsecondsPerSecond
        : 1 / 60;
    sim.step(dt, widget.phase, widget.levels, widget.load);
    final d = dt.clamp(0.0, 0.1);
    _life = LiquidWaveSim._ease(
      _life,
      widget.phase == LiquidPhase.idle ? 0 : 1,
      d,
      0.4,
    );
    _shapeTime += d * _life;
    _low = LiquidWaveSim._ease(_low, widget.lowZoneFree ? 1 : 0, d, 0.15);
    _tick.value++;
  }

  // форма держится и перетекает в соседнюю за секунду: непрерывное перетекание выглядело кашей
  @visibleForTesting
  static double morphAt(double time, int i) {
    const hold = 4.0;
    const morph = 1.0;
    final x = (time + i * 2.3) % (2 * (hold + morph));
    double ease(double v) => Curves.easeInOutCubic.transform(v.clamp(0.0, 1.0));
    if (x < morph) return ease(x / morph);
    if (x < morph + hold) return 1;
    if (x < 2 * morph + hold) return 1 - ease((x - morph - hold) / morph);
    return 0;
  }

  Path _pathFor(LiquidShapeSpot spot) => _paths.putIfAbsent(
        spot,
        () => RoundedPolygonBorder(polygon: spot.polygon).getOuterPath(
          Rect.fromCenter(
            center: Offset.zero,
            width: spot.size,
            height: spot.size,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return LayoutBuilder(
      builder: (context, constraints) {
        final fromEnd = widget.splashFromEnd;
        final w = constraints.maxWidth;
        final at = fromEnd == null || !w.isFinite || w <= 0
            ? 0.5
            : (1 - fromEnd / w).clamp(0.0, 1.0);
        sim.splashAt = rtl ? 1 - at : at;
        return RepaintBoundary(
          child: CustomPaint(
            painter: _LiquidPainter(
              state: this,
              repaint: Listenable.merge([_tick, _change]),
              color: widget.color,
              shapeColor: widget.shapeColor,
              mirror: widget.mirror,
              fade: widget.fade,
              shapesTop: widget.shapesTop,
              rtl: rtl,
              devicePixelRatio:
                  MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
            ),
          ),
        );
      },
    );
  }
}

class _LiquidPainter extends CustomPainter {
  _LiquidPainter({
    required this.state,
    required Listenable repaint,
    required this.color,
    required this.shapeColor,
    required this.mirror,
    required this.fade,
    required this.shapesTop,
    required this.rtl,
    required this.devicePixelRatio,
  }) : super(repaint: repaint);

  final LiquidWaveState state;
  final Color color;
  final Color shapeColor;
  final LiquidMirror? mirror;
  final bool fade;
  final double shapesTop;
  final bool rtl;
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final sim = state.sim;
    final w = size.width;
    final h = size.height - state.widget.overhang;
    final levels = state.widget.levels;
    final base = h - (levels.inDp ? sim.level : sim.level * h);

    _liveShapes(canvas, size);
    final presets = state.widget.shapePresets;
    if (presets.isNotEmpty) {
      final t = Curves.easeInOut.transform(state._change.value);
      for (final (preset, fadeIn) in [(state._from, 1 - t), (state._to, t)]) {
        if (fadeIn <= 0 || preset >= presets.length) continue;
        for (final spot in presets[preset]) {
          _drawSpot(canvas, spot, fadeIn, w, h);
        }
      }
    }

    _wave(canvas, size, base, back: true, alpha: sim.alpha * 0.55, lift: 7);
    _wave(canvas, size, base, back: false, alpha: sim.alpha, lift: 0);
    _reflection(canvas, size, base);
  }

  void _liveShapes(Canvas canvas, Size size) {
    final spots = state.widget.liveShapes;
    final t = state._shapeTime;
    final w = size.width;
    final h = size.height - state.widget.overhang;
    for (var i = 0; i < spots.length; i++) {
      final spot = spots[i];
      final next = spots[(i + 1) % spots.length];
      final morph = state._morphs
          .putIfAbsent(spot, () => Morph(spot.polygon, next.polygon));
      // на остановке доходит до целой формы, а не замирает на полпути
      final p = LiquidWaveState.morphAt(t, i);
      final whole = p.roundToDouble();
      final progress = whole + (p - whole) * state._life;
      final (double dx, double dy) = switch (spot.anchor) {
        LiquidShapeAnchor.top => (w * spot.x, shapesTop + spot.y),
        LiquidShapeAnchor.side => (w - spot.x, shapesTop + spot.y),
        LiquidShapeAnchor.low => (w * spot.x, h - spot.y),
      };
      final sunk = _sunk(spot);
      if (sunk > 0.99) continue;
      final x = (rtl ? w - dx : dx) + sin(t * 0.25 + i * 1.7) * 10;
      final y = dy + cos(t * 0.21 + i) * 7 + sunk * _sinkDepth;
      final s = spot.size * 1.15;
      Path shape() => morph.toPath(progress: progress).transform(
            (Matrix4.identity()
                  ..translateByDouble(-s / 2, -s / 2, 0, 1)
                  ..scaleByDouble(s, s, 1, 1))
                .storage,
          );
      // целую форму фигурка держит 4 с из 5: контур на каждый кадр стоил ~9% ядра Pixel 6a
      final path = progress == 0 || progress == 1
          ? state._wholeShapes.putIfAbsent((spot, progress == 1), shape)
          : shape();
      canvas
        ..save()
        ..translate(x, y)
        ..rotate((spot.degrees + t * 9 * (i.isEven ? 1 : -1)) * pi / 180)
        ..drawPath(
          path,
          Paint()
            ..color = shapeColor.withValues(
              alpha: spot.alpha * 1.3 * (1 - sunk),
            ),
        )
        ..restore();
    }
  }

  static const _sinkDepth = 18.0;

  double _sunk(LiquidShapeSpot spot) =>
      spot.anchor == LiquidShapeAnchor.low ? 1 - state._low : 0;

  void _reflection(Canvas canvas, Size size, double base) {
    final mirror = this.mirror;
    final shader = state._mirror;
    if (mirror == null || shader == null) return;
    final w = size.width;
    final h = size.height;
    final sim = state.sim;
    final headerBottom = h - state.widget.overhang;
    final inDp = state.widget.levels.inDp;
    double surface(double x) {
      final level = sim.levelAt(x / w);
      return headerBottom -
          (inDp ? level : level * headerBottom) -
          sim.displacement(x);
    }
    final water = Path()..moveTo(0, h);
    for (double x = 0; x < w; x += 4) {
      water.lineTo(x, surface(x));
    }
    water
      ..lineTo(w, surface(w))
      ..lineTo(w, h)
      ..close();
    var i = 0;
    for (final v in [
      w,
      h,
      sim.time,
      w / 2,
      shapesTop,
      mirror.size / 2,
      mirror.corner,
      base,
      mirror.size * 0.85,
      0.8 + 0.5 * sim.amplitude,
      mirror.color.r,
      mirror.color.g,
      mirror.color.b,
      0.55 * mirror.color.a,
    ]) {
      shader.setFloat(i++, v);
    }
    canvas
      ..save()
      ..clipPath(water)
      ..drawRect(Offset.zero & size, Paint()..shader = shader)
      ..restore();
  }

  void _drawSpot(
    Canvas canvas,
    LiquidShapeSpot spot,
    double fadeIn,
    double w,
    double h,
  ) {
    final (double dx, double dy) = switch (spot.anchor) {
      LiquidShapeAnchor.top => (w * spot.x, shapesTop + spot.y),
      LiquidShapeAnchor.side => (w - spot.x, shapesTop + spot.y),
      LiquidShapeAnchor.low => (w * spot.x, h - spot.y),
    };
    final sunk = _sunk(spot);
    if (sunk > 0.99) return;
    final x = rtl ? w - dx : dx;
    canvas
      ..save()
      ..translate(x, dy + sunk * _sinkDepth)
      ..rotate(spot.degrees * pi / 180);
    canvas.drawPath(
      state._pathFor(spot),
      Paint()
        ..color = shapeColor.withValues(
          alpha: spot.alpha * fadeIn * (1 - sunk),
        ),
    );
    canvas.restore();
  }

  void _wave(
    Canvas canvas,
    Size size,
    double base, {
    required bool back,
    required double alpha,
    required double lift,
  }) {
    final sim = state.sim;
    final w = size.width;
    final h = size.height;
    final headerBottom = h - state.widget.overhang;
    if (alpha <= 0.001 || base >= h) return;
    final inDp = state.widget.levels.inDp;
    double surface(double x) {
      final level = sim.levelAt(x / w);
      return headerBottom -
          (inDp ? level : level * headerBottom) -
          lift -
          sim.displacement(x, back: back);
    }
    final path = Path()..moveTo(0, h);
    for (double x = 0; x < w; x += 4) {
      path.lineTo(x, surface(x));
    }
    path
      ..lineTo(w, surface(w))
      ..lineTo(w, h)
      ..close();
    final paint = Paint();
    if (fade) {
      paint.shader = SmoothFade.shader(
        state._fades[back ? 0 : 1],
        Rect.fromLTRB(0, base - lift - sim.amplitude * 1.5, w, h),
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        color: color,
        curve: FadeCurve.settle(alpha, 0),
        devicePixelRatio: devicePixelRatio,
      );
    } else {
      paint.color = color.withValues(alpha: alpha);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_LiquidPainter old) =>
      old.color != color ||
      old.shapeColor != shapeColor ||
      old.mirror != mirror ||
      old.fade != fade ||
      old.shapesTop != shapesTop ||
      old.rtl != rtl ||
      old.devicePixelRatio != devicePixelRatio ||
      old.state != state;
}

// наборы фигур панели, меняются раз в полминуты. top и side живут вокруг кнопки, low у воды.
// по пять, у воды по две: с метриками остаётся три
final panelLiquidShapes = [
  [
    LiquidShapeSpot(MaterialShapes.sunny,
        anchor: LiquidShapeAnchor.top, x: 0.40, y: 14, size: 26, degrees: 17),
    LiquidShapeSpot(MaterialShapes.flower,
        anchor: LiquidShapeAnchor.top, x: 0.08, y: 16, size: 22, degrees: -11),
    LiquidShapeSpot(MaterialShapes.clover4Leaf,
        anchor: LiquidShapeAnchor.side, x: 16, y: 52, size: 16, degrees: 29),
    LiquidShapeSpot(MaterialShapes.cookie7Sided,
        anchor: LiquidShapeAnchor.low, x: 0.50, y: 56, size: 20, degrees: 15),
    LiquidShapeSpot(MaterialShapes.gem,
        anchor: LiquidShapeAnchor.low, x: 0.30, y: 62, size: 14, degrees: 24),
  ],
  [
    LiquidShapeSpot(MaterialShapes.cookie9Sided,
        anchor: LiquidShapeAnchor.top, x: 0.30, y: 14, size: 24, degrees: 10),
    LiquidShapeSpot(MaterialShapes.gem,
        anchor: LiquidShapeAnchor.top, x: 0.56, y: 18, size: 16, degrees: 20),
    LiquidShapeSpot(MaterialShapes.softBurst,
        anchor: LiquidShapeAnchor.side, x: 16, y: 118, size: 18),
    LiquidShapeSpot(MaterialShapes.puffy,
        anchor: LiquidShapeAnchor.low, x: 0.42, y: 56, size: 24, degrees: -15),
    LiquidShapeSpot(MaterialShapes.clover4Leaf,
        anchor: LiquidShapeAnchor.low, x: 0.22, y: 60, size: 14, degrees: -20),
  ],
  [
    LiquidShapeSpot(MaterialShapes.flower,
        anchor: LiquidShapeAnchor.top, x: 0.20, y: 15, size: 24),
    LiquidShapeSpot(MaterialShapes.clover4Leaf,
        anchor: LiquidShapeAnchor.top, x: 0.52, y: 13, size: 18, degrees: 35),
    LiquidShapeSpot(MaterialShapes.pill,
        anchor: LiquidShapeAnchor.side, x: 16, y: 86, size: 18, degrees: 46),
    LiquidShapeSpot(MaterialShapes.sunny,
        anchor: LiquidShapeAnchor.low, x: 0.56, y: 56, size: 22, degrees: -10),
    LiquidShapeSpot(MaterialShapes.cookie9Sided,
        anchor: LiquidShapeAnchor.low, x: 0.36, y: 62, size: 15, degrees: 8),
  ],
];

// легаси: по бокам от кнопки в центре, три с одной стороны и две с другой
final legacyLiquidShapes = [
  LiquidShapeSpot(MaterialShapes.sunny,
      anchor: LiquidShapeAnchor.top, x: 0.14, y: 8, size: 26, degrees: 17),
  LiquidShapeSpot(MaterialShapes.clover4Leaf,
      anchor: LiquidShapeAnchor.top, x: 0.27, y: 66, size: 16, degrees: 29),
  LiquidShapeSpot(MaterialShapes.puffy,
      anchor: LiquidShapeAnchor.top, x: 0.10, y: 116, size: 22, degrees: -15),
  LiquidShapeSpot(MaterialShapes.flower,
      anchor: LiquidShapeAnchor.top, x: 0.84, y: 28, size: 24, degrees: -11),
  LiquidShapeSpot(MaterialShapes.cookie7Sided,
      anchor: LiquidShapeAnchor.top, x: 0.76, y: 106, size: 18, degrees: 15),
];
