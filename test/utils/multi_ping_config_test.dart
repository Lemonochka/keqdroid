import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';
import 'package:keqdroid/utils/multi_ping_config.dart';
import 'package:keqdroid/utils/proxy_chain.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

// Общий конфиг замера: вся пачка меряется одним ядром вместо ядра на сервер.
//
// Всё ценное здесь про то, чтобы пробы не перепутались между собой. Теги у
// серверов одинаковые (proxy, direct, socks-in), и склейка обязана их
// развести; правило без inboundTag действует на весь конфиг, то есть адрес
// одного сервера уводил бы в direct чужую пробу, а её catch-all в чужой
// прокси. Такая ошибка не падает, она молча меряет не тот сервер.
String _xraySingle({required String serverAddress, String? dialerProxy}) =>
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
        if (dialerProxy != null) {'protocol': 'freedom', 'tag': dialerProxy},
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
      merged =
          jsonDecode(
                MultiPingConfig.mergeXray([
                  (
                    id: 'a',
                    configJson: _xraySingle(serverAddress: 'a.example'),
                    port: 3001,
                  ),
                  (
                    id: 'b',
                    configJson: _xraySingle(serverAddress: 'b.example'),
                    port: 3002,
                  ),
                ]),
              )
              as Map<String, dynamic>;
    });

    test('инбаунд на пробу, со своим портом', () {
      final inbounds = (merged['inbounds'] as List)
          .cast<Map<String, dynamic>>();
      expect(inbounds.map((i) => i['tag']), ['socks-in-0', 'socks-in-1']);
      expect(inbounds.map((i) => i['port']), [3001, 3002]);
    });

    test('доменные DNS-серверы соседних проб не теряются при склейке', () {
      final probeA = jsonEncode({
        'dns': {
          'servers': [
            'https+local://1.1.1.1/dns-query',
            {
              'address': 'localhost',
              'domains': ['domain:local'],
            },
          ],
          'queryStrategy': 'UseIPv4',
        },
        'inbounds': [
          {'tag': 'in', 'port': 1, 'listen': '127.0.0.1', 'protocol': 'http'},
        ],
        'outbounds': [
          {'tag': 'proxy', 'protocol': 'freedom'},
        ],
        'routing': {
          'domainStrategy': 'AsIs',
          'rules': const <Map<String, dynamic>>[],
        },
      });
      final probeB = jsonEncode({
        'dns': {
          'servers': [
            {
              'address': 'tcp+local://77.88.8.8:53',
              'domains': ['full:edge.example.net'],
              'skipFallback': true,
            },
            'https+local://1.1.1.1/dns-query',
          ],
          'queryStrategy': 'UseIPv4',
        },
        'inbounds': [
          {'tag': 'in', 'port': 1, 'listen': '127.0.0.1', 'protocol': 'http'},
        ],
        'outbounds': [
          {'tag': 'proxy', 'protocol': 'freedom'},
        ],
        'routing': {
          'domainStrategy': 'AsIs',
          'rules': const <Map<String, dynamic>>[],
        },
      });
      final combined =
          jsonDecode(
                MultiPingConfig.mergeXray([
                  (id: 'a', configJson: probeA, port: 3101),
                  (id: 'b', configJson: probeB, port: 3102),
                ]),
              )
              as Map<String, dynamic>;
      final servers = (combined['dns'] as Map)['servers'] as List;
      expect(servers.first, {
        'address': 'tcp+local://77.88.8.8:53',
        'domains': ['full:edge.example.net'],
        'skipFallback': true,
      });
      expect(servers[1], 'https+local://1.1.1.1/dns-query');
      expect((servers.last as Map)['address'], 'localhost');
    });

    test('теги аутбаундов разведены', () {
      final tags = [
        for (final o in (merged['outbounds'] as List)) (o as Map)['tag'],
      ];
      expect(tags, [
        'proxy-0',
        'direct-0',
        'block-0',
        'proxy-1',
        'direct-1',
        'block-1',
      ]);
      expect(tags.toSet().length, tags.length);
    });

    test('каждое правило привязано к своей пробе', () {
      final rules = (merged['routing']['rules'] as List)
          .cast<Map<String, dynamic>>();
      for (final rule in rules) {
        expect(
          rule['inboundTag'],
          isA<List<Object?>>(),
          reason: 'правило без inboundTag ловит чужие пробы',
        );
      }
      final catchAll = rules.where((r) => r['network'] == 'tcp,udp').toList();
      expect(catchAll.length, 2);
      expect(catchAll[0]['inboundTag'], ['socks-in-0']);
      expect(catchAll[0]['outboundTag'], 'proxy-0');
      expect(catchAll[1]['inboundTag'], ['socks-in-1']);
      expect(catchAll[1]['outboundTag'], 'proxy-1');
    });

    test('direct-правило на адрес сервера не трогает соседнюю пробу', () {
      final rules = (merged['routing']['rules'] as List)
          .cast<Map<String, dynamic>>();
      final directRules = rules
          .where((r) => r['outboundTag'].toString().startsWith('direct'))
          .toList();
      expect(directRules.length, 2);
      expect(directRules[0]['domain'], ['full:a.example']);
      expect(directRules[0]['inboundTag'], ['socks-in-0']);
      expect(directRules[1]['domain'], ['full:b.example']);
      expect(directRules[1]['inboundTag'], ['socks-in-1']);
    });

    test('dialerProxy ведёт в аутбаунд своей пробы', () {
      final withFragment =
          jsonDecode(
                MultiPingConfig.mergeXray([
                  (
                    id: 'a',
                    configJson: _xraySingle(
                      serverAddress: 'a.example',
                      dialerProxy: 'fragment',
                    ),
                    port: 3001,
                  ),
                  (
                    id: 'b',
                    configJson: _xraySingle(
                      serverAddress: 'b.example',
                      dialerProxy: 'fragment',
                    ),
                    port: 3002,
                  ),
                ]),
              )
              as Map<String, dynamic>;

      final outbounds = (withFragment['outbounds'] as List)
          .cast<Map<String, dynamic>>();
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
      merged =
          jsonDecode(
                MultiPingConfig.mergeMihomo([
                  (id: 'a', configJson: _mihomoSingle('a.example'), port: 3001),
                  (id: 'b', configJson: _mihomoSingle('b.example'), port: 3002),
                ], httpListeners: false),
              )
              as Map<String, dynamic>;
    });

    test('прокси на сервер, имена разведены', () {
      final proxies = (merged['proxies'] as List).cast<Map<String, dynamic>>();
      expect(proxies.map((p) => p['name']), ['proxy-0', 'proxy-1']);
      expect(proxies.map((p) => p['server']), ['a.example', 'b.example']);
    });

    test('листенер на пробу со своим набором правил', () {
      final listeners = (merged['listeners'] as List)
          .cast<Map<String, dynamic>>();
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
      // Без rules mihomo считает конфиг неполным, а листенеры ходят по своим.
      expect(merged['rules'], ['MATCH,DIRECT']);
    });

    test('десктопная проба слушает http', () {
      final http =
          jsonDecode(
                MultiPingConfig.mergeMihomo([
                  (id: 'a', configJson: _mihomoSingle('a.example'), port: 3001),
                ], httpListeners: true),
              )
              as Map<String, dynamic>;
      expect((http['listeners'] as List).first['type'], 'http');
    });
  });

  // 31.10.2026: проба строилась только из ссылки, и сервер из Clash-подписки или файла не пинговался вовсе
  group('готовый Clash', () {
    const single =
        '{"name":"DE","proxies":[{"name":"DE","type":"hysteria2",'
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

    test(
      'у профиля с группой проба идёт в группу, имена двух проб разведены',
      () {
        final merged =
            jsonDecode(
                  MultiPingConfig.mergeMihomo([
                    (id: 'a', configJson: probe(single, 3001), port: 3001),
                    (id: 'b', configJson: probe(profile, 3002), port: 3002),
                  ], httpListeners: false),
                )
                as Map<String, dynamic>;
        final proxies = [for (final p in merged['proxies'] as List) p['name']];
        final groups = (merged['proxy-groups'] as List)
            .cast<Map<Object?, Object?>>();
        expect(proxies.toSet(), hasLength(proxies.length));
        expect(groups.single['name'], '${MihomoConfigGen.proxyName}-1');
        expect(groups.single['proxies'], everyElement(isIn(proxies)));
        expect(merged['sub-rules'], {
          'probe-0': ['MATCH,${MihomoConfigGen.proxyName}-0'],
          'probe-1': ['MATCH,${MihomoConfigGen.proxyName}-1'],
        });
      },
    );

    // 02.11.2026: узлы Clash-подписки с пробелом по краю имени не пинговались, проба искала их без пробела
    test('узел с пробелом по краю имени пробу строит', () {
      for (final name in [' DE', 'DE ']) {
        final spaced = single.replaceFirst(
          '"proxies":[{"name":"DE"',
          '"proxies":[{"name":"$name"',
        );
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
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            isNot(contains('proxy-providers')),
          ),
        ),
      );
    });

    test(
      'узлы из proxy-providers до подключения не известны: причина названа',
      () {
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
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('proxy-providers'),
            ),
          ),
        );
      },
    );
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

    Map<String, dynamic> mihomo({String? bind}) =>
        jsonDecode(
              MultiPingConfig.mergeMihomo([
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
              ], httpListeners: true),
            )
            as Map<String, dynamic>;

    Map<String, dynamic> xray({String? bind}) =>
        jsonDecode(
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
            )
            as Map<String, dynamic>;

    test('mihomo: привязка к сетевой карте доезжает до общего конфига', () {
      expect(mihomo(bind: iface)['interface-name'], iface);
    });

    test('mihomo: без привязки ключа нет, как на Android', () {
      expect(mihomo().containsKey('interface-name'), isFalse);
    });

    test('mihomo: листенеры http, проба на ПК говорит CONNECT', () {
      final listeners = (mihomo()['listeners'] as List)
          .cast<Map<Object?, Object?>>();
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
      final inbounds = (xray()['inbounds'] as List)
          .cast<Map<Object?, Object?>>();
      expect(inbounds.map((i) => i['protocol']), ['http', 'http']);
      expect(inbounds.map((i) => i['port']), [3001, 3002]);
    });
  });

  group('готовый Xray JSON в пачке', () {
    const uuid = '00000000-0000-4000-8000-000000000000';
    final untaggedJson = jsonEncode({
      'outbounds': [
        {
          'protocol': 'vless',
          'settings': {
            'vnext': [
              {
                'address': '198.51.100.70',
                'port': 443,
                'users': [
                  {'id': uuid, 'encryption': 'none'},
                ],
              },
            ],
          },
          'streamSettings': {
            'network': 'tcp',
            'security': 'tls',
            'tlsSettings': {'serverName': 'u.example'},
          },
        },
        {'protocol': 'freedom'},
        {'protocol': 'dns', 'tag': 'dns-out'},
      ],
    });
    final chainedJson = jsonEncode({
      'outbounds': [
        {
          'tag': 'exit',
          'protocol': 'trojan',
          'settings': {
            'servers': [
              {'address': '198.51.100.71', 'port': 443, 'password': 'secret'},
            ],
          },
          'streamSettings': {
            'network': 'tcp',
            'security': 'tls',
            'tlsSettings': {'serverName': 'exit.example'},
            'sockopt': {'dialerProxy': 'relay'},
          },
        },
        {
          'tag': 'relay',
          'protocol': 'vless',
          'settings': {
            'vnext': [
              {
                'address': '198.51.100.72',
                'port': 443,
                'users': [
                  {'id': uuid, 'encryption': 'none'},
                ],
              },
            ],
          },
          'streamSettings': {
            'network': 'tcp',
            'security': 'tls',
            'tlsSettings': {'serverName': 'relay.example'},
          },
        },
        {'protocol': 'blackhole', 'tag': 'block'},
      ],
    });

    setUp(() => Socks5Credentials().init('u', 'p'));

    test(
      'безымянные выходы получают уникальные теги, цепочка и привязка целы',
      () {
        final mergedText = MultiPingConfig.mergeXray([
          (
            id: 'u',
            configJson: ConfigGeneratorV2.generatePingConfig(
              untaggedJson,
              const AppSettings(),
              socksPort: 3101,
              httpInbound: true,
              outboundInterface: 'Ethernet',
            ),
            port: 3101,
          ),
          (
            id: 'c',
            configJson: ConfigGeneratorV2.generatePingConfig(
              chainedJson,
              const AppSettings(),
              socksPort: 3102,
              httpInbound: true,
              outboundInterface: 'Ethernet',
            ),
            port: 3102,
          ),
        ]);
        final merged = jsonDecode(mergedText) as Map<String, dynamic>;
        final outbounds = (merged['outbounds'] as List)
            .cast<Map<String, dynamic>>();
        final tags = {
          for (final o in outbounds) o['tag']?.toString().trim() ?? '',
        };
        expect(tags, isNot(contains('')));
        expect(tags.length, outbounds.length);

        final dnsOut = outbounds.singleWhere((o) => o['tag'] == 'dns-out-0');
        expect(dnsOut.containsKey('streamSettings'), isFalse);

        final rules = ((merged['routing'] as Map)['rules'] as List)
            .cast<Map<String, dynamic>>();
        for (final rule in rules) {
          expect(tags, contains(rule['outboundTag']));
        }
        expect(rules.any((r) => r['outboundTag'] == 'proxy-0'), isTrue);
        final exit = outbounds.singleWhere((o) => o['tag'] == 'exit-1');
        expect(exit['streamSettings']['sockopt']['dialerProxy'], 'relay-1');
        final relay = outbounds.singleWhere((o) => o['tag'] == 'relay-1');
        expect(relay['streamSettings']['sockopt']['interface'], 'Ethernet');
      },
    );

    test(
      'живые xray.exe и mihomo.exe принимают пачки готовых конфигов без ошибок',
      () async {
        final xrayExe = File('assets/bin/windows/xray.exe');
        final mihomoExe = File('assets/bin/windows/mihomo.exe');
        if (!Platform.isWindows ||
            !xrayExe.existsSync() ||
            !mihomoExe.existsSync()) {
          return;
        }

        final dir = Directory.systemTemp.createTempSync('multi_ping_live');
        addTearDown(() {
          if (dir.existsSync()) dir.deleteSync(recursive: true);
        });
        for (final dat in ['geoip.dat', 'geosite.dat']) {
          final src = File('assets/bin/windows/$dat');
          if (src.existsSync()) {
            src.copySync('${dir.path}${Platform.pathSeparator}$dat');
          }
        }

        final chainUri = const ProxyChainConfig(
          name: 'hop',
          hops: [
            ProxyChainHop(
              name: 'entry',
              config:
                  'vless://00000000-0000-4000-8000-000000000000@198.51.100.80:443?encryption=none&type=tcp&security=tls&sni=a.example#a',
            ),
            ProxyChainHop(
              name: 'exit',
              config: 'trojan://pass@198.51.100.81:443?sni=b.example#b',
            ),
          ],
        ).encode();
        final xrayInputs = [untaggedJson, chainedJson, chainUri];
        final xrayMerged = MultiPingConfig.mergeXray([
          for (var i = 0; i < xrayInputs.length; i++)
            (
              id: 'x$i',
              configJson: ConfigGeneratorV2.generatePingConfig(
                xrayInputs[i],
                const AppSettings(),
                socksPort: 3201 + i,
                httpInbound: true,
              ),
              port: 3201 + i,
            ),
        ]);
        final xrayConfigFile = File(
          '${dir.path}${Platform.pathSeparator}ping_xray.json',
        )..writeAsStringSync(xrayMerged);
        final xrayRes = await Process.run(
          xrayExe.absolute.path,
          ['run', '-test', '-c', xrayConfigFile.path],
          environment: {'XRAY_LOCATION_ASSET': dir.path},
        );
        expect(
          xrayRes.exitCode,
          0,
          reason: '${xrayRes.stdout}\n${xrayRes.stderr}',
        );

        final wgPriv = base64Encode(List<int>.filled(32, 7));
        final wgPub = base64Encode(List<int>.filled(32, 9));
        final awg =
            '''
[Interface]
PrivateKey = $wgPriv
Address = 10.0.0.2/32
Jc = 4
Jmin = 40
Jmax = 70

[Peer]
PublicKey = $wgPub
Endpoint = 198.51.100.82:51820
AllowedIPs = 0.0.0.0/0
''';
        const clashProfile = '''
proxies:
  - {name: "NL", type: trojan, server: 198.51.100.91, port: 443, password: password}
  - {name: "FI", type: trojan, server: 198.51.100.92, port: 443, password: password}
proxy-groups:
  - {name: Select, type: select, proxies: [NL, FI]}
rules:
  - MATCH,Select
''';
        final mihomoInputs = [clashProfile, awg, chainUri];
        final mihomoMerged = MultiPingConfig.mergeMihomo([
          for (var i = 0; i < mihomoInputs.length; i++)
            (
              id: 'm$i',
              configJson: MihomoConfigGen.generatePingConfig(
                mihomoInputs[i],
                const AppSettings(),
                socksPort: 3301 + i,
                httpInbound: true,
              ),
              port: 3301 + i,
            ),
        ], httpListeners: true);
        final mihomoConfigFile = File(
          '${dir.path}${Platform.pathSeparator}ping_mihomo.yaml',
        )..writeAsStringSync(mihomoMerged);
        final mihomoRes = await Process.run(mihomoExe.absolute.path, [
          '-t',
          '-d',
          dir.path,
          '-f',
          mihomoConfigFile.path,
        ]);
        expect(
          mihomoRes.exitCode,
          0,
          reason: '${mihomoRes.stdout}\n${mihomoRes.stderr}',
        );
      },
    );
  });
}
