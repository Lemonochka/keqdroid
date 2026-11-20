import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

const _desktopPlatforms = {
  TargetPlatform.windows,
  TargetPlatform.linux,
  TargetPlatform.macOS,
};

bool get _isDesktopPlatform =>
    !kIsWeb && _desktopPlatforms.contains(defaultTargetPlatform);

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

// относительный остаток, а не абсолютная цель: в ленивых списках maxScrollExtent уточняется на лету
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
        (elapsed - _lastElapsed).inMicroseconds /
        Duration.microsecondsPerSecond;
    _lastElapsed = elapsed;
    if (dt <= 0) return;

    if (_remaining.abs() < 0.5) {
      _velocity = 0.0;
      delegate.goBallistic(0.0);
      return;
    }

    double step = _remaining * (1 - math.exp(-dt / _kSmoothTau));
    if (step.abs() > _remaining.abs()) step = _remaining;
    _remaining -= step;
    _velocity = step / dt;

    final double overscroll = delegate.setPixels(_position.pixels + step);
    if (overscroll.abs() > 0.5) {
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
