import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/services/ping_service.dart';

void main() {
  group('дефолт пинга — прокси', () {
    test('чистые настройки дают url', () {
      // Прокси-пинг единственный меряет путь так, как им пойдёт трафик, и
      // единственный измерим при поднятом TUN.
      expect(const AppSettings().pingType, 'url');
      expect(
        PingService.pingTypeFromSettings(const AppSettings()),
        PingType.url,
      );
    });

    test('настройки без ключа тоже читаются как url', () {
      // Так выглядят сохранёнки версий, где ключа ещё не было.
      final s = AppSettings.fromJson(const {});
      expect(s.pingType, 'url');
    });

    test('явно выбранный tcp сохраняется', () {
      // Пользователь мог выбрать raw tcp сознательно — дефолт не должен его
      // перебивать при следующем чтении.
      final s = AppSettings.fromJson(const {'pingType': 'tcp'});
      expect(s.pingType, 'tcp');
    });

    test('мусор и синонимы нормализуются', () {
      expect(AppSettings.fromJson(const {'pingType': 'http'}).pingType, 'url');
      expect(AppSettings.fromJson(const {'pingType': 'proxy'}).pingType, 'url');
      expect(AppSettings.fromJson(const {'pingType': 'ping'}).pingType, 'icmp');
      expect(AppSettings.fromJson(const {'pingType': 'что-то'}).pingType, 'url');
    });
  });

  group('keep-alive', () {
    test('по умолчанию включён', () {
      expect(const AppSettings().pingKeepAlive, isTrue);
      expect(AppSettings.fromJson(const {}).pingKeepAlive, isTrue);
    });

    test('выключённый переживает сериализацию', () {
      final off = const AppSettings().copyWith(pingKeepAlive: false);
      expect(off.pingKeepAlive, isFalse);
      expect(AppSettings.fromJson(off.toJson()).pingKeepAlive, isFalse);
    });

    test('участвует в равенстве', () {
      // Иначе экран настроек не перерисуется на переключении.
      const on = AppSettings();
      final off = on.copyWith(pingKeepAlive: false);
      expect(on == off, isFalse);
      expect(on.hashCode == off.hashCode, isFalse);
    });
  });
}
