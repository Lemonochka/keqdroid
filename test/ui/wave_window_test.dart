import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/screens/servers/wave_window.dart';

void main() {
  group('бегущий сегмент', () {
    test('никогда не выходит за края и не выворачивается', () {
      for (var i = 0; i <= 200; i++) {
        final progress = i / 20; // несколько полных оборотов фазы
        final (start, end) = waveRunningWindow(progress);
        expect(start, inInclusiveRange(0.0, 1.0), reason: 'progress=$progress');
        expect(end, inInclusiveRange(0.0, 1.0), reason: 'progress=$progress');
        expect(
          end,
          greaterThanOrEqualTo(start),
          reason: 'конец левее начала при progress=$progress',
        );
      }
    });

    test('в середине пробега сегмент полной длины', () {
      // Половина пробега — сегмент целиком внутри, ничего не срезано краями.
      final (start, end) = waveRunningWindow(0.25);
      expect(end - start, closeTo(kWaveRunningWindowFraction, 1e-9));
    });

    test('на разворотах сегмент уходит за край и въезжает обратно', () {
      // Штатное поведение indeterminate-индикатора: на самих разворотах
      // сегмент целиком за экраном, окно пустое.
      final (leftStart, leftEnd) = waveRunningWindow(0);
      expect(leftStart, closeTo(0.0, 1e-9));
      expect(leftEnd, closeTo(0.0, 1e-9));

      final (rightStart, rightEnd) = waveRunningWindow(0.5);
      expect(rightStart, closeTo(1.0, 1e-9));
      expect(rightEnd, closeTo(1.0, 1e-9));

      // Сразу после разворота он въезжает: слева растёт правый край при
      // прижатом левом, справа — наоборот.
      final (enterStart, enterEnd) = waveRunningWindow(0.05);
      expect(enterStart, 0.0);
      expect(enterEnd, greaterThan(0.0));
      expect(enterEnd, lessThan(kWaveRunningWindowFraction));

      final (exitStart, exitEnd) = waveRunningWindow(0.45);
      expect(exitEnd, 1.0);
      expect(exitStart, greaterThan(1 - kWaveRunningWindowFraction));
      expect(exitStart, lessThan(1.0));
    });

    test('идёт туда и обратно', () {
      final forward = waveRunningWindow(0.15).$1;
      final backward = waveRunningWindow(0.85).$1;
      // Симметричные точки пробега дают одинаковое положение: значит сегмент
      // возвращается тем же путём, а не прыгает в начало.
      expect(backward, closeTo(forward, 1e-9));
    });
  });

  group('разворот в полную ширину', () {
    const from = (0.3, 0.7);

    test('в нуле — там же, где остановился сегмент', () {
      expect(waveExpandedWindow(from, 0), from);
    });

    test('в единице — вся ширина', () {
      final (start, end) = waveExpandedWindow(from, 1);
      expect(start, closeTo(0.0, 1e-9));
      expect(end, closeTo(1.0, 1e-9));
    });

    test('растёт монотонно в обе стороны', () {
      var prevStart = 1.0;
      var prevEnd = 0.0;
      for (var i = 0; i <= 20; i++) {
        final (start, end) = waveExpandedWindow(from, i / 20);
        expect(start, lessThanOrEqualTo(prevStart));
        expect(end, greaterThanOrEqualTo(prevEnd));
        prevStart = start;
        prevEnd = end;
      }
    });

    test('перелёт пружины зажимается по краям', () {
      // spatialSlow недодемпфирована и уходит за единицу — без зажима отрезок
      // вылез бы за пределы виджета.
      final (start, end) = waveExpandedWindow(from, 1.4);
      expect(start, 0.0);
      expect(end, 1.0);
    });
  });
}
