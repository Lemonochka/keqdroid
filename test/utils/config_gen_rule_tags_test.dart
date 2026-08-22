import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

/// `ruleTag` — единственный способ узнать, ПО КАКОМУ правилу ушло соединение:
/// xray печатает «Hit route rule: [tag] so taking detour [proxy] for [...]», и по
/// этому тегу дебаг-экран «Соединения» показывает правило. Без тега в логе только
/// «taking detour [proxy]» — куда ушло, но не почему.
const _server = 'vless://uuid@example.com:443?type=tcp&security=none#demo';

List<Map<String, dynamic>> _rules(String config) =>
    (((jsonDecode(config) as Map)['routing'] as Map)['rules'] as List)
        .cast<Map<String, dynamic>>();

void main() {
  setUp(() => Socks5Credentials().init('u', 'p'));

  test('every routing rule carries a unique ruleTag', () {
    final rules = _rules(ConfigGeneratorV2.generateConfig(
      _server,
      const AppSettings(
        directRules: 'vk.com, geoip:ru, 10.8.0.0/24',
        proxyRules: 'youtube.com, geoip:telegram, 1.1.1.1',
        blockedRules: 'doubleclick.net, geoip:cn, 5.5.5.0/24',
      ),
    ));

    final tags = <String>[];
    for (final rule in rules) {
      expect(rule['ruleTag'], isA<String>(), reason: 'untagged rule: $rule');
      tags.add(rule['ruleTag'] as String);
    }
    expect(tags.toSet().length, tags.length, reason: 'duplicate ruleTag: $tags');
    expect(
      tags,
      containsAll([
        'block-domains',
        'block-geoip',
        'block-ips',
        'direct-domains',
        'direct-geoip',
        'direct-private',
        'proxy-domains',
        'proxy-geoip',
        'proxy-ips',
        'final',
      ]),
    );
  });

  test('tagging does not disturb the rule bodies', () {
    final rules = _rules(ConfigGeneratorV2.generateConfig(
      _server,
      const AppSettings(proxyRules: 'youtube.com'),
    ));
    final proxyRule =
        rules.firstWhere((r) => r['ruleTag'] == 'proxy-domains');
    expect(proxyRule['type'], 'field');
    expect(proxyRule['outboundTag'], 'proxy');
    expect(proxyRule['domain'], ['domain:youtube.com']);

    final last = rules.last;
    expect(last['ruleTag'], 'final');
    expect(last['outboundTag'], 'proxy');
    expect(last['network'], 'tcp,udp');
  });

  group('dns-out', () {
    List<Map<String, dynamic>> outbounds(String config) =>
        ((jsonDecode(config) as Map)['outbounds'] as List)
            .cast<Map<String, dynamic>>();
    Map<String, dynamic> dnsBlock(String config) =>
        (jsonDecode(config) as Map)['dns'] as Map<String, dynamic>;

    // Каждый DNS-запрос устройства = отдельное TCP до сервера. Пачка из
    // семи запросов выносила лимит новых соединений на стороне сервера.
    test('порт 53 уходит в dns-аутбаунд, а не в туннель', () {
      final config = ConfigGeneratorV2.generateConfig(_server, const AppSettings());
      final dns = _rules(config).firstWhere((r) => r['ruleTag'] == 'dns-out');
      expect(dns['port'], '53');
      expect(dns['network'], 'tcp,udp');
      expect(dns['outboundTag'], 'dns-out');

      final out = outbounds(config).firstWhere((o) => o['tag'] == 'dns-out');
      expect(out['protocol'], 'dns');
      expect((out['settings'] as Map)['nonIPQuery'], 'reject');
    });

    // Инбаунд LAN-прокси слушает 0.0.0.0: перехвати мы DNS раньше `lan-deny` —
    // получили бы резолвер, открытый в интернет.
    test('перехват стоит ПОСЛЕ запрета входа в LAN-инбаунды', () {
      final rules = _rules(ConfigGeneratorV2.generateConfig(
        _server,
        const AppSettings(lanSharing: true),
      ));
      expect(
        rules.indexWhere((r) => r['ruleTag'] == 'lan-deny'),
        lessThan(rules.indexWhere((r) => r['ruleTag'] == 'dns-out')),
      );
    });

    // Адрес сервера обязан резолвиться системным резолвером: через туннель за
    // ним не сходить — туннеля ещё нет.
    test('адрес сервера резолвится локально, DoH уходит в туннель', () {
      final dns = dnsBlock(ConfigGeneratorV2.generateConfig(
        'vless://uuid@vpn.example.net:443?type=tcp&security=none#demo',
        const AppSettings(),
      ));
      final servers = (dns['servers'] as List).cast<Map<String, dynamic>>();
      expect(servers.first['address'], 'localhost');
      expect(servers.first['domains'], ['full:vpn.example.net']);
      expect(servers.first['skipFallback'], isTrue);
      expect(
        servers.map((s) => s['address']),
        contains('https://1.1.1.1/dns-query'),
      );
    });

    test('сервер по IP не плодит bootstrap-запись — резолвить нечего', () {
      final dns = dnsBlock(ConfigGeneratorV2.generateConfig(
        'vless://uuid@203.0.113.9:443?type=tcp&security=none#demo',
        const AppSettings(),
      ));
      final servers = (dns['servers'] as List).cast<Map<String, dynamic>>();
      expect(
        servers.where((s) =>
            (s['domains'] as List?)?.contains('full:203.0.113.9') ?? false),
        isEmpty,
      );
    });

    // «Остальное — direct»: `final` увёл бы DoH к резолверу мимо прокси, а при
    // `block` — вовсе в blackhole, и DNS умер бы целиком.
    test('вне глобал-прокси DoH остаётся прямым', () {
      for (final mode in [
        AppSettings.finalOutboundDirect,
        AppSettings.finalOutboundBlock,
      ]) {
        final dns = dnsBlock(ConfigGeneratorV2.generateConfig(
          _server,
          AppSettings(finalOutbound: mode),
        ));
        expect(
          (dns['servers'] as List).cast<Map<String, dynamic>>()
              .map((s) => s['address']),
          contains('https+local://1.1.1.1/dns-query'),
          reason: 'finalOutbound=$mode',
        );
      }
    });

    test('в ping-конфиге ни правила, ни аутбаунда нет', () {
      final config = ConfigGeneratorV2.generatePingConfig(
        _server,
        const AppSettings(),
        socksPort: 28150,
      );
      expect(outbounds(config).any((o) => o['tag'] == 'dns-out'), isFalse);
      expect(
        _rules(config).any((r) => r['outboundTag'] == 'dns-out'),
        isFalse,
      );
    });
  });

  group('block-quic', () {
    // vision отвергает UDP/443 сам, но только после того, как поднял до сервера
    // полное TCP+TLS. Каждый QUIC-ретрай приложения = выброшенное рукопожатие,
    // поэтому режем такой трафик правилом, не доводя до аутбаунда.
    const vision =
        'vless://uuid@example.com:443?type=tcp&security=reality&pbk=k&sid=aa'
        '&fp=chrome&flow=xtls-rprx-vision#demo';

    test('vision + глобал-прокси: QUIC уходит в block до proxy-правил', () {
      final rules = _rules(ConfigGeneratorV2.generateConfig(
        vision,
        const AppSettings(proxyRules: 'youtube.com'),
      ));
      final quic = rules.firstWhere((r) => r['ruleTag'] == 'block-quic');
      expect(quic['network'], 'udp');
      expect(quic['port'], '443');
      expect(quic['outboundTag'], 'block');
      expect(
        rules.indexOf(quic),
        lessThan(rules.indexWhere((r) => r['ruleTag'] == 'proxy-domains')),
      );
    });

    test('без vision правило не появляется — QUIC там работает', () {
      final rules = _rules(ConfigGeneratorV2.generateConfig(
        _server,
        const AppSettings(),
      ));
      expect(rules.any((r) => r['ruleTag'] == 'block-quic'), isFalse);
    });

    test('флоу -udp443 умеет UDP/443 сам, его не режем', () {
      final rules = _rules(ConfigGeneratorV2.generateConfig(
        vision.replaceAll('xtls-rprx-vision', 'xtls-rprx-vision-udp443'),
        const AppSettings(),
      ));
      expect(rules.any((r) => r['ruleTag'] == 'block-quic'), isFalse);
    });

    test('«остальное — direct»: чужой QUIC не наше дело', () {
      final rules = _rules(ConfigGeneratorV2.generateConfig(
        vision,
        const AppSettings(finalOutbound: AppSettings.finalOutboundDirect),
      ));
      expect(rules.any((r) => r['ruleTag'] == 'block-quic'), isFalse);
    });
  });

  test('ping config stays untagged (log level none, nothing reads it)', () {
    final rules = _rules(ConfigGeneratorV2.generatePingConfig(
      _server,
      const AppSettings(proxyRules: 'youtube.com'),
      socksPort: 28150,
    ));
    expect(rules.every((r) => !r.containsKey('ruleTag')), isTrue);
  });
}
