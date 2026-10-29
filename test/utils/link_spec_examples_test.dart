import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/services/subscription_service.dart';
import 'package:keqdroid/tunnel/vpn_backend.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';
import 'package:keqdroid/utils/vpn_core_support.dart';

Map<String, dynamic> _mihomo(String link) => MihomoConfigGen.buildProxies(link).first;

Map<String, dynamic> _xray(String link) =>
    ((jsonDecode(ConfigGeneratorV2.generateConfig(link, const AppSettings()))
            as Map)['outbounds'] as List)
        .first as Map<String, dynamic>;

void main() {
  setUp(() => Socks5Credentials().init('user', 'pass'));

  group('SOCKS5', () {
    const link = 'socks://dXNlcjpwYXNz@1.2.3.4:1080#proxy';

    test('импортируется из подписки и руками', () {
      expect(SubscriptionService.parseBodyForTest(link), [link]);
      final item = ServerItem.fromRaw(link);
      expect(item.protocol, 'socks');
      expect(item.address, '1.2.3.4');
      expect(item.port, 1080);
    });

    test('идёт на обоих ядрах', () {
      expect(backendsForLink(link), {VpnBackend.xray, VpnBackend.mihomo});
      expect(_mihomo(link), {
        'name': MihomoConfigGen.proxyName,
        'type': 'socks5',
        'server': '1.2.3.4',
        'port': 1080,
        'username': 'user',
        'password': 'pass',
        'udp': true,
      });
      final out = _xray(link);
      expect(out['protocol'], 'socks');
      expect(out['settings'], {
        'address': '1.2.3.4',
        'port': 1080,
        'user': 'user',
        'pass': 'pass',
      });
    });
  });
}
