import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/xray_core_settings.dart';

void main() {
  group('XrayCoreSettings', () {
    test('buildDnsBlock uses custom servers', () {
      const core = XrayCoreSettings(
        dnsUseCustom: true,
        dnsServers: '1.1.1.1\n8.8.8.8',
      );
      final dns = core.buildDnsBlock(directDomains: []);
      final servers = dns['servers'] as List;
      expect(servers.length, 2);
      expect((servers[0] as Map)['address'], '1.1.1.1');
    });

    test('buildDnsBlock resolves direct domains via the system resolver', () {
      // Direct-домены включают корпоративные/LAN-зоны сплит-DNS, которых
      // публичный DoH не знает — их резолвит 'localhost' со skipFallback.
      final dns = const XrayCoreSettings()
          .buildDnsBlock(directDomains: ['domain:corp.example']);
      final servers = (dns['servers'] as List).cast<Map<String, dynamic>>();

      expect(servers.first['address'], 'localhost');
      expect(servers.first['domains'], ['domain:corp.example']);
      expect(servers.first['skipFallback'], isTrue);
      // остальные запросы — по-прежнему публичный DoH
      expect(servers[1]['address'], 'https+local://1.1.1.1/dns-query');
    });

    test('buildDnsBlock keeps the user-chosen server for direct domains', () {
      const core = XrayCoreSettings(
        dnsUseCustom: true,
        dnsServers: '192.168.1.1\n8.8.8.8',
      );
      final dns = core.buildDnsBlock(directDomains: ['domain:corp.example']);
      final servers = (dns['servers'] as List).cast<Map<String, dynamic>>();

      expect(servers.first['address'], '192.168.1.1');
      expect(servers.first['domains'], ['domain:corp.example']);
    });

    test('buildXmuxMap returns null when disabled', () {
      expect(const XrayCoreSettings().buildXmuxMap(), isNull);
    });

    test('round-trips JSON', () {
      const core = XrayCoreSettings(
        xmuxEnabled: true,
        xmuxMaxConcurrency: '8-16',
        logLevel: 'info',
      );
      final restored =
          XrayCoreSettings.fromJson(core.toJson());
      expect(restored, core);
    });
  });
}
