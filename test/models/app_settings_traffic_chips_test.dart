import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';

/// Общие чипы трафика и раздельные — один и тот же показатель в двух видах:
/// раздельные рисуются ВМЕСТО общих. Включёнными разом они быть не должны,
/// иначе включение общих ничего не меняет на экране и переключатель выглядит
/// сломанным.
void main() {
  group('общие чипы трафика и разбивка', () {
    test('включённая разбивка гасит общие чипы', () {
      final s = const AppSettings().copyWith(showTrafficStats: true);
      final after = s.withTrafficSplit(true);
      expect(after.showTrafficSplit, isTrue);
      expect(after.showTrafficStats, isFalse);
    });

    test('включённые общие чипы гасят разбивку', () {
      final s = const AppSettings().copyWith(
        showTrafficStats: false,
        showTrafficSplit: true,
      );
      final after = s.withTrafficStats(true);
      expect(after.showTrafficStats, isTrue);
      expect(after.showTrafficSplit, isFalse);
    });

    test('выключение соседа не трогает', () {
      // Выключить оба — законное состояние: трафик не показываем вовсе.
      final s = const AppSettings().copyWith(
        showTrafficStats: false,
        showTrafficSplit: true,
      );
      final after = s.withTrafficSplit(false);
      expect(after.showTrafficSplit, isFalse);
      expect(after.showTrafficStats, isFalse);
    });

    test('обе включённые в старых настройках сводятся к разбивке', () {
      // До этого правила разбивка молча перекрывала общие чипы, и на диске
      // остались обе. Выигрывает разбивка: экран после обновления такой же,
      // каким был.
      final loaded = AppSettings.fromJson({
        'showTrafficStats': true,
        'showTrafficSplit': true,
      });
      expect(loaded.showTrafficSplit, isTrue);
      expect(loaded.showTrafficStats, isFalse);
    });

    test('обычные состояния разбор не трогает', () {
      final onlyStats = AppSettings.fromJson({
        'showTrafficStats': true,
        'showTrafficSplit': false,
      });
      expect(onlyStats.showTrafficStats, isTrue);
      expect(onlyStats.showTrafficSplit, isFalse);

      final neither = AppSettings.fromJson({
        'showTrafficStats': false,
        'showTrafficSplit': false,
      });
      expect(neither.showTrafficStats, isFalse);
      expect(neither.showTrafficSplit, isFalse);

      // Настроек этих в json нет вовсе — умолчания как были.
      final fresh = AppSettings.fromJson(const {});
      expect(fresh.showTrafficStats, isTrue);
      expect(fresh.showTrafficSplit, isFalse);
    });

    test('состояние переживает round-trip через json', () {
      final saved = const AppSettings().withTrafficSplit(true);
      final back = AppSettings.fromJson(saved.toJson());
      expect(back.showTrafficSplit, isTrue);
      expect(back.showTrafficStats, isFalse);
    });
  });
}
