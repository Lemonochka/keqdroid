import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/keqrnel_config.dart';

void main() {
  test(
    'fromChain swaps the socks proxy outbound for an embedded xray engine',
    () {
      final singbox = jsonEncode({
        'inbounds': [
          {'type': 'tun', 'tag': 'tun-in'},
        ],
        'outbounds': [
          {
            'type': 'socks',
            'tag': 'proxy',
            'server': '127.0.0.1',
            'server_port': 2080,
            'username': 'u',
            'password': 'p',
          },
          {'type': 'direct', 'tag': 'direct'},
          {'type': 'block', 'tag': 'block'},
        ],
        'route': {
          'rules': [
            {'protocol': 'dns', 'action': 'hijack-dns'},
          ],
          'final': 'proxy',
        },
      });
      final xray = jsonEncode({
        'outbounds': [
          {'protocol': 'vless', 'tag': 'vless-out'},
        ],
      });

      final merged = KeqrnelConfig.fromChain(
        singboxConfig: singbox,
        xrayConfig: xray,
        windows: true,
      );
      final m = jsonDecode(merged) as Map<String, dynamic>;
      final outbounds = (m['outbounds'] as List).cast<Map<String, dynamic>>();

      final proxy = outbounds.firstWhere((o) => o['tag'] == 'proxy');
      expect(proxy['type'], 'xray');
      expect(proxy['xray'], isA<Map<String, dynamic>>());
      expect((proxy['xray'] as Map)['outbounds'], isA<List>());

      // direct/block preserved; tun inbound untouched.
      expect(outbounds.any((o) => o['tag'] == 'direct'), isTrue);
      expect(outbounds.any((o) => o['tag'] == 'block'), isTrue);
      expect((m['inbounds'] as List).first['type'], 'tun');

      // self-bypass rule inserted first so keqrnel's egress to the server goes
      // direct instead of looping back into the TUN.
      final rules = (m['route'] as Map)['rules'] as List;
      expect((rules.first as Map)['process_name'], contains('keqrnel.exe'));
      expect((rules.first as Map)['outbound'], 'direct');
    },
  );

  test('fromChain uses bare process name off Windows', () {
    final singbox = jsonEncode({
      'outbounds': [
        {'type': 'socks', 'tag': 'proxy'},
      ],
      'route': {'rules': <Map<String, dynamic>>[]},
    });
    final merged = KeqrnelConfig.fromChain(
      singboxConfig: singbox,
      xrayConfig: '{"outbounds":[]}',
      windows: false,
    );
    final rules = (jsonDecode(merged) as Map)['route']['rules'] as List;
    expect((rules.first as Map)['process_name'], contains('keqrnel'));
  });

  test('wrapXray wraps the xray config in an embedded xray outbound', () {
    final xray = jsonEncode({
      'inbounds': [
        {'tag': 'socks-in', 'port': 2080, 'protocol': 'socks'},
      ],
      'outbounds': [
        {'protocol': 'vless', 'tag': 'vless-out'},
      ],
    });
    final out = KeqrnelConfig.wrapXray(xray);
    final m = jsonDecode(out) as Map<String, dynamic>;
    final outbounds = (m['outbounds'] as List).cast<Map<String, dynamic>>();
    expect(outbounds, hasLength(1));
    expect(outbounds.first['type'], 'xray');
    // xray outbound config is embedded without local listeners; keqrnel exposes
    // compatible sing-box inbounds and forwards them into embedded xray.
    final embedded = outbounds.first['xray'] as Map<String, dynamic>;
    expect(embedded.containsKey('inbounds'), isFalse);
    expect((embedded['outbounds'] as List).first['protocol'], 'vless');

    final inbounds = (m['inbounds'] as List).cast<Map<String, dynamic>>();
    expect(inbounds.first['type'], 'socks');
    expect(inbounds.first['tag'], 'socks-in');
    expect(inbounds.first['listen_port'], 2080);
  });

  test(
    'proxyWithStats carries LAN inbounds over with creds and source guard',
    () {
      final xray = jsonEncode({
        'inbounds': [
          {'tag': 'socks', 'port': 2080, 'listen': '127.0.0.1', 'protocol': 'socks'},
          {'tag': 'http', 'port': 2081, 'listen': '127.0.0.1', 'protocol': 'http'},
          {
            'tag': 'socks-lan',
            'port': 1080,
            'listen': '0.0.0.0',
            'protocol': 'socks',
            'settings': {
              'auth': 'password',
              'udp': true,
              'accounts': [
                {'user': 'keq', 'pass': 'droid'},
              ],
            },
          },
          {'tag': 'http-lan', 'port': 8080, 'listen': '0.0.0.0', 'protocol': 'http'},
        ],
        'outbounds': [
          {'protocol': 'vless', 'tag': 'vless-out'},
        ],
      });

      final out = KeqrnelConfig.proxyWithStats(
        xrayConfig: xray,
        socksPort: 2080,
        httpPort: 2081,
        clashPort: 9090,
      );
      final m = jsonDecode(out) as Map<String, dynamic>;
      final inbounds = (m['inbounds'] as List).cast<Map<String, dynamic>>();

      // loopback-листенеры — только socks-in/http-in от sing-box, без дублей
      // одноимённых xray-инбаундов на тех же портах.
      expect(inbounds.where((i) => i['listen'] == '127.0.0.1'), hasLength(2));

      final socksLan = inbounds.firstWhere((i) => i['tag'] == 'socks-lan');
      expect(socksLan['listen'], '0.0.0.0');
      expect(socksLan['listen_port'], 1080);
      expect(socksLan['users'], [
        {'username': 'keq', 'password': 'droid'},
      ]);
      final httpLan = inbounds.firstWhere((i) => i['tag'] == 'http-lan');
      expect(httpLan['listen_port'], 8080);
      expect(httpLan.containsKey('users'), isFalse);

      // source-guard: частные диапазоны → proxy, остальное на LAN-тегах → block.
      final rules =
          ((m['route'] as Map)['rules'] as List).cast<Map<String, dynamic>>();
      expect(rules, hasLength(2));
      expect(rules[0]['inbound'], ['socks-lan', 'http-lan']);
      expect(rules[0]['source_ip_cidr'], contains('192.168.0.0/16'));
      expect(rules[0]['outbound'], 'proxy');
      expect(rules[1], {
        'inbound': ['socks-lan', 'http-lan'],
        'outbound': 'block',
      });
      final outbounds = (m['outbounds'] as List).cast<Map<String, dynamic>>();
      expect(outbounds.any((o) => o['tag'] == 'block'), isTrue);

      // у встроенного xray инбаундов не остаётся вовсе.
      final proxy = outbounds.firstWhere((o) => o['tag'] == 'proxy');
      expect((proxy['xray'] as Map).containsKey('inbounds'), isFalse);
    },
  );

  test('proxyWithStats without LAN sharing keeps loopback-only layout', () {
    final xray = jsonEncode({
      'inbounds': [
        {'tag': 'socks', 'port': 2080, 'listen': '127.0.0.1', 'protocol': 'socks'},
      ],
      'outbounds': [
        {'protocol': 'vless', 'tag': 'vless-out'},
      ],
    });
    final out = KeqrnelConfig.proxyWithStats(
      xrayConfig: xray,
      socksPort: 2080,
      httpPort: 2081,
      clashPort: 9090,
    );
    final m = jsonDecode(out) as Map<String, dynamic>;
    final inbounds = (m['inbounds'] as List).cast<Map<String, dynamic>>();
    expect(inbounds, hasLength(2));
    expect(inbounds.every((i) => i['listen'] == '127.0.0.1'), isTrue);
    expect((m['route'] as Map).containsKey('rules'), isFalse);
    expect(
      ((m['outbounds'] as List).cast<Map<String, dynamic>>())
          .any((o) => o['tag'] == 'block'),
      isFalse,
    );
  });

  test('fromChain throws when there is no proxy outbound to replace', () {
    final singbox = jsonEncode({
      'outbounds': [
        {'type': 'direct', 'tag': 'direct'},
      ],
      'route': {'rules': <Map<String, dynamic>>[]},
    });
    expect(
      () => KeqrnelConfig.fromChain(
        singboxConfig: singbox,
        xrayConfig: '{}',
        windows: true,
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
