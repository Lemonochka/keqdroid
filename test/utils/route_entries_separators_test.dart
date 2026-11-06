import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';
import 'package:keqdroid/utils/rule_lists.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

// Записи через пробел склеивались в одну, и маршрут не работал целиком; *.домен
// оба ядра сравнивали буквально (strmatcher у xray, DOMAIN-SUFFIX у mihomo)
const _vless =
    'vless://uuid@198.51.100.20:443?type=tcp&security=none#direct';

List<String> _xrayDirectDomains(AppSettings settings) {
  final config = jsonDecode(
    ConfigGeneratorV2.generateConfig(_vless, settings),
  ) as Map<String, dynamic>;
  final rules = ((config['routing'] as Map<String, dynamic>)['rules'] as List)
      .cast<Map<String, dynamic>>();
  return (rules.firstWhere((r) => r['ruleTag'] == 'direct-domains')['domain']
          as List)
      .cast<String>();
}

void main() {
  setUp(() => Socks5Credentials().init('u', 'p'));

  test('пробел, табуляция, запятая и перевод строки делят записи', () {
    expect(
      routingEntries('a.example b.example,c.example\n\td.example  10.0.0.0/8'),
      ['a.example', 'b.example', 'c.example', 'd.example', '10.0.0.0/8'],
    );
  });

  test('xray: записи через пробел и со звёздочкой', () {
    expect(
      _xrayDirectDomains(
        const AppSettings(directRules: 'a.example b.example, *.c.example'),
      ),
      ['domain:a.example', 'domain:b.example', 'domain:c.example'],
    );
  });

  test('mihomo: записи через пробел и со звёздочкой', () {
    final rules = MihomoConfigGen.buildUserRules(
      const AppSettings(directRules: 'a.example b.example, *.c.example'),
    );
    expect(
      rules,
      containsAll([
        'DOMAIN-SUFFIX,a.example,DIRECT',
        'DOMAIN-SUFFIX,b.example,DIRECT',
        'DOMAIN-SUFFIX,c.example,DIRECT',
      ]),
    );
    expect(rules.any((r) => r.contains('*')), isFalse);
  });
}
