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

    // Единственный сервер уходил под Direct-домены со `skipFallback`, и всё
    // остальное оставалось без резолвера вовсе: «прописал свой DNS — интернет
    // пропал». С одним сервером сплит не нужен, он и так отвечает на всё.
    test('единственный кастомный DNS остаётся общим резолвером', () {
      const core = XrayCoreSettings(
        dnsUseCustom: true,
        dnsServers: 'https://dns.google/dns-query',
      );
      final servers = (core.buildDnsBlock(
        directDomains: ['domain:corp.example'],
      )['servers'] as List).cast<Map<String, dynamic>>();

      expect(servers, hasLength(1));
      expect(servers.single['address'], 'https://dns.google/dns-query');
      expect(servers.single.containsKey('domains'), isFalse);
    });

    // Строки пользователя уходят в конфиг как есть: и `https+local://` (мимо
    // туннеля), и `https://` (через роутинг) остаются на его усмотрение.
    test('кастомные серверы не переписываются', () {
      const core = XrayCoreSettings(
        dnsUseCustom: true,
        dnsServers: 'https+local://1.1.1.1/dns-query\nquic://dns.adguard.com\n1.1.1.1',
      );
      final servers = (core.buildDnsBlock(
        directDomains: const [],
        bootstrapDomains: const ['full:vpn.example.net'],
      )['servers'] as List).cast<Map<String, dynamic>>();

      expect(servers.first['domains'], ['full:vpn.example.net']);
      expect(
        servers.skip(1).map((s) => s['address']),
        ['https+local://1.1.1.1/dns-query', 'quic://dns.adguard.com', '1.1.1.1'],
      );
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
