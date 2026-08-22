import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/removed_tls_fields.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

/// `allowInsecure` ядро отвергает безусловно (26.7.28,
/// `infra/conf/transport_security.go`), и падает при этом разбор ВСЕГО конфига.
/// То есть один сервер с `insecure=1` в подписке лишал связи все остальные, а
/// наружу это выглядело как «SOCKS port not ready».
void main() {
  setUp(() => Socks5Credentials().init('u', 'p'));

  Map<String, dynamic> tlsOf(String config) {
    final stream = ((jsonDecode(config) as Map)['outbounds'] as List)
        .cast<Map<String, dynamic>>()
        .first['streamSettings'] as Map<String, dynamic>;
    return stream['tlsSettings'] as Map<String, dynamic>;
  }

  group('ссылки не эмитят allowInsecure', () {
    // Панели пишут этот флаг тремя разными именами.
    for (final flag in ['insecure=1', 'allowInsecure=true', 'skip-cert-verify=1']) {
      test('vless, $flag', () {
        final tls = tlsOf(ConfigGeneratorV2.generateConfig(
          'vless://uuid@example.com:443?type=tcp&security=tls&sni=example.com&$flag',
          const AppSettings(),
        ));
        expect(tls.containsKey('allowInsecure'), isFalse);
        // Остальное из ссылки на месте — выкидываем ровно одно поле.
        expect(tls['serverName'], 'example.com');
      });
    }

    test('trojan', () {
      final tls = tlsOf(ConfigGeneratorV2.generateConfig(
        'trojan://pass@t.example:8443?sni=t.example&insecure=1',
        const AppSettings(),
      ));
      expect(tls.containsKey('allowInsecure'), isFalse);
    });

    test('hysteria2', () {
      final tls = tlsOf(ConfigGeneratorV2.generateConfig(
        'hysteria2://token@hy.example:443?sni=hy.example&insecure=1',
        const AppSettings(),
      ));
      expect(tls.containsKey('allowInsecure'), isFalse);
    });

    test('vmess', () {
      final payload = base64.encode(utf8.encode(jsonEncode({
        'v': '2',
        'add': 'v.example',
        'port': '443',
        'id': '11111111-1111-1111-1111-111111111111',
        'net': 'tcp',
        'tls': 'tls',
        'sni': 'v.example',
        'allowInsecure': 'true',
      })));
      final tls = tlsOf(ConfigGeneratorV2.generateConfig(
        'vmess://$payload',
        const AppSettings(),
      ));
      expect(tls.containsKey('allowInsecure'), isFalse);
    });
  });

  group('stripRemovedTlsFields', () {
    test('вычищает поле с любой глубины и считает выброшенное', () {
      final config = {
        'outbounds': [
          {
            'streamSettings': {
              'tlsSettings': {'serverName': 'a', 'allowInsecure': true},
            },
          },
          {
            'streamSettings': {
              'tlsSettings': {'serverName': 'b'},
            },
          },
        ],
        'inbounds': [
          {
            'streamSettings': {
              'tlsSettings': {'allowInsecure': false},
            },
          },
        ],
      };

      expect(stripRemovedTlsFields(config), 2);
      expect(jsonEncode(config), isNot(contains('allowInsecure')));
      // Соседние поля не задеты.
      expect(jsonEncode(config), contains('"serverName":"a"'));
    });

    test('чистый конфиг не трогает', () {
      final config = {
        'outbounds': [
          {'streamSettings': {'tlsSettings': {'serverName': 'a'}}},
        ],
      };
      final before = jsonEncode(config);
      expect(stripRemovedTlsFields(config), 0);
      expect(jsonEncode(config), before);
    });
  });

  // Готовый конфиг отдаётся ядру почти как есть, поэтому авторское
  // `allowInsecure` доезжало бы до ядра и роняло всю сессию.
  group('готовый (custom) конфиг', () {
    String authorConfig() => jsonEncode({
          'outbounds': [
            {
              'tag': 'proxy',
              'protocol': 'vless',
              'settings': {
                'address': 'c.example',
                'port': 443,
                'id': '11111111-1111-1111-1111-111111111111',
              },
              'streamSettings': {
                'network': 'tcp',
                'security': 'tls',
                'tlsSettings': {
                  'serverName': 'c.example',
                  'allowInsecure': true,
                },
              },
            },
          ],
        });

    test('сессия: поле не доезжает до ядра', () {
      final config = ConfigGeneratorV2.generateConfig(
        authorConfig(),
        const AppSettings(),
      );
      expect(config, isNot(contains('allowInsecure')));
      expect(config, contains('c.example'));
    });

    test('пинг: тоже не доезжает', () {
      final config = ConfigGeneratorV2.generatePingConfig(
        authorConfig(),
        const AppSettings(),
        socksPort: 28150,
      );
      expect(config, isNot(contains('allowInsecure')));
    });
  });
}
