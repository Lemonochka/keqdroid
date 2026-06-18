import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Плавная прокрутка колёсиком мыши на десктопе.
///
/// По умолчанию Flutter на каждый «щелчок» колеса мгновенно перепрыгивает
/// (`forcePixels`) — получается «лесенка». Здесь прокрутка колёсиком ведётся
/// одной непрерывной активностью, которая каждый кадр экспоненциально
/// подтягивает позицию к цели. Цель можно дополнять новыми щелчками на лету —
/// поэтому и обычное колесо (редкие крупные дельты), и «умные»/тачпадные мыши
/// (поток мелких дельт каждый кадр) скроллятся плавно, без рывков ползунка.
const _desktopPlatforms = {
  TargetPlatform.windows,
  TargetPlatform.linux,
  TargetPlatform.macOS,
};

bool get _isDesktopPlatform =>
    !kIsWeb && _desktopPlatforms.contains(defaultTargetPlatform);

// Постоянная времени сглаживания (сек). Чем меньше — тем «резче» догоняет цель.
const double _kSmoothTau = 0.09;

class SmoothScrollController extends ScrollController {
  SmoothScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
  });

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _SmoothScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }
}

class _SmoothScrollPosition extends ScrollPositionWithSingleContext {
  _SmoothScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  // Активность плавного колеса, пока она живёт. Обнуляется, когда её сменяет
  // любая другая активность (драг, баллистика, idle) — см. onDisposed.
  _SmoothWheelActivity? _wheel;

  @override
  void pointerScroll(double delta) {
    if (delta == 0.0) return;

    updateUserScrollDirection(
      delta > 0.0 ? ScrollDirection.reverse : ScrollDirection.forward,
    );

    if (_wheel != null) {
      _wheel!.addDelta(delta);
    } else {
      final activity = _SmoothWheelActivity(
        this,
        initialDelta: delta,
        vsync: context.vsync,
        onDisposed: () => _wheel = null,
      );
      beginActivity(activity);
      _wheel = activity;
    }
  }
}

/// Непрерывная активность: каждый кадр применяет долю накопленного «остатка»
/// прокрутки относительно текущей позиции (экспоненциальное сглаживание, не
/// зависящее от частоты кадров). Относительный остаток, а не абсолютная цель —
/// чтобы в ленивых списках с разной высотой элементов уточнение
/// `maxScrollExtent` на лету не дёргало позицию.
class _SmoothWheelActivity extends ScrollActivity {
  _SmoothWheelActivity(
    super.delegate, {
    required double initialDelta,
    required TickerProvider vsync,
    required this.onDisposed,
  }) : _remaining = initialDelta {
    _ticker = vsync.createTicker(_tick)..start();
  }

  final VoidCallback onDisposed;
  late final Ticker _ticker;

  _SmoothScrollPosition get _position => delegate as _SmoothScrollPosition;

  double _remaining;
  Duration _lastElapsed = Duration.zero;
  double _velocity = 0.0;

  void addDelta(double delta) => _remaining += delta;

  void _tick(Duration elapsed) {
    final double dt =
        (elapsed - _lastElapsed).inMicroseconds / Duration.microsecondsPerSecond;
    _lastElapsed = elapsed;
    if (dt <= 0) return;

    if (_remaining.abs() < 0.5) {
      _velocity = 0.0;
      delegate.goBallistic(0.0); // завершает активность -> idle
      return;
    }

    double step = _remaining * (1 - math.exp(-dt / _kSmoothTau));
    if (step.abs() > _remaining.abs()) step = _remaining; // не перешагиваем остаток
    _remaining -= step;
    _velocity = step / dt;

    final double overscroll = delegate.setPixels(_position.pixels + step);
    if (overscroll.abs() > 0.5) {
      // Упёрлись в край списка — гасим остаток, чтобы не «висеть» на границе.
      _remaining = 0.0;
      delegate.goBallistic(0.0);
    }
  }

  @override
  bool get shouldIgnorePointer => false;

  @override
  bool get isScrolling => true;

  @override
  double get velocity => _velocity;

  @override
  void dispose() {
    onDisposed();
    _ticker.dispose();
    super.dispose();
  }
}

/// Создаёт скролл-контроллер и отдаёт его в [builder], чтобы навесить на
/// конкретный скролл-вью. На десктопе это [SmoothScrollController] (плавное
/// колесо), на остальных платформах — `null` (поведение по умолчанию,
/// никакого контроллера принудительно не навязываем).
///
/// Контроллер навешивается ровно на один список — вложенные скроллы (например
/// `GridView` внутри `ListView`) не затрагиваются, поэтому конфликтов
/// «несколько позиций на одном контроллере» не возникает.
class SmoothScroll extends StatefulWidget {
  final Widget Function(BuildContext context, ScrollController? controller)
      builder;

  const SmoothScroll({super.key, required this.builder});

  @override
  State<SmoothScroll> createState() => _SmoothScrollState();
}

class _SmoothScrollState extends State<SmoothScroll> {
  SmoothScrollController? _controller;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isDesktopPlatform) return widget.builder(context, null);

    _controller ??= SmoothScrollController();
    return widget.builder(context, _controller);
  }
}
