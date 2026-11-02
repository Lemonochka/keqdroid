import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/services/subscription_service.dart';
import 'package:keqdroid/utils/custom_clash_config.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

// ss-opts, dialer-proxy и smux ссылка не несёт (сверено по примерам docs/config/proxies mihomo).
// пин, token v4 и версию UoT несёт: эти узлы обязаны остаться ссылками
const _profile = '''
proxies:
  - name: Plain
    type: vless
    server: plain.example
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
    tls: true
    servername: plain.example
  - name: Pinned
    type: vless
    server: pin.example
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
    tls: true
    servername: pin.example
    fingerprint: 1d9cd22b3d6ab1e1f0e3c2a7d5d5c2c6a0a4d6f8e1b2c3d4e5f60718293a4b5c
  - name: TuicV4
    type: tuic
    server: tuic.example
    port: 443
    token: tuic-v4-token
  - name: TrojanGo
    type: trojan
    server: tg.example
    port: 443
    password: pw
    ss-opts:
      enabled: true
      method: aes-128-gcm
      password: sspw
  - name: Exit
    type: trojan
    server: exit.example
    port: 443
    password: pw
    dialer-proxy: Plain
  - name: Uot
    type: ss
    server: ss.example
    port: 8388
    cipher: 2022-blake3-aes-128-gcm
    password: AAAAAAAAAAAAAAAAAAAAAA==
    udp-over-tcp: true
    udp-over-tcp-version: 2
  - name: Smux
    type: vless
    server: smux.example
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
    tls: true
    smux: {enabled: true, protocol: h2mux, max-streams: 8}
proxy-groups:
  - {name: G, type: select, proxies: [Plain, Pinned, TuicV4, TrojanGo, Exit, Uot, Smux]}
rules:
  - MATCH,G
''';

void main() {
  setUp(() => Socks5Credentials().init('user', 'pass'));

  Map<String, dynamic> nodeOf(String entry, String name) {
    final clash = CustomClashConfig.tryParse(entry);
    expect(clash, isNotNull, reason: '$name должен ехать целиком');
    return clash!.proxies.firstWhere((p) => p['name'] == name);
  }

  test('узел, который ссылка повторяет целиком, остаётся ссылкой', () {
    final entries = SubscriptionService.parseBodyForTest(_profile);
    expect(entries.where((e) => e.startsWith('vless://')), hasLength(2));
    expect(entries.where((e) => e.startsWith('tuic://')), hasLength(1));
    expect(entries.firstWhere((e) => e.startsWith('ss://')), contains('udp-over-tcp-version=2'));
    expect(entries.firstWhere((e) => e.contains('pin.example')), contains('1d9cd22b'));
  });

  test('ss-opts, звено цепочки и smux доезжают до ядра', () {
    final entries = SubscriptionService.parseBodyForTest(_profile);
    expect(entries, hasLength(7));
    final whole = entries.where((e) => e.startsWith('{')).toList();
    expect(whole, hasLength(3));

    expect((nodeOf(whole[0], 'TrojanGo')['ss-opts'] as Map)['password'], 'sspw');
    expect((nodeOf(whole[2], 'Smux')['smux'] as Map)['protocol'], 'h2mux');
    final chain = CustomClashConfig.tryParse(whole[1])!;
    expect([for (final p in chain.proxies) p['name']], ['Exit', 'Plain']);
    expect(chain.proxies.first['dialer-proxy'], 'Plain');
  });

  test('одноузловой конфиг ведёт трафик в свой узел и проходит генератор', () {
    final entries = SubscriptionService.parseBodyForTest(_profile);
    final trojanGo = entries.firstWhere((e) => e.contains('"TrojanGo"'));
    final clash = CustomClashConfig.tryParse(trojanGo)!;
    expect(clash.remarks, 'TrojanGo');
    expect(clash.map['rules'], ['MATCH,TrojanGo']);
    final session = MihomoConfigGen.build(trojanGo, const AppSettings(), socksPort: 2080);
    expect((session['rules'] as List).last, 'MATCH,TrojanGo');
    expect(jsonEncode(session['proxies']), contains('sspw'));
  });

  // dialer-proxy бывает и группой (BasicOption в base.go mihomo): wireguard такой пропадал из подписки,
  // а узел со ссылкой становился ссылкой без цепочки и шёл к выходу напрямую
  group('звено цепочки группой', () {
    const yaml = '''
proxies:
  - {name: RU1, type: trojan, server: ru1.example, port: 443, password: a}
  - {name: RU2, type: trojan, server: ru2.example, port: 443, password: b}
  - name: WG
    type: wireguard
    server: 162.159.192.1
    port: 2408
    ip: 172.16.0.2
    private-key: eCtXsJZ27+4PbhDkHnB923tkUn2Gj59wZw5wFA75MnU=
    public-key: bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=
    dialer-proxy: Entry
  - {name: DE, type: trojan, server: de.example, port: 443, password: c, dialer-proxy: Entry}
proxy-groups:
  - {name: Main, type: select, proxies: [WG, DE, RU1]}
  - {name: Entry, type: url-test, proxies: [RU1, Auto]}
  - {name: Auto, type: fallback, proxies: [RU2, DIRECT]}
rules:
  - MATCH,Main
''';

    CustomClashConfig entryOf(String name) => CustomClashConfig.tryParse(
          SubscriptionService.parseBodyForTest(yaml)
              .firstWhere((e) => e.contains('"name":"$name"')),
        )!;

    test('узел едет с группой-звеном и её составом', () {
      expect(SubscriptionService.unsupportedClashNodes(yaml), isEmpty);
      for (final name in ['WG', 'DE']) {
        final clash = entryOf(name);
        expect([for (final p in clash.proxies) p['name']], [name, 'RU1', 'RU2'],
            reason: name);
        expect(
          [for (final g in clash.map['proxy-groups'] as List) g['name']],
          ['Entry', 'Auto'],
          reason: name,
        );
      }
    });

    test('трафик идёт в сам узел, а не в группу-звено, и пинг его строит', () {
      for (final name in ['WG', 'DE']) {
        final clash = entryOf(name);
        expect(clash.primaryTarget, name);
        final session = MihomoConfigGen.build(clash.encode(), const AppSettings(), socksPort: 2080);
        expect((session['rules'] as List).last, 'MATCH,$name');
        final probe = jsonDecode(MihomoConfigGen.generatePingConfig(
          clash.encode(),
          const AppSettings(),
          socksPort: 3001,
        )) as Map<String, dynamic>;
        final main = (probe['proxies'] as List)
            .cast<Map>()
            .firstWhere((p) => p['name'] == MihomoConfigGen.proxyName);
        expect(main['dialer-proxy'], isNot(MihomoConfigGen.proxyName));
        expect(
          [for (final g in probe['proxy-groups'] as List) g['name']],
          contains(main['dialer-proxy']),
        );
      }
    });

    test('звена нет в конфиге: узел как раньше, ссылкой', () {
      final broken = yaml.replaceFirst('dialer-proxy: Entry}', 'dialer-proxy: Missing}');
      final entries = SubscriptionService.parseBodyForTest(broken);
      expect(entries.where((e) => e.contains('"name":"DE"')), isEmpty);
      expect(entries.where((e) => e.startsWith('trojan://') && e.contains('de.example')),
          hasLength(1));
    });
  });

  test('метода у vmess-json нет: POST едет целиком, без метода — ссылкой', () {
    const yaml = '''
proxies:
  - name: Post
    type: vmess
    server: m.example
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
    cipher: auto
    network: http
    http-opts: {method: POST, path: [/m]}
  - name: Get
    type: vmess
    server: m.example
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
    cipher: auto
    network: http
    http-opts: {path: [/m]}
''';
    final entries = SubscriptionService.parseBodyForTest(yaml);
    expect(entries.where((e) => e.startsWith('vmess://')), hasLength(1));
    expect(((nodeOf(entries.firstWhere((e) => e.startsWith('{')), 'Post')
            ['http-opts']) as Map)['method'],
        'POST');
  });
}
