import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';
import 'package:keqdroid/utils/rule_lists.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

/// Списки по ссылке в полях маршрутизации. Сама ссылка ядру непонятна и в
/// конфиг попадать не должна ни у одного генератора: у xray она стала бы
/// доменом `https://…`, у mihomo запятые в ней разрезали бы правило.
/// Скачанные домены едут в конфиг отдельно — см. [RuleListDomains].
const _server = 'vless://uuid@example.com:443?type=tcp&security=none#demo';

const _plain = AppSettings(
  directRules: 'vk.com, geoip:ru',
  proxyRules: 'youtube.com',
  blockedRules: 'doubleclick.net, 5.5.5.0/24',
);

const _withUrls = AppSettings(
  directRules: 'vk.com, https://lists.example/direct.txt, geoip:ru',
  proxyRules: 'youtube.com\nhttps://lists.example/proxy.txt',
  blockedRules:
      'doubleclick.net, https://lists.example/ads.txt,'
      ' 5.5.5.0/24\nhttp://plain.example/hosts',
);

const _clashYaml = '''
proxies:
  - name: "NL"
    type: trojan
    server: nl.example
    port: 443
    password: password
    sni: nl.example
proxy-groups:
  - name: "Proxy"
    type: select
    proxies: ["NL"]
rule-providers:
  author-ads:
    type: inline
    behavior: domain
    payload: ["+.author-ads.example"]
rules:
  - RULE-SET,author-ads,REJECT
  - MATCH,Proxy
''';

List<String> _rules(Map<String, dynamic> config) =>
    (config['rules'] as List).cast<String>();

void main() {
  setUp(() => Socks5Credentials().init('u', 'p'));

  group('ссылка в поле до ядра не доезжает', () {
    test('xray', () {
      expect(
        ConfigGeneratorV2.generateConfig(_server, _withUrls),
        ConfigGeneratorV2.generateConfig(_server, _plain),
      );
    });

    test('mihomo', () {
      expect(
        MihomoConfigGen.generate(_server, _withUrls, socksPort: 2080),
        MihomoConfigGen.generate(_server, _plain, socksPort: 2080),
      );
    });
  });

  group('mihomo: скачанные домены — набором, а не правилом на домен', () {
    const lists = RuleListDomains(
      direct: ['direct-list.example'],
      proxy: ['proxy-list.example'],
      blocked: ['ads-list.example', 'track-list.example'],
    );

    test('набор встроен в конфиг и покрывает поддомены', () {
      final c = MihomoConfigGen.build(
        _server,
        _plain,
        socksPort: 2080,
        ruleLists: lists,
      );
      final providers = c['rule-providers'] as Map;
      expect(
        providers.keys,
        unorderedEquals([
          'keq-list-direct',
          'keq-list-proxy',
          'keq-list-block',
        ]),
      );
      expect(providers['keq-list-block'], {
        'type': 'inline',
        'behavior': 'domain',
        'payload': ['+.ads-list.example', '+.track-list.example'],
      });
    });

    test('стоит рядом с доменами своего поля, в том же порядке полей', () {
      final rules = _rules(
        MihomoConfigGen.build(
          _server,
          _plain,
          socksPort: 2080,
          ruleLists: lists,
        ),
      );
      int at(String rule) {
        final i = rules.indexOf(rule);
        expect(i, isNonNegative, reason: '$rule нет в $rules');
        return i;
      }

      final blockDomain = at('DOMAIN-SUFFIX,doubleclick.net,REJECT');
      final blockSet = at('RULE-SET,keq-list-block,REJECT');
      final blockIp = rules.indexWhere(
        (r) => r.startsWith('IP-CIDR,5.5.5.0/24,REJECT'),
      );
      final directSet = at('RULE-SET,keq-list-direct,DIRECT');
      final proxySet = at(
        'RULE-SET,keq-list-proxy,${MihomoConfigGen.proxyName}',
      );

      expect(blockSet, blockDomain + 1);
      expect(blockSet, lessThan(blockIp));
      expect(blockSet, lessThan(directSet));
      expect(directSet, lessThan(proxySet));
      expect(proxySet, lessThan(rules.length - 1));
      expect(rules.last, startsWith('MATCH,'));
    });

    test('пустое поле набора не получает', () {
      final c = MihomoConfigGen.build(
        _server,
        _plain,
        socksPort: 2080,
        ruleLists: const RuleListDomains(blocked: ['ads-list.example']),
      );
      expect((c['rule-providers'] as Map).keys, ['keq-list-block']);
      expect(_rules(c).where((r) => r.startsWith('RULE-SET,')), [
        'RULE-SET,keq-list-block,REJECT',
      ]);
    });

    test('без списков конфиг прежний', () {
      expect(
        MihomoConfigGen.generate(
          _server,
          _plain,
          socksPort: 2080,
          ruleLists: RuleListDomains.none,
        ),
        MihomoConfigGen.generate(_server, _plain, socksPort: 2080),
      );
      expect(
        MihomoConfigGen.build(
          _server,
          _plain,
          socksPort: 2080,
        ).containsKey('rule-providers'),
        isFalse,
      );
    });

    test('готовый clash-конфиг: наборы автора остаются, наш добавляется', () {
      final c = MihomoConfigGen.build(
        _clashYaml,
        _plain,
        socksPort: 2080,
        ruleLists: const RuleListDomains(blocked: ['ads-list.example']),
      );
      final providers = c['rule-providers'] as Map;
      expect(providers.keys, unorderedEquals(['author-ads', 'keq-list-block']));
      final rules = _rules(c);
      expect(rules, contains('RULE-SET,author-ads,REJECT'));
      expect(rules, contains('RULE-SET,keq-list-block,REJECT'));
      expect(rules.last, 'MATCH,Proxy');
    });
  });

  group('xray: домены дописываются в поля', () {
    const lists = RuleListDomains(blocked: ['ads-list.example']);

    test('xray блокирует домен из списка вместе с поддоменами', () {
      final config =
          jsonDecode(
                ConfigGeneratorV2.generateConfig(
                  _server,
                  lists.expand(_withUrls),
                ),
              )
              as Map<String, dynamic>;
      final rules = ((config['routing'] as Map)['rules'] as List)
          .cast<Map<String, dynamic>>();
      final block = rules.firstWhere((r) => r['ruleTag'] == 'block-domains');
      expect(block['domain'], [
        'domain:doubleclick.net',
        'domain:ads-list.example',
      ]);
    });

    test('без списков настройки те же самые', () {
      expect(RuleListDomains.none.expand(_plain), same(_plain));
    });
  });
}
