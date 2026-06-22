import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/keqrnel_config.dart';

void main() {
  test('fromChain swaps the socks proxy outbound for an embedded xray engine',
      () {
    final singbox = jsonEncode({
      'inbounds': [
        {'type': 'tun', 'tag': 'tun-in'}
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
          {'protocol': 'dns', 'action': 'hijack-dns'}
        ],
        'final': 'proxy',
      },
    });
    final xray = jsonEncode({
      'outbounds': [
        {'protocol': 'vless', 'tag': 'vless-out'}
      ]
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
  });

  test('fromChain uses bare process name off Windows', () {
    final singbox = jsonEncode({
      'outbounds': [
        {'type': 'socks', 'tag': 'proxy'}
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
        {'tag': 'socks-in', 'port': 2080, 'protocol': 'socks'}
      ],
      'outbounds': [
        {'protocol': 'vless', 'tag': 'vless-out'}
      ],
    });
    final out = KeqrnelConfig.wrapXray(xray);
    final m = jsonDecode(out) as Map<String, dynamic>;
    final outbounds = (m['outbounds'] as List).cast<Map<String, dynamic>>();
    expect(outbounds, hasLength(1));
    expect(outbounds.first['type'], 'xray');
    // full xray config (incl. its own socks inbound) is embedded verbatim.
    final embedded = outbounds.first['xray'] as Map<String, dynamic>;
    expect((embedded['inbounds'] as List).first['tag'], 'socks-in');
    expect((embedded['outbounds'] as List).first['protocol'], 'vless');
    // no sing-box inbound: the embedded xray owns the socks listener.
    expect(m.containsKey('inbounds'), isFalse);
  });

  test('fromChain throws when there is no proxy outbound to replace', () {
    final singbox = jsonEncode({
      'outbounds': [
        {'type': 'direct', 'tag': 'direct'}
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
