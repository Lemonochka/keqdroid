import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/desktop_tun.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

// узел, который не обслуживает имена: адрес ищет ядро, выходу пишется targetStrategy (жалоба 20.11)
const _uuid = '00000000-0000-4000-8000-000000000000';
const _link =
    'vless://$_uuid@198.51.100.40:443?type=tcp&security=tls&sni=pc.example#pc';

Map<String, dynamic> _vless(String tag, String address, [String? dialer]) => {
  'tag': tag,
  'protocol': 'vless',
  'settings': {
    'vnext': [
      {
        'address': address,
        'port': 443,
        'users': [
          {'id': _uuid, 'encryption': 'none'},
        ],
      },
    ],
  },
  'streamSettings': {
    'network': 'tcp',
    'security': 'tls',
    if (dialer != null) 'sockopt': {'dialerProxy': dialer},
  },
};

Map<String, dynamic> _gen(
  String input, {
  bool resolve = true,
  DesktopTunOptions? tun,
}) {
  Socks5Credentials().init('u', 'p');
  return jsonDecode(
        ConfigGeneratorV2.generateConfig(
          input,
          const AppSettings(),
          desktopTun: tun,
          resolveTargets: resolve,
        ),
      )
      as Map<String, dynamic>;
}

Map<String, Map<String, dynamic>> _byTag(Map<String, dynamic> config) => {
  for (final o in (config['outbounds'] as List).cast<Map<String, dynamic>>())
    (o['tag'] ?? '') as String: o,
};

void main() {
  test('a link: the server exit resolves to IPv4, local exits stay', () {
    final outbounds = _byTag(_gen(_link));
    expect(outbounds['proxy']!['targetStrategy'], 'UseIPv4');
    for (final o in outbounds.values) {
      if (o['tag'] == 'proxy') continue;
      expect(o.containsKey('targetStrategy'), isFalse, reason: '${o['tag']}');
    }
  });

  test('without the flag the config is exactly as before', () {
    final plain = _gen(_link, resolve: false);
    expect(jsonEncode(plain), isNot(contains('targetStrategy')));
    Socks5Credentials().init('u', 'p');
    expect(
      plain,
      jsonDecode(ConfigGeneratorV2.generateConfig(_link, const AppSettings())),
    );
  });

  test(
    'a ready JSON with a balancer: every provider exit, own choice kept',
    () {
      final config = _gen(
        jsonEncode({
          'outbounds': [
            _vless('proxy', '198.51.100.41'),
            _vless('proxy-2', '198.51.100.42'),
            {
              ..._vless('proxy-3', '198.51.100.43'),
              'targetStrategy': 'ForceIP',
            },
            {'tag': 'direct', 'protocol': 'freedom'},
            {'tag': 'block', 'protocol': 'blackhole'},
          ],
          'routing': {
            'balancers': [
              {
                'tag': 'auto',
                'selector': ['proxy'],
                'strategy': {'type': 'leastPing'},
              },
            ],
            'rules': [
              {'type': 'field', 'network': 'tcp,udp', 'balancerTag': 'auto'},
            ],
          },
        }),
      );
      final outbounds = _byTag(config);
      expect(outbounds['proxy']!['targetStrategy'], 'UseIPv4');
      expect(outbounds['proxy-2']!['targetStrategy'], 'UseIPv4');
      expect(outbounds['proxy-3']!['targetStrategy'], 'ForceIP');
      expect(outbounds['direct']!.containsKey('targetStrategy'), isFalse);
      expect(outbounds['block']!.containsKey('targetStrategy'), isFalse);
    },
  );

  test('a chain: the exit resolves, the hop under dialerProxy does not', () {
    final outbounds = _byTag(
      _gen(
        jsonEncode({
          'outbounds': [
            _vless('proxy', 'exit.example', 'hop'),
            _vless('hop', '198.51.100.44'),
          ],
        }),
      ),
    );
    expect(outbounds['proxy']!['targetStrategy'], 'UseIPv4');
    expect(outbounds['hop']!.containsKey('targetStrategy'), isFalse);
  });

  test('IPv6 through the VPN: the exit may get either family', () {
    final outbounds = _byTag(
      _gen(
        _link,
        tun: const DesktopTunOptions(
          windows: true,
          mtu: 9000,
          captureIpv6: true,
          passIpv6: true,
        ),
      ),
    );
    expect(outbounds['proxy']!['targetStrategy'], 'UseIP');
  });
}
