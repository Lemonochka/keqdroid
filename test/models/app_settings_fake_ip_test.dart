import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';

// До 26.09.2026 fake-ip был настройкой одного mihomo и хранился как
// mihomoFakeIp. Теперь он общий на оба ядра и пишется как fakeIp; у тех,
// кто включил его раньше, он не должен выключиться сам.
void main() {
  test('старое имя дочитывается', () {
    expect(AppSettings.fromJson(const {'mihomoFakeIp': true}).fakeIp, isTrue);
  });

  test('новое имя главнее старого', () {
    final s = AppSettings.fromJson(const {
      'fakeIp': false,
      'mihomoFakeIp': true,
    });
    expect(s.fakeIp, isFalse);
  });

  test('пишется только новое имя', () {
    final json = const AppSettings(fakeIp: true).toJson();
    expect(json['fakeIp'], isTrue);
    expect(json.containsKey('mihomoFakeIp'), isFalse);
  });
}
