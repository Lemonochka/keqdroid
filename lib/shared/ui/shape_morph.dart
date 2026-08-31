import 'dart:async';
import 'dart:math' as math;

import 'package:androidx_graphics_shapes/material_shapes.dart';
import 'package:androidx_graphics_shapes/shapes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// Цикл морфинга фигур M3 Expressive — общий механизм для индикатора загрузки
/// и для формы кнопки подключения.
///
/// Повторяет `LoadingIndicator` из androidx (material3), включая числа — иначе
/// получается «похоже, но не то»:
///
///  * последовательность из семи фигур — `IndeterminateIndicatorPolygons`;
///  * `MorphIntervalMillis = 650` — шаг морфинга. Пружина добегает до конца
///    заметно раньше, и остаток интервала фигура СТОИТ. Эта пауза и делает
///    движение узнаваемым: оно щёлкает формами, а не перетекает без остановки;
///  * пружина `dampingRatio = 0.6, stiffness = 200` — недодемпфированная, с
///    перелётом. Обычная кривая ускорения даёт ту же траекторию без отдачи, и
///    как раз она читается «не как в материале»;
///  * `GlobalRotationDurationMillis = 4666` — полный оборот, ЛИНЕЙНО и
///    независимо от морфинга. Периоды намеренно не кратны друг другу (4666
///    против 7×650), поэтому рисунок движения не повторяется покадрово;
///  * итоговый угол — `progress * 90 + шаги по 90° + глобальное вращение`
///    (`QuarterRotation`): каждая смена формы доворачивает фигуру на четверть.
class ShapeMorphCycle extends ChangeNotifier {
  ShapeMorphCycle({required TickerProvider vsync}) {
    _morph = AnimationController.unbounded(vsync: vsync)
      ..addListener(notifyListeners);
    _rotation = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: _globalRotationDurationMillis),
    )
      ..addListener(notifyListeners)
      ..repeat();
    _step();
    _timer = Timer.periodic(
      const Duration(milliseconds: _morphIntervalMillis),
      (_) => _step(),
    );
  }

  static const _morphIntervalMillis = 650;
  static const _globalRotationDurationMillis = 4666;
  static const _quarterRotation = 90.0;

  /// Официальная последовательность M3 Expressive.
  static final List<RoundedPolygon> shapes = [
    MaterialShapes.softBurst,
    MaterialShapes.cookie9Sided,
    MaterialShapes.pentagon,
    MaterialShapes.pill,
    MaterialShapes.sunny,
    MaterialShapes.cookie4Sided,
    MaterialShapes.oval,
  ];

  /// Морфы считаются ОДИН раз на всё приложение, и это не преждевременная
  /// оптимизация: конструктор [Morph] сопоставляет кривые двух фигур (`match`),
  /// то есть перебор с поиском лучшего соответствия. Строить его в `build` или
  /// в пейнтере значило бы гонять этот перебор 60 раз в секунду.
  ///
  /// Список замкнут в кольцо: последняя фигура перетекает обратно в первую.
  static final List<Morph> morphs = [
    for (var i = 0; i < shapes.length; i++)
      Morph(shapes[i], shapes[(i + 1) % shapes.length]),
  ];

  static final _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 200,
    ratio: 0.6,
  );

  /// Пружине нужен unbounded-контроллер: она перелетает за 1.0 и возвращается,
  /// а обычный AnimationController зажал бы значение в [0, 1] и съел бы отдачу.
  late final AnimationController _morph;
  late final AnimationController _rotation;
  Timer? _timer;
  int _index = 0;
  double _stepAngle = 0;

  /// Морф «текущая фигура → круг» для завершения цикла, см. [settle].
  Morph? _settleMorph;

  /// Идёт ли доводка до круга.
  bool get isSettling => _settleMorph != null;

  /// Текущая пара фигур.
  Morph get morph => _settleMorph ?? morphs[_index];

  /// Положение между ними; перелетает за 1.0 — так работает пружина.
  double get progress => _morph.value;

  double get degrees =>
      progress * _quarterRotation + _stepAngle + _rotation.value * 360;

  /// Довести фигуру до круга и остановиться.
  ///
  /// Без этого цикл обрывался на произвольной форме: подключение заканчивалось,
  /// и кнопка скачком превращалась из клевера обратно в круг. Здесь она
  /// доезжает туда той же пружиной, что и все остальные переходы.
  ///
  /// Морф берётся от КОНЕЧНОЙ фигуры текущей пары, а не от промежуточной формы:
  /// пружина почти всё время интервала стоит на завершённом переходе, поэтому в
  /// момент вызова кадр совпадает с ней с точностью до отдачи.
  ///
  /// [onDone] зовётся, когда доводка закончилась — по нему владелец убирает
  /// цикл и возвращает обычную круглую форму.
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
        // TickerFuture завершается и когда анимацию ПЕРЕБИЛИ (различает только
        // `orCancel`). Без этой проверки отменённая доводка всё равно звала бы
        // onDone — то есть владелец убирал бы цикл, который уже снова крутится.
        if (!isSettling) return;
        onDone();
      });
  }

  /// Отменить доводку и вернуться к бесконечному циклу.
  ///
  /// Нужно, когда работа возобновилась, пока фигура ехала к кругу. На первом
  /// подключении так и происходит: система показывает диалог разрешения VPN,
  /// статус на этот момент проваливается из «подключается» и тут же
  /// возвращается. Без возобновления цикл добегал доводку до конца и умирал —
  /// фигур на кнопке не было вовсе до самого конца подключения.
  void resume() {
    if (!isSettling) return;
    _settleMorph = null;
    _rotation.repeat();
    _step();
    _timer = Timer.periodic(
      const Duration(milliseconds: _morphIntervalMillis),
      (_) => _step(),
    );
  }

  static final _circle = MaterialShapes.circle;

  /// Доводка идёт кривой, а НЕ пружиной, и это принципиально.
  ///
  /// Критически задемпфированная пружина подходит к цели асимптотически:
  /// визуально она приезжала за пару десятых, а `isDone` наступал сильно
  /// позже — фигура успевала стать кругом и потом ещё около секунды просто
  /// стояла, прежде чем уступить место иконке. Снаружи это выглядело как
  /// зависание после успешного подключения.
  ///
  /// Перелёт здесь и не нужен: круг — конечная форма кнопки, дрогнуть в самом
  /// конце он не должен.
  static const _settleDuration = Duration(milliseconds: 320);

  /// Следующая пара фигур: прогресс с нуля, доворот на четверть.
  void _step() {
    _index = (_index + 1) % morphs.length;
    _stepAngle = (_stepAngle + _quarterRotation) % 360;
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

/// Рисует текущую фигуру [ShapeMorphCycle] заливкой.
///
/// Общий для индикатора загрузки и для кнопки подключения: у M3E это один и тот
/// же компонент, «contained loading indicator» — круглая подложка и фигура
/// внутри неё, отличается только размер.
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
    // Фигуры нормализованы в квадрат (0,0)–(1,1), поэтому масштаб — сторона
    // виджета, ужатая до активного размера, а сдвиг возвращает её в центр.
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

