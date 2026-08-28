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
    test('кастомные серверы переписываются только там, где ядро их не поймёт',
        () {
      const core = XrayCoreSettings(
        dnsUseCustom: true,
        dnsServers: 'https+local://1.1.1.1/dns-query\nquic://dns.adguard.com\n1.1.1.1',
      );
      final servers = (core.buildDnsBlock(
        directDomains: const [],
        bootstrapDomains: const ['full:vpn.example.net'],
      )['servers'] as List).cast<Map<String, dynamic>>();

      final bootstrap =
          servers.where((s) => s.containsKey('domains')).toList();
      // Bootstrap берёт кастомные резолверы, а не дефолтные: раз пользователь
      // выбрал свой DNS, адрес сервера ищется им же. Не больше двух — каждый
      // молчащий стоит таймаута на критическом пути к подключению.
      expect(
        bootstrap.map((s) => s['address']),
        [
          'https+local://1.1.1.1/dns-query',
          'quic+local://dns.adguard.com',
          'localhost',
        ],
      );
      expect(
        bootstrap.every(
            (s) => (s['domains'] as List).single == 'full:vpn.example.net'),
        isTrue,
      );

      expect(
        servers.where((s) => !s.containsKey('domains')).map((s) => s['address']),
        // DoQ у xray существует только как `quic+local` (удалённого режима у
        // QUIC-резолвера нет): голый `quic://` молча становится ДОМЕНОМ
        // обычного UDP-сервера и не резолвится никогда.
        [
          'https+local://1.1.1.1/dns-query',
          'quic+local://dns.adguard.com',
          '1.1.1.1',
        ],
      );
    });

    test('bootstrap не ищет адрес сервера через fakedns', () {
      // fakedns вернул бы на адрес сервера ПОДДЕЛЬНЫЙ IP из fake-диапазона, и
      // подключение ушло бы в никуда.
      const core = XrayCoreSettings(
        dnsUseCustom: true,
        dnsServers: 'fakedns\nhttps://1.1.1.1/dns-query',
      );
      final servers = (core.buildDnsBlock(
        directDomains: const [],
        bootstrapDomains: const ['full:vpn.example.net'],
      )['servers'] as List).cast<Map<String, dynamic>>();

      expect(
        servers.where((s) => s.containsKey('domains')).map((s) => s['address']),
        // `https://` тоже приведён к `+local`: через туннель за адресом сервера
        // не сходить, туннеля ещё нет.
        ['https+local://1.1.1.1/dns-query', 'localhost'],
      );
    });

    test('host:port разъезжается на address и port', () {
      // `address` у xray — не строка подключения: если в ней не узнаётся IP,
      // строка разбирается как URL. `[2606:4700:4700::1111]:53` не разбирается
      // вовсе («first path segment in URL cannot contain colon»), и ядро не
      // стартует — туннеля нет совсем.
      const core = XrayCoreSettings(
        dnsUseCustom: true,
        dnsServers: '[2606:4700:4700::1111]:53\ndns.example:5353\n9.9.9.9',
      );
      final servers = (core.buildDnsBlock(directDomains: const [])['servers']
              as List)
          .cast<Map<String, dynamic>>();

      expect(
        servers.map((s) => {'address': s['address'], if (s.containsKey('port')) 'port': s['port']}),
        [
          {'address': '2606:4700:4700::1111', 'port': 53},
          {'address': 'dns.example', 'port': 5353},
          {'address': '9.9.9.9'},
        ],
      );
      // Ограничители — на каждом сервере: их у xray нет глобальных, а без них
      // один молчащий резолвер стоит 4 секунды ожидания (и до 20 на список).
      expect(servers.every((s) => s['timeoutMs'] == 2500), isTrue);
      expect(servers.every((s) => s['serveStale'] == true), isTrue);
    });

    test('адреса, которых ядро не исполнит, выбрасываются с откатом на дефолт',
        () {
      // `tls://`, `sdns://`, `dhcp://` xray не знает: строка молча становится
      // доменом UDP-резолвера, который никогда не отвечает. Пустой список
      // после чистки — уходим в дефолтный DoH, а не остаёмся без DNS.
      const core = XrayCoreSettings(
        dnsUseCustom: true,
        dnsServers: 'tls://1.1.1.1\nsdns://gibberish',
      );
      final servers = (core.buildDnsBlock(directDomains: const [])['servers']
              as List)
          .cast<Map<String, dynamic>>();

      expect(
        servers.map((s) => s['address']),
        containsAll(<String>[
          'https+local://1.1.1.1/dns-query',
          'https+local://8.8.8.8/dns-query',
        ]),
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
