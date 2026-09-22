import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/multi_ping_config.dart';

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
}
