import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/tunnel/app_routing_mode.dart';
import 'package:keqdroid/utils/custom_clash_config.dart';
import 'package:keqdroid/utils/custom_xray_config.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

/// «Не учитывать правила провайдера»: уходят его сайты напрямую и в блок и его
/// «всё остальное», а правила к его же узлам и технические остаются, иначе
/// ломаются конфиги на несколько узлов.
void main() {
  setUp(() => Socks5Credentials().init('u', 'p'));

  group('xray JSON', () {
    CustomXrayConfig config(List<Map<String, dynamic>> rules) =>
        CustomXrayConfig.tryParse(jsonEncode({
          'outbounds': [
            {'tag': 'proxy', 'protocol': 'vless'},
            {'tag': 'proxy-fast', 'protocol': 'vless'},
            {'tag': 'direct', 'protocol': 'freedom'},
            {'tag': 'block', 'protocol': 'blackhole'},
            {'tag': 'dns-out', 'protocol': 'dns'},
          ],
          'routing': {'rules': rules},
        }))!;

    List<Object?> kept(List<Map<String, dynamic>> rules) =>
        (config(rules).withoutProviderRules().json['routing'] as Map)['rules'] as List;

    test('сайты и адреса напрямую и в блок уходят', () {
      expect(
        kept([
          {'domain': ['geosite:category-ru'], 'outboundTag': 'direct'},
          {'ip': ['geoip:private'], 'outboundTag': 'direct'},
          {'domain': ['domain:ads.example'], 'outboundTag': 'block'},
          {'ip': ['::/0'], 'outboundTag': 'block'},
        ]),
        isEmpty,
      );
    });

    test('правила к его узлам и балансировщику остаются', () {
      final rules = [
        {'domain': ['domain:video.example'], 'outboundTag': 'proxy-fast'},
        {'ip': ['203.0.113.0/24'], 'balancerTag': 'auto'},
      ];
      expect(kept(rules), rules);
    });

    test('технические правила остаются', () {
      final rules = [
        {'protocol': ['bittorrent'], 'outboundTag': 'direct'},
        {'port': '53', 'outboundTag': 'direct'},
        {'inboundTag': ['dns-in'], 'outboundTag': 'dns-out'},
      ];
      expect(kept(rules), rules);
    });

    test('его «всё остальное» уходит, к какому бы узлу оно ни вело', () {
      expect(
        kept([
          {'type': 'field', 'network': 'tcp,udp', 'outboundTag': 'direct'},
          {'port': '0-65535', 'outboundTag': 'direct'},
          {'type': 'field', 'outboundTag': 'proxy'},
        ]),
        isEmpty,
      );
    });

    test('что выбросит, видно заранее', () {
      expect(config([{'domain': ['domain:x'], 'outboundTag': 'direct'}]).hasProviderRules, isTrue);
      expect(config([{'port': '53', 'outboundTag': 'direct'}]).hasProviderRules, isFalse);
      expect(
        CustomXrayConfig.tryParse('{"outbounds":[{"tag":"proxy","protocol":"vless"}]}')!
            .hasProviderRules,
        isFalse,
      );
    });
  });

  group('Clash', () {
    CustomClashConfig config(List<String> rules) => CustomClashConfig.tryParse('''
proxies:
  - name: "NL"
    type: trojan
    server: 198.51.100.60
    port: 443
    password: password
proxy-groups:
  - name: "Proxy"
    type: select
    proxies: ["NL"]
rules:
${rules.map((r) => '  - "$r"').join('\n')}
''')!;

    List<String> kept(List<String> rules) => [
          for (final r in config(rules).withoutProviderRules().map['rules'] as List)
            r.toString(),
        ];

    test('сайты, наборы и составные правила в DIRECT и REJECT уходят, MATCH тоже', () {
      expect(
        kept([
          'DOMAIN-SUFFIX,ru,DIRECT',
          'GEOIP,private,DIRECT,no-resolve',
          'IP-CIDR,203.0.113.0/24,REJECT,no-resolve',
          'RULE-SET,ads,REJECT-DROP',
          'AND,((DOMAIN-SUFFIX,quic.example),(NETWORK,UDP)),REJECT',
          ' DOMAIN-KEYWORD , ads , REJECT ',
          'MATCH,Proxy',
        ]),
        isEmpty,
      );
    });

    // в регулярке свои запятые, ядро берёт цель последней (ParseRulePayload в rules/common/base.go)
    test('регулярка с запятой в DIRECT и REJECT уходит, к его группе остаётся', () {
      expect(
        kept([
          r'DOMAIN-REGEX,^ads[0-9]{1,3}[.]example$,REJECT',
          r'DOMAIN-REGEX,^(cdn|img){1,2}[.]ru$,DIRECT',
          r'DOMAIN-REGEX,^v{1,3}[.]example$,Proxy',
        ]),
        [r'DOMAIN-REGEX,^v{1,3}[.]example$,Proxy'],
      );
      expect(
        config([r'DOMAIN-REGEX,^ads[0-9]{1,3}[.]example$,REJECT']).hasProviderRules,
        isTrue,
      );
    });

    test('к его группам и технические остаются', () {
      final rules = [
        'DOMAIN-SUFFIX,video.example,Proxy',
        'DST-PORT,53,DIRECT',
        'PROCESS-NAME,tool.exe,DIRECT',
        'AND,((NETWORK,UDP),(DST-PORT,443)),REJECT',
        'SUB-RULE,(NETWORK,tcp),sub',
      ];
      expect(kept(rules), rules);
    });

    test('своё «всё остальное» ставит генератор, как у ссылок', () {
      const yaml = '''
proxies:
  - name: "NL"
    type: trojan
    server: 198.51.100.61
    port: 443
    password: password
rules:
  - DOMAIN-SUFFIX,provider-only.example,DIRECT
  - MATCH,DIRECT
''';
      List<String> rulesOf(AppSettings s, {AppRoutingMode mode = AppRoutingMode.allProxy}) {
        final out = jsonDecode(MihomoConfigGen.generate(yaml, s, socksPort: 2080)) as Map;
        return [for (final r in out['rules'] as List) r.toString()];
      }

      const on = AppSettings(ignoreProviderRules: true);
      expect(rulesOf(on).last, 'MATCH,NL');
      expect(rulesOf(on.copyWith(finalOutbound: AppSettings.finalOutboundDirect)).last,
          'MATCH,DIRECT');
      expect(rulesOf(on), isNot(contains('DOMAIN-SUFFIX,provider-only.example,DIRECT')));
      // выключенный переключатель: всё как раньше, решает MATCH провайдера
      expect(rulesOf(const AppSettings()).last, 'MATCH,DIRECT');
      expect(rulesOf(const AppSettings()), contains('DOMAIN-SUFFIX,provider-only.example,DIRECT'));
    });

    test('что выбросит, видно заранее', () {
      expect(config(['DOMAIN-SUFFIX,ru,DIRECT']).hasProviderRules, isTrue);
      expect(config(['DST-PORT,53,DIRECT']).hasProviderRules, isFalse);
    });
  });
}
