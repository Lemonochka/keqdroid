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

// примеры дословно из спецификаций: SIP002 (shadowsocks.org/doc/sip002.html) и Hysteria 2 URI Scheme
const _sip002Plugin =
    'ss://YWVzLTEyOC1nY206dGVzdA@192.168.100.1:8888/?plugin=obfs-local%3Bobfs%3Dhttp#Example2';
const _sip002Plain =
    'ss://2022-blake3-aes-256-gcm:YctPZ6U7xPPcU%2Bgp3u%2B0tx%2FtRizJN9K8y%2BuKlW2qjlI%3D@192.168.100.1:8888#Example3';
const _sip002PlainKey = 'YctPZ6U7xPPcU+gp3u+0tx/tRizJN9K8y+uKlW2qjlI=';
const _hy2Doc =
    'hysteria2://letmein@example.com/?insecure=1&obfs=salamander&obfs-password=gawrgura&pinSHA256=deadbeef&sni=real.example.com';

Map<String, dynamic> _mihomo(String link) => MihomoConfigGen.buildProxies(link).first;

Map<String, dynamic> _xray(String link) =>
    ((jsonDecode(ConfigGeneratorV2.generateConfig(link, const AppSettings()))
            as Map)['outbounds'] as List)
        .first as Map<String, dynamic>;

void main() {
  setUp(() => Socks5Credentials().init('user', 'pass'));

  group('Hysteria2 без порта', () {
    test('порт 443, как в спецификации, v2rayN и mihomo', () {
      for (final link in [
        _hy2Doc,
        'hysteria2://pw@hy2.example',
        'hy2://pw@hy2.example/?sni=real.example',
      ]) {
        expect(_mihomo(link)['port'], 443, reason: link);
        expect((_xray(link)['settings'] as Map)['port'], 443, reason: link);
      }
    });

    test('явный порт и явный ноль остаются как есть', () {
      expect(_mihomo('hysteria2://pw@hy2.example:8443/')['port'], 8443);
      expect(_mihomo('hysteria2://pw@hy2.example:0/')['port'], 0);
      expect((_xray('hysteria2://pw@hy2.example:0/')['settings'] as Map)['port'], 0);
    });
  });

  group('Shadowsocks по SIP002', () {
    test('с плагином после / порт не теряется', () {
      final proxy = _mihomo(_sip002Plugin);
      expect(proxy['port'], 8888);
      expect(proxy['plugin'], 'obfs');
    });

    test('незакодированный пароль 2022 раскодирован в обоих ядрах', () {
      expect(_mihomo(_sip002Plain)['password'], _sip002PlainKey);
      expect((_xray(_sip002Plain)['settings'] as Map)['password'], _sip002PlainKey);
    });
  });

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
