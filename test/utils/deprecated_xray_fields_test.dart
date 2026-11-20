import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/custom_xray_config.dart';
import 'package:keqdroid/utils/deprecated_xray_fields.dart';

/// Поля, которые xray объявил к удалению, в готовых конфигах провайдеров
/// переводятся в новую запись по правилам самого ядра (xray 26.9.9,
/// `infra/conf/dns_proxy.go`, `xray.go`, `transport_method.go`). После удаления
/// поля ядро отказалось бы запускать такой конфиг целиком.
void main() {
  Map<String, dynamic> configWith(Map<String, dynamic> outbound) => {
    'outbounds': [outbound],
  };

  Map<String, dynamic> migrated(Map<String, dynamic> outbound) {
    final config = configWith(
      jsonDecode(jsonEncode(outbound)) as Map<String, dynamic>,
    );
    migrateDeprecatedXrayFields(config);
    return (config['outbounds'] as List).first as Map<String, dynamic>;
  }

  group('dns-аутбаунд: nonIPQuery и blockTypes → rules', () {
    Object? rulesFor(Map<String, dynamic> settings) =>
        (migrated({
              'protocol': 'dns',
              'tag': 'dns-out',
              'settings': settings,
            })['settings']
            as Map)['rules'];

    test('reject: A/AAAA в DNS-модуль, остальное REFUSED', () {
      expect(rulesFor({'nonIPQuery': 'reject'}), [
        {'action': 'hijack', 'qType': '1,28'},
        {'action': 'return', 'rCode': 5},
      ]);
    });

    test('drop и skip', () {
      expect(rulesFor({'nonIPQuery': 'drop'}), [
        {'action': 'hijack', 'qType': '1,28'},
        {'action': 'drop'},
      ]);
      expect(rulesFor({'nonIPQuery': 'skip'}), [
        {'action': 'hijack', 'qType': '1,28'},
        {'action': 'direct'},
      ]);
    });

    // Без nonIPQuery ядро считает режим reject — и блокируемые типы тоже
    // отвечает REFUSED, а не молчанием.
    test('blockTypes без режима — первым правилом, с REFUSED', () {
      expect(
        rulesFor({
          'blockTypes': [65, 28],
        }),
        [
          {'action': 'return', 'rCode': 5, 'qType': '65,28'},
          {'action': 'hijack', 'qType': '1,28'},
          {'action': 'return', 'rCode': 5},
        ],
      );
    });

    test('blockTypes при drop — молчанием', () {
      expect(
        rulesFor({
          'nonIPQuery': 'drop',
          'blockTypes': [65],
        }),
        [
          {'action': 'drop', 'qType': '65'},
          {'action': 'hijack', 'qType': '1,28'},
          {'action': 'drop'},
        ],
      );
    });

    test('старых полей после перевода нет', () {
      final settings =
          migrated({
                'protocol': 'dns',
                'settings': {
                  'nonIPQuery': 'reject',
                  'blockTypes': [65],
                },
              })['settings']
              as Map;
      expect(settings.containsKey('nonIPQuery'), isFalse);
      expect(settings.containsKey('blockTypes'), isFalse);
    });

    // Такие конфиги ядро отвергает уже сегодня: перевод не должен ни чинить
    // ошибку автора, ни прятать её.
    for (final entry in {
      'вместе с rules': {'nonIPQuery': 'reject', 'rules': <Object>[]},
      'неизвестный режим': {'nonIPQuery': 'Reject'},
      'тип не числом': {
        'blockTypes': ['65'],
      },
      'тип вне диапазона': {
        'blockTypes': [70000],
      },
    }.entries) {
      test('не трогаем: ${entry.key}', () {
        final before = {'protocol': 'dns', 'settings': entry.value};
        expect(migrated(before), jsonDecode(jsonEncode(before)));
      });
    }
  });

  group('freedom: стратегия резолва → sockopt', () {
    test('domainStrategy уезжает в sockopt', () {
      final out = migrated({
        'protocol': 'freedom',
        'tag': 'direct',
        'settings': {'domainStrategy': 'UseIPv4'},
      });
      expect((out['settings'] as Map).containsKey('domainStrategy'), isFalse);
      expect(out['streamSettings'], {
        'sockopt': {'domainStrategy': 'UseIPv4'},
      });
    });

    test('targetStrategy главнее domainStrategy и переписывает sockopt', () {
      final out = migrated({
        'protocol': 'freedom',
        'settings': {
          'targetStrategy': 'ForceIPv6',
          'domainStrategy': 'UseIPv4',
        },
        'streamSettings': {
          'sockopt': {'domainStrategy': 'UseIP', 'mark': 255},
        },
      });
      expect(out['settings'], isEmpty);
      expect(out['streamSettings'], {
        'sockopt': {'domainStrategy': 'ForceIPv6', 'mark': 255},
      });
    });

    test('AsIs просто убирается, sockopt не появляется', () {
      final out = migrated({
        'protocol': 'freedom',
        'settings': {'domainStrategy': 'AsIs'},
      });
      expect(out['settings'], isEmpty);
      expect(out.containsKey('streamSettings'), isFalse);
    });

    // Свой targetStrategy у аутбаунда ядро ставит вместо поля freedom, а то
    // не читает вовсе.
    test('при targetStrategy аутбаунда поле freedom просто убирается', () {
      final out = migrated({
        'protocol': 'freedom',
        'targetStrategy': 'UseIPv6',
        'settings': {'domainStrategy': 'UseIPv4'},
      });
      expect(out['settings'], isEmpty);
      expect(out['targetStrategy'], 'UseIPv6');
      expect(out.containsKey('streamSettings'), isFalse);
    });

    test('неизвестное значение не трогаем', () {
      final before = {
        'protocol': 'freedom',
        'settings': {'domainStrategy': 'PreferIPv4'},
      };
      expect(migrated(before), jsonDecode(jsonEncode(before)));
    });
  });

  group('WebSocket: Host из headers → host', () {
    Map<String, dynamic> wsOf(Map<String, dynamic> ws) =>
        (migrated({
                  'protocol': 'vless',
                  'streamSettings': {'network': 'ws', 'wsSettings': ws},
                })['streamSettings']
                as Map)['wsSettings']
            as Map<String, dynamic>;

    test('заголовок становится полем, пустые headers уходят', () {
      expect(
        wsOf({
          'path': '/ws',
          'headers': {'Host': 'cdn.example'},
        }),
        {'path': '/ws', 'host': 'cdn.example'},
      );
    });

    test('написание заголовка любое, остальные заголовки остаются', () {
      expect(
        wsOf({
          'headers': {'host': 'cdn.example', 'User-Agent': 'x'},
        }),
        {
          'headers': {'User-Agent': 'x'},
          'host': 'cdn.example',
        },
      );
    });

    // Своё host у ядра главнее заголовка: заголовок оно просто выбрасывает.
    test('свой host сохраняется, заголовок выбрасывается', () {
      expect(
        wsOf({
          'host': 'own.example',
          'headers': {'Host': 'cdn.example'},
        }),
        {'host': 'own.example'},
      );
    });
  });

  test('готовый конфиг переводится перед запуском и перед пингом', () {
    final custom = CustomXrayConfig.tryParse(
      jsonEncode({
        'outbounds': [
          {
            'protocol': 'vless',
            'tag': 'proxy',
            'settings': {
              'vnext': [
                {
                  'address': 'example.com',
                  'port': 443,
                  'users': [
                    {
                      'id': '0e0f3003-f4d9-46ef-b0b5-79c4223caa6c',
                      'encryption': 'none',
                    },
                  ],
                },
              ],
            },
            'streamSettings': {
              'network': 'ws',
              'security': 'tls',
              'wsSettings': {
                'headers': {'Host': 'cdn.example'},
              },
            },
          },
          {
            'protocol': 'freedom',
            'tag': 'direct',
            'settings': {'domainStrategy': 'UseIPv4'},
          },
          {
            'protocol': 'dns',
            'tag': 'dns-out',
            'settings': {'nonIPQuery': 'skip'},
          },
        ],
      }),
    )!;

    for (final config in [
      custom.buildSessionConfig(inbounds: const [], logLevel: 'warning'),
      custom.buildPingConfig(inbounds: const [], rules: const []),
    ]) {
      final text = jsonEncode(config);
      expect(text, isNot(contains('nonIPQuery')));
      expect(text, isNot(contains('"headers"')));
      expect(text, contains('"host":"cdn.example"'));
      expect(text, contains('"sockopt":{"domainStrategy":"UseIPv4"}'));
    }
  });
}
