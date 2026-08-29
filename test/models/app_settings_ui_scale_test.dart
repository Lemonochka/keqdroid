import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';

void main() {
  group('размер интерфейса', () {
    test('по умолчанию 1.0 — то есть ровно как в системе', () {
      expect(const AppSettings().uiScale, 1.0);
    });

    test('переживает round-trip через json', () {
      final saved = const AppSettings().copyWith(uiScale: 1.25);
      final back = AppSettings.fromJson(saved.toJson());
      expect(back.uiScale, 1.25);
    });

    test('значение за границами обрезается, а не принимается как есть', () {
      // Число приезжает из бэкапа и из настроек, записанных другой версией, где
      // границы могли быть другими. Пропустить 4.0 значит показать пользователю
      // экран, на котором не найти обратный ползунок.
      expect(const AppSettings().copyWith(uiScale: 9.0).uiScale,
          AppSettings.maxUiScale);
      expect(const AppSettings().copyWith(uiScale: 0.1).uiScale,
          AppSettings.minUiScale);
      expect(
        AppSettings.fromJson({'uiScale': 42}).uiScale,
        AppSettings.maxUiScale,
      );
    });

    test('мусор вместо числа не ломает разбор настроек', () {
      expect(AppSettings.fromJson(const {}).uiScale, 1.0);
      expect(AppSettings.fromJson(const {'uiScale': 'большой'}).uiScale, 1.0);
      expect(AppSettings.clampUiScale(double.nan), 1.0);
      expect(AppSettings.clampUiScale(double.infinity), 1.0);
    });

    test('участвует в равенстве — иначе тема не перестроится', () {
      const base = AppSettings();
      expect(base.copyWith(uiScale: 1.2), isNot(base));
      expect(base.copyWith(uiScale: 1.2).hashCode, isNot(base.hashCode));
    });
  });
}
