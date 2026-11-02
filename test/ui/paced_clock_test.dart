import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/shared/ui/paced_clock.dart';

const _hz60 = Duration(microseconds: 16667);
const _hz120 = Duration(microseconds: 8333);

// секунды кадров, где каждый late-й из десяти не влез в бюджет 60 к/с
void _feed(
  FramePaceGovernor governor, {
  required Duration from,
  required int seconds,
  required int latePerTen,
}) {
  for (var i = 0; i < seconds * 60; i++) {
    governor.addFrame(
      at: from + _hz60 * i,
      build: const Duration(milliseconds: 4),
      raster: Duration(milliseconds: i % 10 < latePerTen ? 25 : 6),
    );
  }
}

Future<int> _ticksOver(
  WidgetTester tester,
  PacedClock clock, {
  required Duration frame,
  required int frames,
}) async {
  var ticks = 0;
  void count() => ticks++;
  clock.addListener(count);
  for (var i = 0; i < frames; i++) {
    await tester.pump(frame);
  }
  clock.removeListener(count);
  return ticks;
}

void main() {
  setUp(() => FramePace.instance.reset());

  group('FramePaceGovernor', () {
    test('ровные кадры оставляют 60 к/с', () {
      final governor = FramePaceGovernor();
      _feed(governor, from: Duration.zero, seconds: 10, latePerTen: 1);
      expect(governor.level, 0);
      expect(governor.frameInterval, _hz60);
    });

    test('две плохие секунды ещё терпим, три подряд сбавляют до 30', () {
      final governor = FramePaceGovernor();
      _feed(governor, from: Duration.zero, seconds: 3, latePerTen: 3);
      expect(governor.level, 0);

      _feed(governor, from: const Duration(seconds: 3), seconds: 2, latePerTen: 3);
      expect(governor.level, 1);
      expect(governor.frameInterval, const Duration(microseconds: 33333));
    });

    test('плохие секунды вразбивку не сбавляют', () {
      final governor = FramePaceGovernor();
      for (var s = 0; s < 12; s++) {
        _feed(
          governor,
          from: Duration(seconds: s),
          seconds: 1,
          latePerTen: s.isEven ? 4 : 0,
        );
      }
      expect(governor.level, 0);
    });

    test('после 30 спокойных секунд обратно, срыв за минуту удваивает ожидание', () {
      final governor = FramePaceGovernor();
      _feed(governor, from: Duration.zero, seconds: 5, latePerTen: 5);
      expect(governor.level, 1);
      expect(governor.calmNeeded, 30);

      _feed(governor, from: const Duration(seconds: 5), seconds: 33, latePerTen: 0);
      expect(governor.level, 0);

      _feed(governor, from: const Duration(seconds: 38), seconds: 5, latePerTen: 5);
      expect(governor.level, 1);
      expect(governor.calmNeeded, 60);
    });

    test('редкие кадры не судим: секунда с парой кадров ничего не решает', () {
      final governor = FramePaceGovernor();
      for (var i = 0; i < 40; i++) {
        governor.addFrame(
          at: Duration(milliseconds: 500 * i),
          build: const Duration(milliseconds: 40),
          raster: const Duration(milliseconds: 40),
        );
      }
      expect(governor.level, 0);
    });
  });

  group('PacedClock', () {
    // часы вне дерева виджетов, поэтому закрываются в теле теста: addTearDown идёт после проверки таймеров
    void clockTest(
      String description,
      Future<void> Function(WidgetTester tester, PacedClock clock) body,
    ) {
      testWidgets(description, (tester) async {
        final clock = PacedClock()..repeat();
        try {
          await body(tester, clock);
        } finally {
          clock.dispose();
        }
      });
    }

    clockTest('на 60 Гц тикает каждый кадр, как часы по vsync',
        (tester, clock) async {
      final ticks = await _ticksOver(tester, clock, frame: _hz60, frames: 120);

      expect(ticks, 120);
      expect(clock.lastElapsedDuration, greaterThan(const Duration(seconds: 1)));
    });

    clockTest('на 120 Гц тикает через кадр', (tester, clock) async {
      final ticks = await _ticksOver(tester, clock, frame: _hz120, frames: 240);

      expect(clock.vsync, _hz120);
      expect(ticks, inInclusiveRange(119, 122));
    });

    clockTest('сам будит кадр, когда больше никто не рисует',
        (tester, clock) async {
      await _ticksOver(tester, clock, frame: _hz120, frames: 4);
      await tester.pump(_hz120);
      expect(tester.binding.hasScheduledFrame, isFalse);

      await tester.binding.delayed(const Duration(milliseconds: 13));
      expect(tester.binding.hasScheduledFrame, isTrue);
    });

    clockTest('когда телефон не успевает, на 60 Гц тикает через кадр',
        (tester, clock) async {
      final governor = FramePaceGovernor();
      _feed(governor, from: Duration.zero, seconds: 4, latePerTen: 5);
      FramePace.instance.reset(governor);

      final ticks = await _ticksOver(tester, clock, frame: _hz60, frames: 120);

      expect(ticks, inInclusiveRange(59, 62));
    });

    clockTest('заглушённые часы не тикают и кадров не просят',
        (tester, clock) async {
      await tester.pump(_hz60);

      clock.muted = true;
      final ticks = await _ticksOver(tester, clock, frame: _hz60, frames: 30);

      expect(ticks, 0);
      expect(SchedulerBinding.instance.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(clock.isAnimating, isTrue);

      clock.muted = false;
      expect(await _ticksOver(tester, clock, frame: _hz60, frames: 3), 3);
    });

    clockTest('stop обнуляет время, repeat считает заново',
        (tester, clock) async {
      await _ticksOver(tester, clock, frame: _hz60, frames: 30);
      expect(clock.lastElapsedDuration, isNotNull);

      clock.stop();
      expect(clock.lastElapsedDuration, isNull);
      expect(clock.isAnimating, isFalse);
      expect(await _ticksOver(tester, clock, frame: _hz60, frames: 10), 0);

      clock.repeat();
      await tester.pump(_hz60);
      expect(clock.lastElapsedDuration, Duration.zero);
    });
  });
}
