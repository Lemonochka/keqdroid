import 'dart:math';
import 'dart:ui' as ui;

import 'package:androidx_graphics_shapes/material_shapes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/shared/ui/liquid_wave.dart';
import 'package:keqdroid/shared/ui/smooth_fade.dart';

const _frame = 1 / 60;

const _panel = LiquidLevels(idle: 12, busy: 44, quiet: 36, loud: 44, inDp: true);

void _run(LiquidWaveSim sim, double seconds, LiquidPhase phase, double load) {
  for (var t = 0.0; t < seconds; t += _frame) {
    sim.step(_frame, phase, _panel, load);
  }
}

List<double> _profile(LiquidWaveSim sim) =>
    [for (var x = 0.0; x <= 400; x += 10) sim.displacement(x)];

double _profileGap(List<double> a, List<double> b) {
  var gap = 0.0;
  for (var i = 0; i < a.length; i++) {
    gap = max(gap, (a[i] - b[i]).abs());
  }
  return gap;
}

void main() {
  group('трафик чуть поднимает воду, плавно', () {
    test('при полной загрузке вода выше и волна крупнее, но без перебора', () {
      final calm = LiquidWaveSim()..snap(LiquidPhase.active, _panel, 0.1);
      final busy = LiquidWaveSim()..snap(LiquidPhase.active, _panel, 0.1);
      _run(calm, 10, LiquidPhase.active, 0.1);
      _run(busy, 10, LiquidPhase.active, 0.9);
      expect(busy.level - calm.level, inInclusiveRange(5, 10));
      expect(busy.amplitude - calm.amplitude, inInclusiveRange(1.5, 3));
    });

    test('фоновый трафик воду не трогает, видео поднимает примерно наполовину',
        () {
      expect(LiquidWaveSim.loadFor(0), 0);
      expect(LiquidWaveSim.loadFor(2 * 1024), 0);
      expect(LiquidWaveSim.loadFor(30 * 1024), 0);
      expect(LiquidWaveSim.loadFor(600 * 1024), inInclusiveRange(0.4, 0.65));
      expect(LiquidWaveSim.loadFor(8 * 1024 * 1024), 1);
      expect(LiquidWaveSim.loadFor(50 * 1024 * 1024), 1);
    });

    test('скачок трафика за один кадр почти не двигает воду', () {
      final sim = LiquidWaveSim()..snap(LiquidPhase.active, _panel, 0);
      final level = sim.level;
      final amplitude = sim.amplitude;
      sim.step(_frame, LiquidPhase.active, _panel, 1);
      expect(sim.level - level, lessThan(0.2));
      expect(sim.amplitude - amplitude, lessThan(0.1));

      _run(sim, 10, LiquidPhase.active, 1);
      expect(sim.level, closeTo(44, 1));
      expect(sim.amplitude, closeTo(6.2, 0.4));
    });

    test('трафик, скачущий каждую секунду, не раскачивает воду', () {
      final sim = LiquidWaveSim()..snap(LiquidPhase.active, _panel, 0.5);
      var lowLevel = double.infinity;
      var highLevel = 0.0;
      for (var second = 0; second < 20; second++) {
        final load = second.isEven ? 0.2 : 0.8;
        for (var f = 0; f < 60; f++) {
          sim.step(_frame, LiquidPhase.active, _panel, load);
          lowLevel = min(lowLevel, sim.level);
          highLevel = max(highLevel, sim.level);
        }
      }
      // без сглаживания уровень прыгал бы на 4,8 dp каждую секунду
      expect(highLevel - lowLevel, lessThan(1.5));
    });
  });

  group('смена состояния без рывков', () {
    test('из «подключения» в «подключено» вода едет, а не прыгает', () {
      final sim = LiquidWaveSim()..snap(LiquidPhase.busy, _panel, 0.45);
      final level = sim.level;
      final surface = sim.displacement(120);
      sim.step(_frame, LiquidPhase.active, _panel, 0.45);
      expect((sim.level - level).abs(), lessThan(0.5));
      expect((sim.displacement(120) - surface).abs(), lessThan(0.6));

      _run(sim, 10, LiquidPhase.active, 0.45);
      expect(sim.level, closeTo(36 + 8 * 0.45, 0.5));
    });

    test('после нажатия вода растёт плавно, без скачка к цели', () {
      final sim = LiquidWaveSim()..snap(LiquidPhase.idle, _panel, 0.45);
      final steps = <double>[];
      var last = sim.level;
      for (var f = 0; f < 120; f++) {
        sim.step(_frame, LiquidPhase.busy, _panel, 0.45);
        steps.add(sim.level - last);
        last = sim.level;
      }
      expect(steps.reduce(max), lessThan(1.5));
      expect(sim.level, greaterThan(35));
    });
  });

  group('вода поднимается от кнопки', () {
    LiquidWaveSim tapped(double seconds) {
      final sim = LiquidWaveSim()
        ..splashAt = 0.76
        ..snap(LiquidPhase.idle, _panel, 0);
      _run(sim, seconds, LiquidPhase.busy, 0);
      return sim;
    }

    test('сразу после нажатия под кнопкой вода выше, чем у дальнего края', () {
      final sim = tapped(0.3);
      expect(sim.levelAt(0.76) - sim.levelAt(0), greaterThan(8));
      expect(sim.levelAt(0.76), greaterThan(sim.levelAt(0.4)));
    });

    test('через пару секунд вода ровная по всей ширине', () {
      final sim = tapped(3);
      expect((sim.levelAt(0) - sim.levelAt(0.76)).abs(), lessThan(0.5));
      expect((sim.levelAt(1) - sim.levelAt(0.76)).abs(), lessThan(0.5));
    });

    test('вода чуть перелетает и садится', () {
      final sim = LiquidWaveSim()
        ..splashAt = 0.76
        ..snap(LiquidPhase.idle, _panel, 0);
      var peak = 0.0;
      for (var t = 0.0; t < 4; t += _frame) {
        sim.step(_frame, LiquidPhase.busy, _panel, 0);
        peak = max(peak, sim.level);
      }
      expect(peak - 44, inInclusiveRange(2, 8));
      expect(sim.level, closeTo(44, 0.3));
    });

    testWidgets('кнопка справа, а в RTL слева', (tester) async {
      final clock = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(seconds: 2),
      );
      addTearDown(clock.dispose);
      for (final (direction, expected) in [
        (TextDirection.ltr, closeTo(0.76, 0.01)),
        (TextDirection.rtl, closeTo(0.24, 0.01)),
      ]) {
        await tester.pumpWidget(
          Directionality(
            textDirection: direction,
            child: Center(
              child: SizedBox(
                width: 380,
                height: 200,
                child: LiquidWave(
                  key: ValueKey(direction),
                  clock: clock,
                  phase: LiquidPhase.idle,
                  levels: _panel,
                  load: 0,
                  color: Colors.pink,
                  splashFromEnd: 92,
                ),
              ),
            ),
          ),
        );
        final state = tester.state<LiquidWaveState>(find.byType(LiquidWave));
        expect(state.sim.splashAt, expected);
      }
    });
  });

  test('в подключённом состоянии волна заметная, а не рябь', () {
    final sim = LiquidWaveSim()..snap(LiquidPhase.active, _panel, 0.45);
    final profile = _profile(sim);
    expect(profile.reduce(max) - profile.reduce(min), greaterThan(8));
  });

  test('без трафика рисунок не повторяется через период гребня', () {
    final sim = LiquidWaveSim()..snap(LiquidPhase.active, _panel, 0);
    final start = _profile(sim);
    // гребень проходит полный круг за 2π / (1.0 * speed)
    _run(sim, 2 * pi / sim.speed, LiquidPhase.active, 0);
    expect(_profileGap(start, _profile(sim)), greaterThan(0.3));
  });

  test('гребни чуть разной высоты, но не вразнобой', () {
    final sim = LiquidWaveSim()..snap(LiquidPhase.active, _panel, 0);
    _run(sim, 3, LiquidPhase.active, 0);
    final crests = <double>[];
    for (var x = 1.0; x < 1060; x++) {
      final y = sim.displacement(x);
      if (y > sim.displacement(x - 1) && y >= sim.displacement(x + 1)) {
        crests.add(y);
      }
    }
    final ratio = crests.reduce(max) / crests.reduce(min);
    expect(ratio, inInclusiveRange(1.1, 1.6));
  });

  test('фигурок в наборе нечётное число, и когда у воды их прячут метрики',
      () {
    for (final preset in [...panelLiquidShapes, ...legacyLiquidShapes]) {
      expect(preset.length.isOdd, isTrue);
      final aboveMetrics =
          preset.where((s) => s.anchor != LiquidShapeAnchor.low).length;
      expect(aboveMetrics.isOdd, isTrue);
    }
  });

  testWidgets('свес ниже шапки: поверхность на месте, к концу вода гаснет', (
    tester,
  ) async {
    await tester.runAsync(SmoothFade.load);
    final clock = AnimationController(
      vsync: const TestVSync(),
      duration: const Duration(seconds: 2),
    );
    addTearDown(clock.dispose);
    const legacy = LiquidLevels(idle: 0.08, busy: 0.36, quiet: 0.3, loud: 0.36);

    Future<List<double>> column(double overhang) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 120,
                height: 200 + overhang,
                child: ColoredBox(
                  color: Colors.black,
                  child: LiquidWave(
                    clock: clock,
                    phase: LiquidPhase.active,
                    levels: legacy,
                    load: 0,
                    color: Colors.white,
                    fade: true,
                    overhang: overhang,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final data = await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        return bytes!;
      });
      return [
        for (var y = 0; y < 200 + overhang; y++)
          data!.getUint8((y * 120 + 60) * 4).toDouble(),
      ];
    }

    final plain = await column(0);
    final hanging = await column(48);
    int surface(List<double> c) => c.indexWhere((v) => v > 0);
    expect((surface(hanging) - surface(plain)).abs(), lessThanOrEqualTo(2));
    expect(hanging[199], greaterThan(4));
    expect(hanging.last, lessThan(2));
  });

  testWidgets('наборы фигур сменяются раз в полминуты', (tester) async {
    final clock = AnimationController(
      vsync: const TestVSync(),
      duration: const Duration(seconds: 2),
    );
    addTearDown(clock.dispose);
    final presets = [
      [
        LiquidShapeSpot(MaterialShapes.sunny,
            anchor: LiquidShapeAnchor.top, x: 0.5, y: 10, size: 20),
      ],
      [
        LiquidShapeSpot(MaterialShapes.flower,
            anchor: LiquidShapeAnchor.top, x: 0.5, y: 10, size: 20),
      ],
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 300,
          height: 160,
          child: LiquidWave(
            clock: clock,
            phase: LiquidPhase.active,
            levels: _panel,
            load: 0.45,
            color: Colors.pink,
            shapePresets: presets,
            shapeColor: Colors.pink,
          ),
        ),
      ),
    );
    final state = tester.state<LiquidWaveState>(find.byType(LiquidWave));
    expect(state.shownPreset, 0);

    await tester.pump(const Duration(seconds: 31));
    await tester.pump(const Duration(seconds: 2));
    expect(state.shownPreset, 1);

    await tester.pump(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 2));
    expect(state.shownPreset, 0);
  });
}
