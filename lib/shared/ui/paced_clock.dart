import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

// часы бесконечной анимации: не чаще 60 к/с на любом экране и тикают в кадрах, которые рисуются и так.
// Impeller растеризует весь кадр заново, поэтому вода по vsync на 120 Гц стоила вдвое больше, чем на Pixel 6a
class PacedClock extends ChangeNotifier {
  int? _callbackId;
  Timer? _timer;
  bool _running = false;
  bool _muted = false;
  Duration? _start;
  Duration? _lastTick;
  Duration? _lastFrame;
  Duration? _lastProbe;
  Duration? _elapsed;

  Duration _vsync = _assumedVsync;
  Duration? _windowStart;
  Duration? _windowMin;

  static const _assumedVsync = Duration(microseconds: 16667);
  // дисплеев быстрее 240 Гц нет, а pump в тестах шагает как угодно
  static const _minVsync = Duration(milliseconds: 4);
  static const _vsyncWindow = Duration(seconds: 3);
  static const _probeEvery = Duration(seconds: 2);

  Duration? get lastElapsedDuration => _elapsed;

  bool get isAnimating => _running;

  @visibleForTesting
  Duration get vsync => _vsync;

  bool get muted => _muted;
  set muted(bool value) {
    if (value == _muted) return;
    _muted = value;
    _sync();
  }

  void repeat() {
    if (_running) return;
    _running = true;
    _start = null;
    _lastTick = null;
    _sync();
  }

  void stop() {
    if (!_running) return;
    _running = false;
    _elapsed = null;
    _sync();
  }

  @override
  void dispose() {
    _running = false;
    _sync();
    super.dispose();
  }

  void _sync() {
    if (_running && !_muted) {
      FramePace.instance._attach(this);
      _lastFrame = null;
      _await(force: true);
    } else {
      FramePace.instance._detach(this);
      final id = _callbackId;
      if (id != null) SchedulerBinding.instance.cancelFrameCallbackWithId(id);
      _callbackId = null;
      _timer?.cancel();
      _timer = null;
    }
  }

  void _await({required bool force}) {
    if (_callbackId != null) {
      if (force) SchedulerBinding.instance.scheduleFrame();
      return;
    }
    _callbackId = SchedulerBinding.instance
        .scheduleFrameCallback(_onFrame, scheduleNewFrame: force);
  }

  void _onFrame(Duration stamp) {
    _callbackId = null;
    _measure(stamp);
    final start = _start ??= stamp;
    final stride = FramePace.instance.strideFor(_vsync);
    // полкадра запаса: таймер будит до нужного vsync, а не после него
    final due = _vsync * (stride - 0.5);
    final last = _lastTick;
    if (last != null && stamp - last < due) {
      _await(force: false);
      _timer ??= Timer(due - (stamp - last), _wake);
      return;
    }

    _lastTick = stamp;
    _elapsed = stamp - start;
    notifyListeners();
    if (!_running || _muted) return;

    _timer?.cancel();
    _timer = null;
    if (stride == 1) {
      _await(force: true);
      return;
    }
    _await(force: false);
    _timer = Timer(due, _wake);
    // кадр сразу следом раз в пару секунд: иначе настоящий период vsync не увидеть
    final probe = _lastProbe;
    if (probe == null || stamp - probe >= _probeEvery) {
      _lastProbe = stamp;
      SchedulerBinding.instance.scheduleFrame();
    }
  }

  void _wake() {
    _timer = null;
    if (_running && !_muted) SchedulerBinding.instance.scheduleFrame();
  }

  // вниз сразу, вверх по минимуму за окно: LTPO-экран сбрасывает частоту, когда кадров мало
  void _measure(Duration stamp) {
    final prev = _lastFrame;
    _lastFrame = stamp;
    if (prev == null) return;
    final gap = stamp - prev;
    if (gap < _minVsync) return;
    if (gap < _vsync) _vsync = gap;
    final windowMin = _windowMin;
    if (windowMin == null || gap < windowMin) _windowMin = gap;
    final windowStart = _windowStart ??= stamp;
    if (stamp - windowStart >= _vsyncWindow) {
      _vsync = _windowMin!;
      _windowMin = null;
      _windowStart = stamp;
    }
  }
}

class FramePace {
  FramePace._();

  static final instance = FramePace._();

  final _clocks = <PacedClock>{};
  FramePaceGovernor _governor = FramePaceGovernor();

  int get level => _governor.level;

  // на 90 Гц шаг 1: 45 к/с заметно хуже 60, а на 144 шаг 2 даёт 72
  int strideFor(Duration vsync) => math.max(
        1,
        (_governor.frameInterval.inMicroseconds / vsync.inMicroseconds + 0.25)
            .floor(),
      );

  @visibleForTesting
  void reset([FramePaceGovernor? governor]) {
    _governor = governor ?? FramePaceGovernor();
  }

  void _attach(PacedClock clock) {
    if (_clocks.add(clock) && _clocks.length == 1) {
      SchedulerBinding.instance.addTimingsCallback(_onTimings);
    }
  }

  void _detach(PacedClock clock) {
    if (_clocks.remove(clock) && _clocks.isEmpty) {
      SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    }
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _governor.addFrame(
        at: Duration(microseconds: t.timestampInMicroseconds(FramePhase.vsyncStart)),
        build: t.buildDuration,
        raster: t.rasterDuration,
      );
    }
  }
}

// телефон не успевает: три секунды подряд четверть кадров не влезла в бюджет. тогда 30 к/с,
// обратно после спокойных 30 с, а если снова сорвался в течение минуты, ждём вдвое дольше
class FramePaceGovernor {
  int _level = 0;
  Duration? _windowStart;
  int _frames = 0;
  int _late = 0;
  int _badWindows = 0;
  int _calmWindows = 0;
  int _calmNeeded = _firstCalm;
  Duration? _recoveredAt;

  static const _smooth = Duration(microseconds: 16667);
  static const _relieved = Duration(microseconds: 33333);
  static const _window = Duration(seconds: 1);
  static const _minFrames = 10;
  static const _badRun = 3;
  static const _firstCalm = 30;
  static const _maxCalm = 480;
  static const _relapse = Duration(minutes: 1);

  int get level => _level;

  Duration get frameInterval => _level == 0 ? _smooth : _relieved;

  @visibleForTesting
  int get calmNeeded => _calmNeeded;

  void addFrame({
    required Duration at,
    required Duration build,
    required Duration raster,
  }) {
    final start = _windowStart ??= at;
    if (at - start >= _window) {
      _closeWindow(at);
      _windowStart = at;
    }
    _frames++;
    final budget = frameInterval;
    if (build > budget || raster > budget) _late++;
  }

  void _closeWindow(Duration at) {
    final frames = _frames;
    final late = _late;
    _frames = 0;
    _late = 0;
    if (frames < _minFrames) return;
    final share = late / frames;
    if (_level == 0) {
      _badWindows = share >= 0.25 ? _badWindows + 1 : 0;
      if (_badWindows < _badRun) return;
      final recovered = _recoveredAt;
      _calmNeeded = recovered != null && at - recovered < _relapse
          ? math.min(_calmNeeded * 2, _maxCalm)
          : _firstCalm;
      _level = 1;
      _badWindows = 0;
      _calmWindows = 0;
    } else {
      _calmWindows = share < 0.05 ? _calmWindows + 1 : 0;
      if (_calmWindows < _calmNeeded) return;
      _level = 0;
      _calmWindows = 0;
      _recoveredAt = at;
    }
  }
}
