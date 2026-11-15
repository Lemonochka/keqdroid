import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';
import 'package:keqdroid/utils/multi_ping_config.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

/// Общий конфиг замера: весь батч меряется одним ядром вместо ядра на сервер.
///
/// Всё ценное здесь — про то, чтобы пробы не перепутались между собой. Теги у
/// серверов одинаковые (`proxy`, `direct`, `socks-in`), и склейка обязана их
/// развести; правило без `inboundTag` действует на весь конфиг, то есть адрес
/// одного сервера уводил бы в direct чужую пробу, а её catch-all — в чужой
/// прокси. Такая ошибка не падает, она молча меряет не тот сервер.
String _xraySingle({
  required String serverAddress,
  String? dialerProxy,
}) =>
    jsonEncode({
      'log': {'loglevel': 'none'},
      'dns': {
        'servers': ['localhost'],
      },
      'inbounds': [
        {
          'tag': 'socks-in',
          'port': 1,
          'listen': '127.0.0.1',
          'protocol': 'socks',
        },
      ],
      'outbounds': [
        {
          'tag': 'proxy',
          'protocol': 'vless',
          'settings': {'address': serverAddress, 'port': 443},
          if (dialerProxy != null)
            'streamSettings': {
              'sockopt': {'dialerProxy': dialerProxy},
            },
        },
        if (dialerProxy != null)
          {'protocol': 'freedom', 'tag': dialerProxy},
        {'protocol': 'freedom', 'tag': 'direct'},
        {'protocol': 'blackhole', 'tag': 'block'},
      ],
      'routing': {
        'domainStrategy': 'AsIs',
        'rules': [
          {
            'type': 'field',
            'domain': ['full:$serverAddress'],
            'outboundTag': 'direct',
          },
          {'type': 'field', 'outboundTag': 'proxy', 'network': 'tcp,udp'},
        ],
      },
    });

String _mihomoSingle(String serverAddress) => jsonEncode({
      'port': 1,
      'mode': 'rule',
      'dns': {'enable': true},
      'proxies': [
        {'name': 'proxy', 'type': 'vless', 'server': serverAddress, 'port': 443},
      ],
      'rules': ['MATCH,proxy'],
    });

void main() {
  group('xray', () {
    late Map<String, dynamic> merged;

    setUp(() {
      merged = jsonDecode(
        MultiPingConfig.mergeXray([
          (id: 'a', configJson: _xraySingle(serverAddress: 'a.example'), port: 3001),
          (id: 'b', configJson: _xraySingle(serverAddress: 'b.example'), port: 3002),
        ]),
      ) as Map<String, dynamic>;
    });

    test('инбаунд на пробу, со своим портом', () {
      final inbounds = (merged['inbounds'] as List).cast<Map<String, dynamic>>();
      expect(inbounds.map((i) => i['tag']), ['socks-in-0', 'socks-in-1']);
      expect(inbounds.map((i) => i['port']), [3001, 3002]);
    });

    test('теги аутбаундов разведены', () {
      final tags = [
        for (final o in (merged['outbounds'] as List)) (o as Map)['tag'],
      ];
      expect(tags, ['proxy-0', 'direct-0', 'block-0', 'proxy-1', 'direct-1', 'block-1']);
      expect(tags.toSet().length, tags.length);
    });

    test('каждое правило привязано к своей пробе', () {
      final rules = (merged['routing']['rules'] as List).cast<Map<String, dynamic>>();
      for (final rule in rules) {
        expect(rule['inboundTag'], isA<List>(), reason: 'правило без inboundTag ловит чужие пробы');
      }
      final catchAll = rules.where((r) => r['network'] == 'tcp,udp').toList();
      expect(catchAll.length, 2);
      expect(catchAll[0]['inboundTag'], ['socks-in-0']);
      expect(catchAll[0]['outboundTag'], 'proxy-0');
      expect(catchAll[1]['inboundTag'], ['socks-in-1']);
      expect(catchAll[1]['outboundTag'], 'proxy-1');
    });

    test('direct-правило на адрес сервера не трогает соседнюю пробу', () {
      final rules = (merged['routing']['rules'] as List).cast<Map<String, dynamic>>();
      final directRules = rules.where((r) => r['outboundTag'].toString().startsWith('direct')).toList();
      expect(directRules.length, 2);
      expect(directRules[0]['domain'], ['full:a.example']);
      expect(directRules[0]['inboundTag'], ['socks-in-0']);
      expect(directRules[1]['domain'], ['full:b.example']);
      expect(directRules[1]['inboundTag'], ['socks-in-1']);
    });

    test('dialerProxy ведёт в аутбаунд своей пробы', () {
      final withFragment = jsonDecode(
        MultiPingConfig.mergeXray([
          (
            id: 'a',
            configJson: _xraySingle(serverAddress: 'a.example', dialerProxy: 'fragment'),
            port: 3001,
          ),
          (
            id: 'b',
            configJson: _xraySingle(serverAddress: 'b.example', dialerProxy: 'fragment'),
            port: 3002,
          ),
        ]),
      ) as Map<String, dynamic>;

      final outbounds = (withFragment['outbounds'] as List).cast<Map<String, dynamic>>();
      final first = outbounds.firstWhere((o) => o['tag'] == 'proxy-0');
      final second = outbounds.firstWhere((o) => o['tag'] == 'proxy-1');
      expect(first['streamSettings']['sockopt']['dialerProxy'], 'fragment-0');
      expect(second['streamSettings']['sockopt']['dialerProxy'], 'fragment-1');
    });

    test('пустой список — ошибка, а не пустой конфиг', () {
      expect(() => MultiPingConfig.mergeXray([]), throwsArgumentError);
    });
  });

  group('mihomo', () {
    late Map<String, dynamic> merged;

    setUp(() {
      merged = jsonDecode(
        MultiPingConfig.mergeMihomo(
          [
            (id: 'a', configJson: _mihomoSingle('a.example'), port: 3001),
            (id: 'b', configJson: _mihomoSingle('b.example'), port: 3002),
          ],
          httpListeners: false,
        ),
      ) as Map<String, dynamic>;
    });

    test('прокси на сервер, имена разведены', () {
      final proxies = (merged['proxies'] as List).cast<Map<String, dynamic>>();
      expect(proxies.map((p) => p['name']), ['proxy-0', 'proxy-1']);
      expect(proxies.map((p) => p['server']), ['a.example', 'b.example']);
    });

    test('листенер на пробу со своим набором правил', () {
      final listeners = (merged['listeners'] as List).cast<Map<String, dynamic>>();
      expect(listeners.map((l) => l['port']), ['3001', '3002']);
      expect(listeners.map((l) => l['rule']), ['probe-0', 'probe-1']);
      expect(listeners.every((l) => l['listen'] == '127.0.0.1'), isTrue);
    });

    test('набор правил ведёт в прокси своей пробы', () {
      expect(merged['sub-rules'], {
        'probe-0': ['MATCH,proxy-0'],
        'probe-1': ['MATCH,proxy-1'],
      });
    });

    test('основной набор правил есть, но никуда не ведёт', () {
      // Без `rules` mihomo считает конфиг неполным, а листенеры ходят по своим.
      expect(merged['rules'], ['MATCH,DIRECT']);
    });

    test('десктопная проба слушает http', () {
      final http = jsonDecode(
        MultiPingConfig.mergeMihomo(
          [(id: 'a', configJson: _mihomoSingle('a.example'), port: 3001)],
          httpListeners: true,
        ),
      ) as Map<String, dynamic>;
      expect((http['listeners'] as List).first['type'], 'http');
    });
  });

  // 31.10.2026: проба строилась только из ссылки, и сервер из Clash-подписки или файла не пинговался вовсе
  group('готовый Clash', () {
    const single = '{"name":"DE","proxies":[{"name":"DE","type":"hysteria2",'
        '"server":"198.51.100.90","port":443,"password":"password"}],'
        '"rules":["MATCH,DE"]}';
    const profile = '''
proxies:
  - {name: "NL", type: trojan, server: 198.51.100.91, port: 443, password: password}
  - {name: "FI", type: trojan, server: 198.51.100.92, port: 443, password: password}
proxy-groups:
  - {name: Select, type: select, proxies: [NL, FI]}
rules:
  - MATCH,Select
''';

    String probe(String config, int port) => MihomoConfigGen.generatePingConfig(
          config,
          const AppSettings(),
          socksPort: port,
        );

    test('проба одного узла ведёт в сам узел', () {
      final config = jsonDecode(probe(single, 3001)) as Map<String, dynamic>;
      final proxy = (config['proxies'] as List).single as Map;
      expect(proxy['name'], MihomoConfigGen.proxyName);
      expect(proxy['type'], 'hysteria2');
      expect(proxy['server'], '198.51.100.90');
      expect(config['rules'], ['MATCH,${MihomoConfigGen.proxyName}']);
    });

    test('у профиля с группой проба идёт в группу, имена двух проб разведены', () {
      final merged = jsonDecode(
        MultiPingConfig.mergeMihomo(
          [
            (id: 'a', configJson: probe(single, 3001), port: 3001),
            (id: 'b', configJson: probe(profile, 3002), port: 3002),
          ],
          httpListeners: false,
        ),
      ) as Map<String, dynamic>;
      final proxies = [for (final p in merged['proxies'] as List) p['name']];
      final groups = (merged['proxy-groups'] as List).cast<Map>();
      expect(proxies.toSet(), hasLength(proxies.length));
      expect(groups.single['name'], '${MihomoConfigGen.proxyName}-1');
      expect(groups.single['proxies'], everyElement(isIn(proxies)));
      expect(merged['sub-rules'], {
        'probe-0': ['MATCH,${MihomoConfigGen.proxyName}-0'],
        'probe-1': ['MATCH,${MihomoConfigGen.proxyName}-1'],
      });
    });

    // 02.11.2026: узлы Clash-подписки с пробелом по краю имени не пинговались, проба искала их без пробела
    test('узел с пробелом по краю имени пробу строит', () {
      for (final name in [' DE', 'DE ']) {
        final spaced = single.replaceFirst('"proxies":[{"name":"DE"', '"proxies":[{"name":"$name"');
        final config = jsonDecode(probe(spaced, 3001)) as Map<String, dynamic>;
        final proxy = (config['proxies'] as List).single as Map;
        expect(proxy['name'], MihomoConfigGen.proxyName, reason: '[$name]');
        expect(proxy['server'], '198.51.100.90');
        expect(config['rules'], ['MATCH,${MihomoConfigGen.proxyName}']);
      }
    });

    test('группа ведёт мимо конфига: причина не про proxy-providers', () {
      final broken = profile.replaceFirst('[NL, FI]', '[NL, Missing]');
      expect(
        () => probe(broken, 3001),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          isNot(contains('proxy-providers')),
        )),
      );
    });

    test('узлы из proxy-providers до подключения не известны: причина названа', () {
      const providers = '''
proxy-providers:
  main: {type: http, url: "https://provider.example/nodes.yaml"}
proxy-groups:
  - {name: Select, type: select, use: [main]}
rules:
  - MATCH,Select
''';
      expect(
        () => probe(providers, 3001),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('proxy-providers'),
        )),
      );
    });
  });

  // на ПК пачку меряет одно ядро так же, как на Android; в TUN на Windows его выход привязан к сетевой
  // карте (3b29d8f), и склейка обязана эту привязку донести, иначе REALITY с маской снова краснеет
  group('пачка на ПК', () {
    const iface = 'Ethernet';
    const uuid = '00000000-0000-4000-8000-000000000000';
    const links = [
      'vless://$uuid@198.51.100.40:443?type=tcp&security=reality'
          '&sni=decoy.example&pbk=publickey&sid=aabb&fp=chrome#de',
      'trojan://pass@198.51.100.41:8443?sni=tr.example&type=ws&path=%2Fw#nl',
    ];

    setUp(() => Socks5Credentials().init('u', 'p'));

    Map<String, dynamic> mihomo({String? bind}) => jsonDecode(
          MultiPingConfig.mergeMihomo(
            [
              for (var i = 0; i < links.length; i++)
                (
                  id: '$i',
                  configJson: MihomoConfigGen.generatePingConfig(
                    links[i],
                    const AppSettings(),
                    socksPort: 3001 + i,
                    httpInbound: true,
                    outboundInterface: bind,
                  ),
                  port: 3001 + i,
                ),
            ],
            httpListeners: true,
          ),
        ) as Map<String, dynamic>;

    Map<String, dynamic> xray({String? bind}) => jsonDecode(
          MultiPingConfig.mergeXray([
            for (var i = 0; i < links.length; i++)
              (
                id: '$i',
                configJson: ConfigGeneratorV2.generatePingConfig(
                  links[i],
                  const AppSettings(),
                  socksPort: 3001 + i,
                  httpInbound: true,
                  outboundInterface: bind,
                ),
                port: 3001 + i,
              ),
          ]),
        ) as Map<String, dynamic>;

    test('mihomo: привязка к сетевой карте доезжает до общего конфига', () {
      expect(mihomo(bind: iface)['interface-name'], iface);
    });

    test('mihomo: без привязки ключа нет, как на Android', () {
      expect(mihomo().containsKey('interface-name'), isFalse);
    });

    test('mihomo: листенеры http, проба на ПК говорит CONNECT', () {
      final listeners = (mihomo()['listeners'] as List).cast<Map>();
      expect(listeners.map((l) => l['type']), ['http', 'http']);
      expect(listeners.map((l) => l['port']), ['3001', '3002']);
    });

    test('xray: каждый выход наружу привязан, DNS пинга свой', () {
      final merged = xray(bind: iface);
      final proxies = (merged['outbounds'] as List)
          .cast<Map<String, dynamic>>()
          .where((o) => o['tag'].toString().startsWith('proxy-'))
          .toList();
      expect(proxies, hasLength(links.length));
      for (final proxy in proxies) {
        expect(proxy['streamSettings']['sockopt']['interface'], iface);
      }
      expect(
        (merged['dns'] as Map)['servers'],
        contains('https+local://1.1.1.1/dns-query'),
      );
    });

    test('xray: инбаунды http на своих портах', () {
      final inbounds = (xray()['inbounds'] as List).cast<Map>();
      expect(inbounds.map((i) => i['protocol']), ['http', 'http']);
      expect(inbounds.map((i) => i['port']), [3001, 3002]);
    });
  });
}
