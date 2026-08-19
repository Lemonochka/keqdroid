import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/services/ping_service.dart';

void main() {
  test('Hy2 with obfs uses URL ping even when settings say TCP', () {
    final server = ServerItem(
      id: '1',
      config:
          'hysteria2://pwd@host:443?obfs=salamander&obfs-password=secret&sni=host',
      type: ServerItemType.manual,
    );
    expect(
      PingService.effectivePingType(server, PingType.tcp),
      PingType.url,
    );
  });

  test('VLESS stays on TCP when settings say TCP', () {
    final server = ServerItem(
      id: '2',
      config: 'vless://uuid@host:443',
      type: ServerItemType.manual,
    );
    expect(
      PingService.effectivePingType(server, PingType.tcp),
      PingType.tcp,
    );
  });

  test('TCP ping color thresholds', () {
    expect(PingService.pingLatencyQuality(50, PingType.tcp), PingLatencyQuality.good);
    expect(PingService.pingLatencyQuality(100, PingType.tcp), PingLatencyQuality.fair);
    expect(PingService.pingLatencyQuality(200, PingType.tcp), PingLatencyQuality.poor);
  });

  test('URL proxy ping uses relaxed color thresholds', () {
    expect(PingService.pingLatencyQuality(500, PingType.url), PingLatencyQuality.good);
    expect(PingService.pingLatencyQuality(800, PingType.url), PingLatencyQuality.fair);
    expect(PingService.pingLatencyQuality(1500, PingType.url), PingLatencyQuality.poor);
  });

  test('Speed quality is inverted (higher kbps is better)', () {
    expect(PingService.pingLatencyQuality(40000, PingType.speed), PingLatencyQuality.good);
    expect(PingService.pingLatencyQuality(10000, PingType.speed), PingLatencyQuality.fair);
    expect(PingService.pingLatencyQuality(3000, PingType.speed), PingLatencyQuality.poor);
  });

  test('Speed value formats as Mbps, latency as ms', () {
    expect(PingService.formatPingValue(15300, PingType.speed), '15.3 Mbps');
    expect(PingService.formatPingValue(120000, PingType.speed), '120 Mbps');
    expect(PingService.formatPingValue(42, PingType.tcp), '42 ms');
    expect(PingService.formatPingValue(350, PingType.url), '350 ms');
  });

  test('Speed ping type survives stored round-trip and stays speed', () {
    final server = ServerItem(
      id: '3',
      config: 'vless://uuid@host:443',
      type: ServerItemType.manual,
    );
    expect(PingService.effectivePingType(server, PingType.speed), PingType.speed);
    expect(PingService.pingTypeToStored(PingType.speed), 'speed');
    expect(PingService.pingTypeFromStored('speed'), PingType.speed);
  });

  test('TUN fallback only rewrites TCP, leaves speed/url intact', () {
    expect(
      PingService.pingTypeForConnectionState(PingType.tcp,
          vpnConnected: true, tunMode: true),
      PingType.url,
    );
    expect(
      PingService.pingTypeForConnectionState(PingType.speed,
          vpnConnected: true, tunMode: true),
      PingType.speed,
    );
    expect(
      PingService.pingTypeForConnectionState(PingType.tcp,
          vpnConnected: true, tunMode: false),
      PingType.tcp,
    );
  });

  group('на Android подмена не зависит от activeMode', () {
    // Android всегда TUN, но android_tunnel_backend не заполняет activeMode,
    // поэтому tunMode приходит false — и без поправки на платформу raw tcp
    // мерил бы локальный конец туннеля (у пользователей это выглядело как
    // одинаковые 2-4 мс до любого сервера).
    test('tcp подменяется даже при tunMode: false', () {
      expect(
        PingService.pingTypeForConnectionState(PingType.tcp,
            vpnConnected: true, tunMode: false, platformAlwaysTun: true),
        PingType.url,
      );
    });

    test('icmp тоже, он через tun2socks не проходит', () {
      expect(
        PingService.pingTypeForConnectionState(PingType.icmp,
            vpnConnected: true, tunMode: false, platformAlwaysTun: true),
        PingType.url,
      );
    });

    test('без подключения меряем как просили', () {
      // Туннеля нет — raw tcp честен, подменять его нечем и незачем.
      expect(
        PingService.pingTypeForConnectionState(PingType.tcp,
            vpnConnected: false, tunMode: false, platformAlwaysTun: true),
        PingType.tcp,
      );
    });

    test('speed и url не трогаем', () {
      for (final type in const [PingType.speed, PingType.url]) {
        expect(
          PingService.pingTypeForConnectionState(type,
              vpnConnected: true, tunMode: false, platformAlwaysTun: true),
          type,
        );
      }
    });
  });
}
