import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/platform/home_widget_sync.dart';

void main() {
  ServerItem server({int? pingMs, String? pingType}) => ServerItem(
        id: 'id-1',
        config:
            'vless://uuid-1@1.2.3.4:443?security=tls&sni=x.com#🇵🇱 Poland Fast',
        type: ServerItemType.manual,
        pingMs: pingMs,
        lastTestedAt: pingMs == null ? null : DateTime(2026, 11, 1),
        lastPingType: pingType,
      );

  test('the widget gets the name without the flag and the country apart', () {
    final s = homeWidgetServer(server(), const AppSettings())!;
    expect(s.key, '🇵🇱 Poland Fast');
    expect(s.name, 'Poland Fast');
    expect(s.countryCode, 'PL');
    expect(s.ping, isNull);
  });

  test('the ping goes as the app shows it', () {
    final s = homeWidgetServer(
        server(pingMs: 38, pingType: 'tcp'), const AppSettings())!;
    expect(s.ping, '38 ms');
  });

  // в pingMs у замера скорости килобиты в секунду
  test('a speed test is not sent as a ping', () {
    final s = homeWidgetServer(
        server(pingMs: 42000, pingType: 'speed'), const AppSettings())!;
    expect(s.ping, isNull);
  });

  test('no active server sends nothing', () {
    expect(homeWidgetServer(null, const AppSettings()), isNull);
  });
}
