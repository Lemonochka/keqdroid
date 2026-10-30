import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/utils/import_payload.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';
import 'package:keqdroid/utils/vpn_core_support.dart';

/// Готовый конфиг Clash вставляют так же, как ссылку, — целым текстом.
///
/// Резать его построчно нельзя: в YAML нет ни фигурной скобки в начале, ни
/// строки-ссылки, поэтому один профиль превращался в десятки «Unsupported
/// format». По узлам он раскладывается так же, как через подписку.
const _clashYaml = '''
mixed-port: 7890
proxies:
  - name: "node-1"
    type: vless
    server: example.com
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
    tls: true
    network: tcp
proxy-groups:
  - name: PROXY
    type: select
    proxies: ["node-1"]
rules:
  - MATCH,PROXY
''';

void main() {
  test('YAML-конфиг Clash режется по узлам, а не строками', () {
    final configs = splitServerImportPayload(_clashYaml);

    expect(configs, hasLength(1));
    expect(
      ServersNotifier.validateServerConfig(configs.single),
      isNull,
      reason: 'валидация обязана принять его как сервер',
    );
  });

  // её файл из Telegram: якоря, AWG до i1 и два MASQUE. приезжал одним
  // сервером на весь профиль
  test('файл WARP даёт три сервера, и каждый собирает mihomo', () {
    final yaml = File(
      'test/fixtures/subscription_payloads/clash-yaml-warp.txt',
    ).readAsStringSync();
    final configs = splitServerImportPayload(yaml);

    expect(configs, hasLength(3));
    final nodes = <Map<String, dynamic>>[];
    for (final config in configs) {
      expect(ServersNotifier.validateServerConfig(config), isNull);
      expect(detectServerFormat(config), ServerFormat.clashYaml);
      expect(ServerItem.fromRaw(config).address, '203.0.113.40');
      final session = MihomoConfigGen.build(
        config,
        const AppSettings(),
        socksPort: 2080,
      );
      nodes.add((session['proxies'] as List).single as Map<String, dynamic>);
    }

    expect([for (final n in nodes) n['name']], [
      '[WARP-AWG] Default',
      '[WARP-MASQUE] QUIC',
      '[WARP-MASQUE] H2',
    ]);
    expect([for (final n in nodes) n['type']], ['wireguard', 'masque', 'masque']);
    expect(
      (nodes[0]['amnezia-wg-option'] as Map)['i1'],
      '<b 0xc10000000114367096bb0fb3f58f3a3f>',
    );
    expect(nodes[0]['reserved'], [1, 2, 3]);
    expect(nodes[1].containsKey('network'), isFalse);
    expect(nodes[2]['network'], 'h2');
    expect(nodes[2]['sni'], 'sni.example');
  });

  test('профиль на proxy-providers остаётся целым', () {
    // одиночный socks5 рядом заслонил бы узлы провайдера
    const profile = '''
proxies:
  - name: "local"
    type: socks5
    server: 198.51.100.9
    port: 1080
proxy-groups:
  - name: Proxy
    type: select
    use: ["main"]
proxy-providers:
  main:
    type: http
    url: "https://example.invalid/nodes.yaml"
    interval: 3600
rules:
  - MATCH,Proxy
''';
    final configs = splitServerImportPayload(profile);

    expect(configs, hasLength(1));
    final decoded = jsonDecode(configs.single) as Map<String, dynamic>;
    expect(decoded['proxy-providers'], isNotNull);
    expect(decoded['rules'], ['MATCH,Proxy']);
  });

  test('негодный clash отдаётся целиком — ради внятной причины', () {
    // Узлы за `proxy-providers`, но групп нет: правилу некуда указывать.
    const broken = '''
proxy-providers:
  main:
    url: "https://example.com/sub"
    type: http
''';
    final configs = splitServerImportPayload(broken);

    expect(configs, hasLength(1));
    final problem = ServersNotifier.validateServerConfig(configs.single);
    expect(problem, isNotNull);
    expect(
      problem,
      contains('proxy-groups'),
      reason: 'причина обязана быть названа, а не «формат не поддерживается»',
    );
  });

  test('список ссылок по-прежнему режется построчно', () {
    final configs = splitServerImportPayload(
      'vless://uuid@a.example:443?type=tcp&security=none\n'
      'vless://uuid@b.example:443?type=tcp&security=none',
    );

    expect(configs, hasLength(2));
  });
}
