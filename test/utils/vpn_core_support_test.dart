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
      expect(choose(awg).backend, VpnBackend.mihomo);
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
        choose(awg, preference: AppSettings.vpnCoreXray).skip,
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

  // «Ссылку умеют оба» было неправдой. Оба ядра молча пропускают незнакомый
  // ключ, поэтому неверный выбор здесь не падает, а тихо уводит трафик не тем
  // транспортом: подключение якобы есть, сервер не отвечает. Ниже — те самые
  // случаи, где ядро решает содержимое ссылки, а не её формат.
  group('какое ядро берёт эту ссылку', () {
    const both = {VpnBackend.xray, VpnBackend.mihomo};
    const uuid = '00000000-0000-4000-8000-000000000000';
    const ssUser = 'YWVzLTI1Ni1nY206cGFzc3dvcmQ';
    String vmess(Map<String, String> fields) {
      final payload = jsonEncode({
        'v': '2',
        'ps': 'n',
        'add': '198.51.100.10',
        'port': '443',
        'id': uuid,
        ...fields,
      });
      return 'vmess://${base64.encode(utf8.encode(payload))}';
    }

    test('обычную ссылку по-прежнему берут оба', () {
      expect(backendsForLink(link), both);
      expect(
        backendsForLink('trojan://p@198.51.100.10:443?type=ws&security=tls'),
        both,
      );
      expect(backendsForLink(vmess({'net': 'ws', 'tls': 'tls'})), both);
      expect(backendsForLink('ss://$ssUser@198.51.100.10:8388'), both);
    });

    test('плагин shadowsocks — только mihomo', () {
      expect(
        backendsForLink(
          'ss://$ssUser@198.51.100.10:8388'
          '?plugin=obfs-local%3Bobfs%3Dhttp%3Bobfs-host%3Dobfs.example',
        ),
        {VpnBackend.mihomo},
      );
    });

    test('UDP внутри TCP у shadowsocks — только mihomo', () {
      for (final query in ['uot=1', 'udp-over-tcp=true']) {
        expect(
          backendsForLink('ss://$ssUser@198.51.100.10:8388?$query'),
          {VpnBackend.mihomo},
          reason: query,
        );
      }
    });

    test('транспорт h2 — только mihomo: xray 26 его снёс', () {
      expect(
        backendsForLink('vless://$uuid@198.51.100.10:443?type=http'),
        {VpnBackend.mihomo},
      );
      expect(backendsForLink(vmess({'net': 'h2'})), {VpnBackend.mihomo});
    });

    test('mKCP и чужой xhttp — только xray', () {
      expect(
        backendsForLink('vless://$uuid@198.51.100.10:443?type=kcp'),
        {VpnBackend.xray},
      );
      expect(backendsForLink(vmess({'net': 'xhttp'})), {VpnBackend.xray});
      expect(
        backendsForLink('trojan://p@198.51.100.10:443?type=xhttp'),
        {VpnBackend.xray},
      );
      // У VLESS xhttp есть и у mihomo — эта ссылка по-прежнему для обоих.
      expect(
        backendsForLink('vless://$uuid@198.51.100.10:443?type=xhttp'),
        both,
      );
    });

    // Маски finalmask (`fm` у 3X-UI) — только у xray: у mihomo их нет вовсе.
    test('ссылка с масками fm — только xray', () {
      final fm = Uri.encodeQueryComponent('{"udp":[{"type":"mkcp-legacy"}]}');
      expect(
        backendsForLink('vless://$uuid@198.51.100.10:443?type=tcp&fm=$fm'),
        {VpnBackend.xray},
      );
      expect(
        backendsForLink('trojan://password@198.51.100.10:443?fm=$fm'),
        {VpnBackend.xray},
      );
    });

    test('HTTP-маскировка у trojan — только xray', () {
      expect(
        backendsForLink(
          'trojan://p@198.51.100.10:443?type=tcp&security=tls&headerType=http',
        ),
        {VpnBackend.xray},
      );
      // У VLESS и VMess `http-opts` есть — эти ссылки по-прежнему для обоих.
      expect(
        backendsForLink('vless://$uuid@198.51.100.10:443?headerType=http'),
        both,
      );
      expect(backendsForLink(vmess({'net': 'tcp', 'type': 'http'})), both);
    });

    test('TUIC — только mihomo: у xray такого аутбаунда нет', () {
      expect(
        backendsForLink('tuic://uuid:pwd@198.51.100.30:443?sni=t.example'),
        {VpnBackend.mihomo},
      );
    });

    test('нечитаемую ссылку не судим — её развернёт генератор', () {
      expect(backendsForLink('vmess://не-base64'), both);
      expect(backendsForLink('какая-то строка'), both);
    });

    test('выбор ядра мимо правила виден причиной, а не молчанием', () {
      const ss = 'ss://$ssUser@198.51.100.10:8388?plugin=obfs-local%3Bobfs%3Dhttp';
      final onXray = resolveVpnBackend(
        config: ss,
        preference: AppSettings.vpnCoreXray,
        mihomoAvailable: true,
      );
      expect(onXray.backend, VpnBackend.mihomo);
      expect(onXray.skip, VpnCoreSkip.linkMihomoOnly);

      const kcp = 'vless://$uuid@198.51.100.10:443?type=kcp';
      final onMihomo = resolveVpnBackend(
        config: kcp,
        preference: AppSettings.vpnCoreMihomo,
        mihomoAvailable: true,
      );
      expect(onMihomo.backend, VpnBackend.xray);
      expect(onMihomo.skip, VpnCoreSkip.linkXrayOnly);

      // auto ничего не «пропускает» и здесь: ядро выбирал не пользователь.
      expect(
        resolveVpnBackend(
          config: kcp,
          preference: AppSettings.vpnCoreAuto,
          mihomoAvailable: true,
        ).skip,
        isNull,
      );
    });
  });
}
