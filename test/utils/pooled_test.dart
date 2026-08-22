import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/pooled.dart';

void main() {
  group('mapPooled', () {
    test('порядок результата — входной, а не порядок ответов', () async {
      // Первый элемент отвечает последним: если складывать по мере готовности,
      // список поедет. Именно это ломало бы раскладку пингов по серверам.
      final out = await mapPooled([30, 20, 10], 3, (ms) async {
        await Future<void>.delayed(Duration(milliseconds: ms));
        return 'v$ms';
      });
      expect(out, ['v30', 'v20', 'v10']);
    });

    test('одновременно работает не больше concurrency', () async {
      var inFlight = 0;
      var peak = 0;
      await mapPooled(List.generate(20, (i) => i), 4, (_) async {
        inFlight++;
        peak = peak > inFlight ? peak : inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        inFlight--;
        return null;
      });
      expect(peak, 4);
    });

    test('воркеров не больше, чем элементов', () async {
      var peak = 0;
      var inFlight = 0;
      await mapPooled([1, 2], 8, (_) async {
        inFlight++;
        peak = peak > inFlight ? peak : inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        inFlight--;
        return null;
      });
      expect(peak, 2);
    });

    test('пустой список не поднимает ни одного воркера', () async {
      var calls = 0;
      final out = await mapPooled(<int>[], 4, (_) async {
        calls++;
        return 0;
      });
      expect(out, isEmpty);
      expect(calls, 0);
    });

    test('concurrency < 1 не вешает вызов, а работает как одиночный', () async {
      final out = await mapPooled([1, 2, 3], 0, (v) async => v * 2);
      expect(out, [2, 4, 6]);
    });

    test('обрабатывается каждый элемент, включая длинный хвост', () async {
      final out = await mapPooled(List.generate(50, (i) => i), 6, (v) async {
        await Future<void>.delayed(Duration(milliseconds: v % 3));
        return v;
      });
      expect(out, List.generate(50, (i) => i));
    });

    test('исключение из action всплывает наружу', () async {
      expect(
        () => mapPooled([1, 2, 3], 2, (v) async {
          if (v == 2) throw StateError('boom');
          return v;
        }),
        throwsStateError,
      );
    });
  });
}
