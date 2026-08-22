import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/proxy_chain.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

const _de = 'vless://uuid-de@de.example.com:443?security=reality&pbk=pub&sid=aa&fp=chrome&sni=de.example.com&type=tcp#DE-1';
const _nl = 'trojan://pass@nl.example.com:8443?sni=nl.example.com&type=ws&path=/w#NL-2';
const _jp = 'ss://YWVzLTI1Ni1nY206cGFzcw@jp.example.com:8388#JP-3';

String _link(List<String> hops, {String name = 'chain'}) => ProxyChainConfig(
      name: name,
      hops: [for (final h in hops) ProxyChainHop(config: h)],
    ).encode();

Map<String, dynamic> _outboundByTag(Map<String, dynamic> config, String tag) =>
    (config['outbounds'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((o) => o['tag'] == tag);

String? _dialerProxyOf(Map<String, dynamic> outbound) {
  final stream = outbound['streamSettings'] as Map<String, dynamic>?;
  final sockopt = stream?['sockopt'] as Map<String, dynamic>?;
  return sockopt?['dialerProxy'] as String?;
}

void main() {
  const settings = AppSettings();
  setUp(() => Socks5Credentials().init('u', 'p'));

  group('ConfigGeneratorV2 proxy chain', () {
    test('exit keeps tag proxy and each hop dials through the previous one', () {
      final config = jsonDecode(
        ConfigGeneratorV2.generateConfig(_link([_de, _nl, _jp]), settings),
      ) as Map<String, dynamic>;

      final tags = (config['outbounds'] as List)
          .cast<Map<String, dynamic>>()
          .map((o) => o['tag'])
          .toList();
      // Выходной узел первым: в xray первый аутбаунд — основной.
      expect(tags, ['proxy', 'chain-0', 'chain-1', 'direct', 'block', 'dns-out']);

      // Вход набирается напрямую, дальше — через предыдущее звено.
      expect(_dialerProxyOf(_outboundByTag(config, 'chain-0')), isNull);
      expect(_dialerProxyOf(_outboundByTag(config, 'chain-1')), 'chain-0');
      expect(_dialerProxyOf(_outboundByTag(config, 'proxy')), 'chain-1');

      // Порядок узлов сохраняется: chain-0 — вход, proxy — выход.
      expect(
        (_outboundByTag(config, 'chain-0')['settings']
            as Map<String, dynamic>)['address'],
        'de.example.com',
      );
      expect(
        (_outboundByTag(config, 'proxy')['settings']
            as Map<String, dynamic>)['address'],
        'jp.example.com',
      );
    });

    test('per-node transport survives chaining', () {
      final config = jsonDecode(
        ConfigGeneratorV2.generateConfig(_link([_de, _nl]), settings),
      ) as Map<String, dynamic>;

      // Ради этого и выбран dialerProxy: proxySettings без transportLayer
      // выбросил бы reality/ws вместе со всем streamSettings узла.
      final entry = _outboundByTag(config, 'chain-0');
      expect(
        (entry['streamSettings'] as Map<String, dynamic>)['realitySettings'],
        isNotNull,
      );
      final exit = _outboundByTag(config, 'proxy');
      final exitStream = exit['streamSettings'] as Map<String, dynamic>;
      expect(exitStream['network'], 'ws');
      expect(exitStream['wsSettings'], isNotNull);
      expect((exitStream['sockopt'] as Map)['dialerProxy'], 'chain-0');
    });

    test('every node address is routed direct', () {
      final config = jsonDecode(
        ConfigGeneratorV2.generateConfig(
          _link([_de, _nl, _jp]),
          settings,
          resolvedServerIp: '203.0.113.7',
        ),
      ) as Map<String, dynamic>;

      final rules = ((config['routing'] as Map<String, dynamic>)['rules']
              as List)
          .cast<Map<String, dynamic>>();
      final directDomains = [
        for (final r in rules)
          if (r['outboundTag'] == 'direct' && r['domain'] is List)
            ...(r['domain'] as List).cast<String>(),
      ];
      final directIps = [
        for (final r in rules)
          if (r['outboundTag'] == 'direct' && r['ip'] is List)
            ...(r['ip'] as List).cast<String>(),
      ];

      expect(directIps, contains('203.0.113.7'));
      expect(directDomains, contains('full:de.example.com'));
      expect(directDomains, contains('full:nl.example.com'));
      expect(directDomains, contains('full:jp.example.com'));
    });

    test('routing still ends in the chain and inbounds are ours', () {
      final config = jsonDecode(
        ConfigGeneratorV2.generateConfig(_link([_de, _nl]), settings),
      ) as Map<String, dynamic>;

      final rules = ((config['routing'] as Map<String, dynamic>)['rules']
              as List)
          .cast<Map<String, dynamic>>();
      expect(rules.last['outboundTag'], 'proxy');

      final inbounds = (config['inbounds'] as List).cast<Map<String, dynamic>>();
      expect(inbounds.map((i) => i['tag']), containsAll(['socks-in', 'http-in']));
    });

    test('ping config runs the whole chain, not just the entry', () {
      final config = jsonDecode(
        ConfigGeneratorV2.generatePingConfig(
          _link([_de, _nl, _jp]),
          settings,
          socksPort: 28150,
          httpInbound: true,
        ),
      ) as Map<String, dynamic>;

      expect(_dialerProxyOf(_outboundByTag(config, 'proxy')), 'chain-1');
      expect(_dialerProxyOf(_outboundByTag(config, 'chain-1')), 'chain-0');
      final rules = ((config['routing'] as Map<String, dynamic>)['rules']
              as List)
          .cast<Map<String, dynamic>>();
      expect(rules.last['outboundTag'], 'proxy');
    });

    test('hysteria port hopping is dropped past the entry node', () {
      const hyEntry =
          'hysteria2://secret@hy.example.com:443?mport=20000-30000&sni=hy.example.com#HY-entry';
      const hyExit =
          'hysteria2://secret@hy2.example.com:443?mport=20000-30000&sni=hy2.example.com#HY-exit';
      final config = jsonDecode(
        ConfigGeneratorV2.generateConfig(_link([hyEntry, hyExit]), settings),
      ) as Map<String, dynamic>;

      Map<String, dynamic> hysteriaOf(String tag) =>
          ((_outboundByTag(config, tag)['streamSettings']
              as Map<String, dynamic>)['hysteriaSettings']
              as Map<String, dynamic>);

      // Внешнему узлу перебор портов оставляем — он звонит сам.
      expect(hysteriaOf('chain-0')['udphop'], isNotNull);
      // А вот за dialerProxy ядро отвечает «udphop requires being at the
      // outermost level» и роняет коннект целиком.
      expect(hysteriaOf('proxy')['udphop'], isNull);
    });

    test('single-node chain is still a valid config', () {
      final config = jsonDecode(
        ConfigGeneratorV2.generateConfig(_link([_de]), settings),
      ) as Map<String, dynamic>;

      final tags = (config['outbounds'] as List)
          .cast<Map<String, dynamic>>()
          .map((o) => o['tag'])
          .toList();
      expect(tags, ['proxy', 'direct', 'block', 'dns-out']);
      expect(_dialerProxyOf(_outboundByTag(config, 'proxy')), isNull);
    });
  });
}
