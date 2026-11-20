import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/services/settings_backup_service.dart';

void main() {
  group('праздничное оформление', () {
    test('включено по умолчанию — и у новых, и у тех, кто обновился', () {
      // оформление временное и уходит само, поэтому по умолчанию включено;
      // у настроек, записанных до появления флага, ключа нет вовсе
      expect(const AppSettings().seasonalDecor, isTrue);
      expect(AppSettings.fromJson(const {}).seasonalDecor, isTrue);
    });

    test('выключенное переживает round-trip через json', () {
      final saved = const AppSettings().copyWith(seasonalDecor: false);
      expect(AppSettings.fromJson(saved.toJson()).seasonalDecor, isFalse);
    });

    test('участвует в равенстве — иначе переключатель не перерисует экран', () {
      const base = AppSettings();
      expect(base.copyWith(seasonalDecor: false), isNot(base));
      expect(
        base.copyWith(seasonalDecor: false).hashCode,
        isNot(base.hashCode),
      );
    });

    test('уезжает в резервную копию вместе с остальным внешним видом', () {
      expect(
        SettingsBackupService.portableSettingKeys,
        contains('seasonalDecor'),
      );
    });
  });
}
