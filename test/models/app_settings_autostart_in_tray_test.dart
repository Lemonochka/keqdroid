import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/services/settings_backup_service.dart';

void main() {
  group('автозапуск в трей', () {
    test('выключен и у новых, и у тех, кто обновился', () {
      // у настроек, записанных до появления флага, ключа нет вовсе
      expect(const AppSettings().autostartInTray, isFalse);
      expect(AppSettings.fromJson(const {}).autostartInTray, isFalse);
    });

    test('включённый переживает round-trip через json', () {
      final saved = const AppSettings().copyWith(autostartInTray: true);
      expect(AppSettings.fromJson(saved.toJson()).autostartInTray, isTrue);
    });

    test('участвует в равенстве, иначе переключатель не перерисует экран', () {
      const base = AppSettings();
      expect(base.copyWith(autostartInTray: true), isNot(base));
      expect(
        base.copyWith(autostartInTray: true).hashCode,
        isNot(base.hashCode),
      );
    });

    test('в резервную копию не едет: это про автозапуск этой машины', () {
      expect(
        SettingsBackupService.portableSettingKeys,
        isNot(contains('autostartInTray')),
      );
    });
  });
}
