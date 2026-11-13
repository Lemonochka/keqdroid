import 'dart:async';
import 'dart:math' as math;

import 'package:androidx_graphics_shapes/material_shapes.dart';
import 'package:androidx_graphics_shapes/shapes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

class ShapeMorphCycle extends ChangeNotifier {
  ShapeMorphCycle({required TickerProvider vsync}) {
    _morph = AnimationController.unbounded(vsync: vsync)
      ..addListener(notifyListeners);
    _rotation = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: _globalRotationDurationMillis),
    )..addListener(notifyListeners);
    _start();
  }

  static const _morphIntervalMillis = 650;
  static const _globalRotationDurationMillis = 4666;
  static const _quarterRotation = 90.0;

  static final List<RoundedPolygon> shapes = [
    MaterialShapes.softBurst,
    MaterialShapes.cookie9Sided,
    MaterialShapes.pentagon,
    MaterialShapes.pill,
    MaterialShapes.sunny,
    MaterialShapes.cookie4Sided,
    MaterialShapes.oval,
  ];

  // Morph сопоставляет кривые перебором, строить его в build или пейнтере значит 60 раз в секунду
  static final List<Morph> morphs = [
    for (var i = 0; i < shapes.length; i++)
      Morph(shapes[i], shapes[(i + 1) % shapes.length]),
  ];

  static final _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 200,
    ratio: 0.6,
  );

  // unbounded: пружина перелетает за 1.0, обычный контроллер срезал бы отдачу
  late final AnimationController _morph;
  late final AnimationController _rotation;
  Timer? _timer;
  int _index = 0;
  double _stepAngle = 0;

  double _rotationOffset = 0;

  // время планировщика: по нему тикают контроллеры, и в тестах оно идёт по pump
  static Duration get _now =>
      SchedulerBinding.instance.currentSystemFrameTimeStamp;

  static int _stepsNow(Duration now) =>
      now.inMilliseconds ~/ _morphIntervalMillis;

  // округляем к границе: часы планировщика отстают на кадр, и floor дал бы прежний шаг
  static int _stepsAtBoundary(Duration now) =>
      (now.inMilliseconds + _morphIntervalMillis ~/ 2) ~/ _morphIntervalMillis;

  Morph? _settleMorph;

  bool get isSettling => _settleMorph != null;

  Morph get morph => _settleMorph ?? morphs[_index];

  double get progress => _morph.value;

  double get degrees =>
      progress * _quarterRotation +
      _stepAngle +
      (_rotation.value + _rotationOffset) * 360;

  void settle({required VoidCallback onDone}) {
    if (isSettling) return;
    _timer?.cancel();
    _timer = null;
    _settleMorph = Morph(shapes[(_index + 1) % shapes.length], _circle);
    _rotation.stop();
    _morph
      ..value = 0
      ..animateTo(
        1,
        duration: _settleDuration,
        curve: Curves.easeOutCubic,
      ).whenComplete(() {
        // TickerFuture завершается и при отмене, без проверки onDone убрал бы уже ожившую фигуру
        if (!isSettling) return;
        onDone();
      });
  }

  void resume() {
    if (!isSettling) return;
    _settleMorph = null;
    if (!_asleep) _start();
  }

  var _asleep = false;

  // невидимый индикатор спит: таймер шага будил процесс и на чужой вкладке, и в свёрнутом приложении
  set asleep(bool value) {
    if (value == _asleep) return;
    _asleep = value;
    if (isSettling) return;
    if (value) {
      _timer?.cancel();
      _timer = null;
      _rotation.stop();
    } else {
      _start();
    }
  }

  static final _circle = MaterialShapes.circle;

  // кривой, а не пружиной: критическая пружина доезжает асимптотически, и isDone наступал на секунду позже
  static const _settleDuration = Duration(milliseconds: 320);

  // фаза от общих часов: ленивые тайлы умирают вместе с циклом, и вернувшийся в кадр откатывал бы анимацию
  void _start() {
    final now = _now;
    final steps = _stepsNow(now);
    _index = steps % morphs.length;
    _stepAngle = (steps * _quarterRotation) % 360;
    _morph.value = 1;
    _rotationOffset =
        (now.inMilliseconds % _globalRotationDurationMillis) /
            _globalRotationDurationMillis;
    _rotation.repeat();
    final untilNext =
        _morphIntervalMillis - now.inMilliseconds % _morphIntervalMillis;
    _timer = Timer(Duration(milliseconds: untilNext), () {
      _step();
      _timer = Timer.periodic(
        const Duration(milliseconds: _morphIntervalMillis),
        (_) => _step(),
      );
    });
  }

  // номер шага от общих часов: periodic-таймеры расходятся, и соседи разъезжались бы по фигурам
  void _step() {
    final steps = _stepsAtBoundary(_now);
    _index = steps % morphs.length;
    _stepAngle = (steps * _quarterRotation) % 360;
    _morph
      ..value = 0
      ..animateWith(SpringSimulation(_spring, 0, 1, 0));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _morph.dispose();
    _rotation.dispose();
    super.dispose();
  }
}

class MorphPainter extends CustomPainter {
  const MorphPainter({
    required this.morph,
    required this.progress,
    required this.degrees,
    required this.scale,
    required this.color,
  });

  final Morph morph;
  final double progress;
  final double degrees;
  final double scale;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height) * scale;
    final dx = (size.width - side) / 2;
    final dy = (size.height - side) / 2;
    final path = morph.toPath(progress: progress).transform(
          (Matrix4.identity()
                ..translateByDouble(dx, dy, 0, 1)
                ..scaleByDouble(side, side, 1, 1))
              .storage,
        );
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..rotate(degrees * math.pi / 180)
      ..translate(-size.width / 2, -size.height / 2)
      ..drawPath(path, Paint()..color = color)
      ..restore();
  }

  @override
  bool shouldRepaint(MorphPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.degrees != degrees ||
      oldDelegate.color != color ||
      oldDelegate.scale != scale ||
      !identical(oldDelegate.morph, morph);
}

