import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';

// До 15.10.2026 в выборе ядра был пункт Автоматически (auto). Ядро он
// выбирал то же, что xray, и был убран; сохранённое auto читается как xray.
void main() {
  test('по умолчанию xray', () {
    expect(const AppSettings().vpnCore, AppSettings.vpnCoreXray);
  });

  test('сохранённое auto становится xray', () {
    expect(
      AppSettings.fromJson(const {'vpnCore': 'auto'}).vpnCore,
      AppSettings.vpnCoreXray,
    );
  });

  test('выбранный mihomo остаётся mihomo', () {
    expect(
      AppSettings.fromJson(const {'vpnCore': 'mihomo'}).vpnCore,
      AppSettings.vpnCoreMihomo,
    );
  });
}
