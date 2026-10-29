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
