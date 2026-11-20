import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/shared/ui/halloween/halloween_season.dart';

void main() {
  group('окно праздника', () {
    test(
      'открывается в полночь 20 октября и закрывается в полночь 3 ноября',
      () {
        expect(
          HalloweenSeason.contains(DateTime(2026, 10, 19, 23, 59, 59)),
          isFalse,
        );
        expect(HalloweenSeason.contains(DateTime(2026, 10, 20)), isTrue);
        expect(HalloweenSeason.contains(DateTime(2026, 10, 31, 12)), isTrue);
        // 2 ноября последний день: подпись в настройках обещает до 2 ноября
        expect(
          HalloweenSeason.contains(DateTime(2026, 11, 2, 23, 59, 59)),
          isTrue,
        );
        expect(HalloweenSeason.contains(DateTime(2026, 11, 3)), isFalse);
      },
    );

    test('в следующем году само не возвращается', () {
      // год зашит нарочно: забытая сборка не должна через год снова стать тыквой
      expect(HalloweenSeason.contains(DateTime(2027, 10, 31)), isFalse);
      expect(HalloweenSeason.contains(DateTime(2025, 10, 31)), isFalse);
    });

    test('ждёт ровно до ближайшей границы, после окна — ничего', () {
      expect(
        HalloweenSeason.untilNextBoundary(DateTime(2026, 10, 19, 23)),
        const Duration(hours: 1),
      );
      expect(
        HalloweenSeason.untilNextBoundary(DateTime(2026, 11, 2, 22)),
        const Duration(hours: 2),
      );
      expect(HalloweenSeason.untilNextBoundary(DateTime(2026, 11, 3)), isNull);
    });
  });
}
