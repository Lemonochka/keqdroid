import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

/// `ruleTag` — единственный способ узнать, ПО КАКОМУ правилу ушло соединение:
/// xray печатает «Hit route rule: [tag] so taking detour [proxy] for [...]», и по
/// этому тегу дебаг-экран «Соединения» показывает правило. Без тега в логе только
/// «taking detour [proxy]» — куда ушло, но не почему.
const _server = 'vless://uuid@example.com:443?type=tcp&security=none#demo';

List<Map<String, dynamic>> _rules(String config) =>
    (((jsonDecode(config) as Map)['routing'] as Map)['rules'] as List)
        .cast<Map<String, dynamic>>();

void main() {
  setUp(() => Socks5Credentials().init('u', 'p'));

  test('every routing rule carries a unique ruleTag', () {
    final rules = _rules(ConfigGeneratorV2.generateConfig(
      _server,
      const AppSettings(
        directRules: 'vk.com, geoip:ru, 10.8.0.0/24',
        proxyRules: 'youtube.com, geoip:telegram, 1.1.1.1',
        blockedRules: 'doubleclick.net, geoip:cn, 5.5.5.0/24',
      ),
    ));

    final tags = <String>[];
    for (final rule in rules) {
      expect(rule['ruleTag'], isA<String>(), reason: 'untagged rule: $rule');
      tags.add(rule['ruleTag'] as String);
    }
    expect(tags.toSet().length, tags.length, reason: 'duplicate ruleTag: $tags');
    expect(
      tags,
      containsAll([
        'block-domains',
        'block-geoip',
        'block-ips',
        'direct-domains',
        'direct-geoip',
        'direct-private',
        'proxy-domains',
        'proxy-geoip',
        'proxy-ips',
        'final',
      ]),
    );
  });

  test('tagging does not disturb the rule bodies', () {
    final rules = _rules(ConfigGeneratorV2.generateConfig(
      _server,
      const AppSettings(proxyRules: 'youtube.com'),
    ));
    final proxyRule =
        rules.firstWhere((r) => r['ruleTag'] == 'proxy-domains');
    expect(proxyRule['type'], 'field');
    expect(proxyRule['outboundTag'], 'proxy');
    expect(proxyRule['domain'], ['domain:youtube.com']);

    final last = rules.last;
    expect(last['ruleTag'], 'final');
    expect(last['outboundTag'], 'proxy');
    expect(last['network'], 'tcp,udp');
  });

  test('ping config stays untagged (log level none, nothing reads it)', () {
    final rules = _rules(ConfigGeneratorV2.generatePingConfig(
      _server,
      const AppSettings(proxyRules: 'youtube.com'),
      socksPort: 28150,
    ));
    expect(rules.every((r) => !r.containsKey('ruleTag')), isTrue);
  });
}
