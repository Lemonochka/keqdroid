import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/tunnel/vpn_backend.dart';
import 'package:keqdroid/utils/proxy_chain.dart';
import 'package:keqdroid/utils/vpn_core_support.dart';

/// Ядро выбирает ФОРМАТ сервера, а настройка — только там, где формат берут
/// оба. Раньше несовпадение молча откатывалось на xray, и это выглядело как
/// «включил mihomo — приложение пишет, что активное ядро xray».
void main() {
  const link = 'vless://uuid@example.com:443?type=tcp&security=reality'
      '&pbk=k&sni=example.org#node';

  final xrayJson = jsonEncode({
    'remarks': 'provider',
    'outbounds': [
      {
        'protocol': 'vless',
        'tag': 'proxy',
        'settings': {
          'vnext': [
            {
              'address': 'example.com',
              'port': 443,
              'users': [
                {'id': 'uuid', 'encryption': 'none'},
              ],
            },
          ],
        },
      },
    ],
  });

  const clashYaml = '''
proxies:
  - name: "NL"
    type: vless
    server: nl.example
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
    tls: true
proxy-groups:
  - name: Proxy
    type: select
    proxies: ["NL"]
rules:
  - MATCH,Proxy
''';

  const awg = '''
[Interface]
PrivateKey = aGVsbG8gd29ybGQgaGVsbG8gd29ybGQgaGVsbG8gd28=
Address = 10.0.0.2/32
Jc = 4

[Peer]
PublicKey = aGVsbG8gd29ybGQgaGVsbG8gd29ybGQgaGVsbG8gd28=
Endpoint = example.com:51820
AllowedIPs = 0.0.0.0/0
''';

  final chain = ProxyChainConfig(
    name: 'chain',
    hops: [
      const ProxyChainHop(config: 'vless://a@a.example:443?type=tcp'),
      const ProxyChainHop(config: 'vless://b@b.example:443?type=tcp'),
    ],
  ).encode();

  group('формат', () {
    test('узнаётся по самому конфигу', () {
      expect(detectServerFormat(link), ServerFormat.link);
      expect(detectServerFormat(xrayJson), ServerFormat.xrayJson);
      expect(detectServerFormat(clashYaml), ServerFormat.clashYaml);
      expect(detectServerFormat(chain), ServerFormat.chain);
      expect(detectServerFormat(awg), ServerFormat.amneziaWg);
      expect(detectServerFormat('мусор'), ServerFormat.unknown);
      expect(detectServerFormat(''), ServerFormat.unknown);
    });

    // Профиль, у которого узлы за ссылкой: ключа `proxies` в нём нет вовсе.
    // Такой конфиг обязан узнаваться и в YAML-, и в JSON-форме — сохраняется он
    // всегда как JSON, и без этого сервер уезжал в «неизвестный формат», то
    // есть на xray, который его не разберёт.
    test('профиль на proxy-providers — тоже clash, в обеих формах', () {
      const providersYaml = '''
proxy-providers:
  main:
    type: http
    url: "https://example.invalid/nodes.yaml"
proxy-groups:
  - name: Proxy
    type: select
    use: ["main"]
rules:
  - MATCH,Proxy
''';
      expect(detectServerFormat(providersYaml), ServerFormat.clashYaml);

      final providersJson = jsonEncode({
        'proxy-providers': {
          'main': {'type': 'http', 'url': 'https://example.invalid/nodes.yaml'},
        },
        'proxy-groups': [
          {'name': 'Proxy', 'type': 'select', 'use': ['main']},
        ],
        'rules': ['MATCH,Proxy'],
      });
      expect(detectServerFormat(providersJson), ServerFormat.clashYaml);
      expect(
        resolveVpnBackend(
          config: providersJson,
          preference: AppSettings.vpnCoreAuto,
          mihomoAvailable: true,
        ).backend,
        VpnBackend.mihomo,
      );
    });

    test('clash в json-форме не принимается за конфиг xray', () {
      // У обоих корень `{`, различает их ключ: `proxies` против `outbounds`.
      final clashJson = jsonEncode({
        'proxies': [
          {
            'name': 'NL',
            'type': 'vless',
            'server': 'nl.example',
            'port': 443,
            'uuid': 'uuid',
          },
        ],
        'rules': ['MATCH,DIRECT'],
      });
      expect(detectServerFormat(clashJson), ServerFormat.clashYaml);
    });
  });

  group('выбор ядра', () {
    VpnBackendChoice choose(
      String config, {
      String preference = AppSettings.vpnCoreAuto,
      bool mihomo = true,
    }) =>
        resolveVpnBackend(
          config: config,
          preference: preference,
          mihomoAvailable: mihomo,
        );

    test('auto: ссылку берёт xray, готовый конфиг — своё ядро', () {
      expect(choose(link).backend, VpnBackend.xray);
      expect(choose(xrayJson).backend, VpnBackend.xray);
      expect(choose(clashYaml).backend, VpnBackend.mihomo);
      expect(choose(awg).backend, VpnBackend.awg);
      expect(choose(chain).backend, VpnBackend.xray);
      // auto ничего не «пропускает»: пользователь ядро и не выбирал.
      for (final config in [link, xrayJson, clashYaml, awg, chain]) {
        expect(choose(config).skip, isNull, reason: config);
      }
    });

    test('ручной выбор действует только на ссылку', () {
      expect(
        choose(link, preference: AppSettings.vpnCoreMihomo).backend,
        VpnBackend.mihomo,
      );
      expect(
        choose(link, preference: AppSettings.vpnCoreXray).backend,
        VpnBackend.xray,
      );
    });

    test('несовпадение выбора и формата НАЗЫВАЕТСЯ, а не молчит', () {
      expect(
        choose(xrayJson, preference: AppSettings.vpnCoreMihomo).skip,
        VpnCoreSkip.customConfig,
      );
      expect(
        choose(chain, preference: AppSettings.vpnCoreMihomo).skip,
        VpnCoreSkip.chain,
      );
      expect(
        choose(clashYaml, preference: AppSettings.vpnCoreXray).skip,
        VpnCoreSkip.clashConfig,
      );
      expect(
        choose(awg, preference: AppSettings.vpnCoreMihomo).skip,
        VpnCoreSkip.amneziaWg,
      );
    });

    test('без mihomo на платформе: ссылка на xray, clash — честный отказ', () {
      final forLink = choose(link, preference: AppSettings.vpnCoreMihomo, mihomo: false);
      expect(forLink.backend, VpnBackend.xray);
      expect(forLink.skip, VpnCoreSkip.platform);

      // Формат, который умеет только отсутствующее ядро: подменять его другим
      // нельзя — чужой формат оно не разберёт.
      final forClash = choose(clashYaml, mihomo: false);
      expect(forClash.backend, VpnBackend.mihomo);
      expect(forClash.skip, VpnCoreSkip.platform);
    });

    test('у каждой причины есть текст для лога', () {
      for (final skip in VpnCoreSkip.values) {
        expect(vpnCoreSkipLogReason(skip), isNotEmpty);
      }
    });
  });
}
