import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/tunnel/app_routing_mode.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/exit_ip_probe.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

/// Флаг страны в статусе узнаёт выход запросом через локальный вход ядра.
/// Пользовательские правила такой запрос трогать не должны: с «Всё остальное
/// → напрямую» или с cloudflare.com в «Напрямую» флаг показывал домашний
/// адрес вместо адреса сервера.
const _server = 'vless://uuid@nl.example:443?type=tcp&security=none#nl';

/// Всё, что могло бы увести проверку мимо VPN.
const _hostile = AppSettings(
  directRules: 'cloudflare.com, ru',
  blockedRules: 'www.cloudflare.com',
  finalOutbound: AppSettings.finalOutboundDirect,
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
rules:
  - DOMAIN-SUFFIX,cloudflare.com,DIRECT
  - MATCH,Proxy
''';

const _xrayCustom = '''
{
  "outbounds": [
    {
      "tag": "my-proxy",
      "protocol": "vless",
      "settings": {"vnext": [{"address": "nl.example", "port": 443,
        "users": [{"id": "00000000-0000-4000-8000-000000000000", "encryption": "none"}]}]}
    },
    {"tag": "direct", "protocol": "freedom"}
  ],
  "routing": {"rules": [
    {"type": "field", "domain": ["domain:cloudflare.com"], "outboundTag": "direct"}
  ]}
}
''';

List<Map<String, dynamic>> _xrayRules(String config) => [
  for (final r
      in ((jsonDecode(config) as Map)['routing'] as Map)['rules'] as List)
    (r as Map).cast<String, dynamic>(),
];

bool _isProbe(Map<String, dynamic> r) =>
    (r['domain'] as List?)?.contains('full:$kExitIpProbeHost') ?? false;

void main() {
  setUp(() => Socks5Credentials().init('u', 'p'));

  group('xray', () {
    test('проверка выхода идёт через VPN раньше списков пользователя', () {
      final rules = _xrayRules(
        ConfigGeneratorV2.generateConfig(_server, _hostile),
      );
      final probe = rules.indexWhere(_isProbe);
      expect(probe, isNonNegative, reason: 'правила проверки нет');
      expect(rules[probe]['outboundTag'], 'proxy');
      // Без условия на вход: в режиме прокси на ПК соединение приходит в xray
      // из sing-box без тега, и такое условие не совпало бы ни разу.
      expect(rules[probe].containsKey('inboundTag'), isFalse);
      for (final tag in ['block-domains', 'direct-domains', 'final']) {
        final at = rules.indexWhere((r) => r['ruleTag'] == tag);
        expect(probe, lessThan(at), reason: 'проверка обязана стоять до $tag');
      }
    });

    test('в готовом конфиге — раньше правил автора, в его основной выход', () {
      final rules = _xrayRules(
        ConfigGeneratorV2.generateConfig(_xrayCustom, _hostile),
      );
      final probe = rules.indexWhere(_isProbe);
      final author = rules.indexWhere(
        (r) =>
            (r['domain'] as List?)?.contains('domain:cloudflare.com') ?? false,
      );
      expect(probe, isNonNegative);
      expect(rules[probe]['outboundTag'], 'my-proxy');
      expect(probe, lessThan(author));
    });
  });

  group('mihomo', () {
    List<String> rulesOf(Map<String, dynamic> c) =>
        (c['rules'] as List).cast<String>();

    test('проверка выхода — первым правилом, через прокси', () {
      final rules = rulesOf(
        MihomoConfigGen.build(
          _server,
          _hostile,
          socksPort: 2080,
          httpPort: 2081,
          tun: const MihomoTunOptions(device: 'tun-keqdis', stack: 'gvisor'),
          appProcessName: 'keqdroid.exe',
          windows: true,
        ),
      );
      expect(
        rules.first,
        'AND,((NOT,((IN-TYPE,TUN))),(DOMAIN,$kExitIpProbeHost)),'
        '${MihomoConfigGen.proxyName}',
      );
    });

    test('в готовом конфиге — раньше правил автора, в его группу', () {
      final rules = rulesOf(
        MihomoConfigGen.build(_clashYaml, _hostile, socksPort: 2080),
      );
      expect(
        rules.first,
        'AND,((NOT,((IN-TYPE,TUN))),(DOMAIN,$kExitIpProbeHost)),Proxy',
      );
    });

    // Запросы приложения через локальный вход ядра (флаг, подписки,
    // обновления) обязаны идти в туннель. Правило «свой процесс — напрямую»
    // нужно только для его собственных сокетов, попавших в TUN: mihomo ищет
    // процесс и у соединений, пришедших на HTTP-вход, и находил там нас же.
    test('свой процесс мимо туннеля — только для соединений из TUN', () {
      final rules = rulesOf(
        MihomoConfigGen.build(
          _server,
          const AppSettings(),
          socksPort: 2080,
          httpPort: 2081,
          tun: const MihomoTunOptions(device: 'tun-keqdis', stack: 'gvisor'),
          routingMode: AppRoutingMode.allProxy,
          appProcessName: 'keqdroid.exe',
          windows: true,
        ),
      );
      expect(rules, isNot(contains('PROCESS-NAME,keqdroid.exe,DIRECT')));
      expect(
        rules,
        contains(
          r'AND,((IN-TYPE,TUN),(PROCESS-NAME-REGEX,^keqdroid\x2eexe$)),DIRECT',
        ),
      );
    });

    // Скобка или запятая в имени переименованного exe разорвали бы
    // логическое правило, и ядро не приняло бы весь конфиг.
    test('имя процесса в логическом правиле закодировано', () {
      final rules = rulesOf(
        MihomoConfigGen.build(
          _server,
          const AppSettings(),
          socksPort: 2080,
          tun: const MihomoTunOptions(device: 'tun-keqdis', stack: 'gvisor'),
          appProcessName: 'keqdroid (1).exe',
          windows: true,
        ),
      );
      final own = rules.singleWhere((r) => r.startsWith('AND,((IN-TYPE,TUN)'));
      expect(own, isNot(contains(' (1)')));
      expect(own, contains(r'keqdroid\x20\x281\x29\x2eexe'));
    });
  });
}
