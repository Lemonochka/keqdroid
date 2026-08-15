import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/xray_core_settings.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/custom_xray_config.dart';
import 'package:keqdroid/utils/geo_asset_index.dart';
import 'package:keqdroid/utils/import_payload.dart';

/// Готовый конфиг ядра, каким его отдают провайдеры: своя цепочка аутбаундов,
/// свои правила роутинга и свой dns, имя в корневом `remarks` (v2rayNG).
const _customConfig = '''
{
  "remarks": "🇳🇱 Обход [Gold] - Нидерланды",
  "dns": {
    "servers": ["1.1.1.1", "1.0.0.1"],
    "queryStrategy": "UseIPv4"
  },
  "inbounds": [
    {"tag": "socks", "port": 10808, "protocol": "socks", "listen": "127.0.0.1"}
  ],
  "routing": {
    "rules": [
      {"type": "field", "ip": ["185.73.195.0/24"], "outboundTag": "direct"},
      {"type": "field", "protocol": ["bittorrent"], "outboundTag": "direct"},
      {"type": "field", "domain": ["geosite:sberbank", "geosite:google"], "outboundTag": "direct"},
      {"type": "field", "domain": ["geosite:sberbank"], "outboundTag": "block"},
      {"type": "field", "network": "tcp,udp", "outboundTag": "proxy"}
    ]
  },
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "nl1.example.com",
            "port": 443,
            "users": [{"id": "uuid-1", "encryption": "none", "flow": "xtls-rprx-vision"}]
          }
        ]
      },
      "streamSettings": {"network": "tcp", "security": "reality"}
    },
    {"tag": "direct", "protocol": "freedom"},
    {"tag": "block", "protocol": "blackhole"}
  ]
}
''';

const _singboxConfig = '''
{
  "inbounds": [{"type": "tun", "tag": "tun-in"}],
  "outbounds": [{"type": "vless", "tag": "proxy", "server": "nl1.example.com", "server_port": 443}]
}
''';

Map<String, dynamic> _decode(String raw) =>
    jsonDecode(raw) as Map<String, dynamic>;

List<Map<String, dynamic>> _rules(Map<String, dynamic> config) => [
      for (final r in (config['routing'] as Map)['rules'] as List)
        (r as Map).cast<String, dynamic>(),
    ];

List<String?> _outboundTags(Map<String, dynamic> config) => [
      for (final o in config['outbounds'] as List)
        (o as Map)['tag'] as String?,
    ];

void main() {
  group('CustomXrayConfig', () {
    test('parses a full xray config and reads its name', () {
      final custom = CustomXrayConfig.tryParse(_customConfig);
      expect(custom, isNotNull);
      expect(custom!.remarks, '🇳🇱 Обход [Gold] - Нидерланды');
      expect(custom.primaryOutboundTag, 'proxy');
      expect(custom.endpoint.address, 'nl1.example.com');
      expect(custom.endpoint.port, 443);
      expect(CustomXrayConfig.describeProblem(_customConfig), isNull);
    });

    test('reads the endpoint from every outbound shape', () {
      ({String address, int port}) endpointOf(String outbound) =>
          CustomXrayConfig.tryParse(
            '{"outbounds": [$outbound]}',
          )!.endpoint;

      // trojan/ss/socks — `servers`
      expect(
        endpointOf(
          '{"protocol": "trojan", "settings": {"servers": '
          '[{"address": "a.example.com", "port": 8443}]}}',
        ),
        (address: 'a.example.com', port: 8443),
      );
      // xray 26+ плоская форма (её пишет наш собственный генератор)
      expect(
        endpointOf(
          '{"protocol": "vless", "settings": {"address": "b.example.com", "port": 2053}}',
        ),
        (address: 'b.example.com', port: 2053),
      );
      // wireguard — endpoint строкой
      expect(
        endpointOf(
          '{"protocol": "wireguard", "settings": {"peers": '
          '[{"endpoint": "c.example.com:51820"}]}}',
        ),
        (address: 'c.example.com', port: 51820),
      );
    });

    test('skips freedom/blackhole when looking for the server', () {
      final custom = CustomXrayConfig.tryParse('''
{"outbounds": [
  {"tag": "direct", "protocol": "freedom"},
  {"tag": "real", "protocol": "vmess", "settings": {"vnext": [{"address": "d.example.com", "port": 80}]}}
]}''');
      expect(custom!.primaryOutboundTag, 'real');
      expect(custom.address, 'd.example.com');
    });

    test('rejects sing-box json with a distinguishable reason', () {
      expect(CustomXrayConfig.tryParse(_singboxConfig), isNull);
      expect(
        CustomXrayConfig.describeProblem(_singboxConfig),
        contains('sing-box'),
      );
    });

    test('rejects json that is not a core config at all', () {
      expect(CustomXrayConfig.tryParse('{"user": "kek", "days": 3}'), isNull);
      expect(
        CustomXrayConfig.describeProblem('{"user": "kek"}'),
        contains('outbounds'),
      );
      expect(CustomXrayConfig.tryParse('vless://uuid@host:443'), isNull);
    });

    test('extracts every config from a json array', () {
      final list = '[$_customConfig, $_customConfig]';
      expect(CustomXrayConfig.extractConfigs(list).length, 2);
      expect(CustomXrayConfig.extractConfigs(_customConfig).length, 1);
      expect(CustomXrayConfig.extractConfigs('[{"a": 1}]'), isEmpty);
    });
  });

  group('stripUnknownGeoFromConfig', () {
    // База, в которой sberbank нет — как в поставляемой v2fly.
    const index = GeoAssetIndex(
      geoipCodes: {'ru', 'private'},
      geositeCodes: {'google', 'category-ads-all'},
    );

    test('drops unknown geo tokens and rules left without conditions', () {
      final config = _decode(_customConfig);
      final dropped = stripUnknownGeoFromConfig(config, index);

      expect(dropped, contains('geosite:sberbank'));
      final rules = _rules(config);
      // Правило с двумя доменами осталось, но уже без неизвестного кода.
      final mixed = rules.firstWhere((r) => r['outboundTag'] == 'direct' &&
          r.containsKey('domain'));
      expect(mixed['domain'], ['geosite:google']);
      // Правило, у которого не осталось ни одного условия, ядро не приняло бы.
      expect(rules.any((r) => r['outboundTag'] == 'block'), isFalse);
      // Всё остальное на месте.
      expect(rules.any((r) => r['protocol'] != null), isTrue);
      expect(rules.last['outboundTag'], 'proxy');
    });

    test('never widens a rule: a fully stripped condition drops it', () {
      // Самое опасное место чистки. `ip` тут после выброса неизвестного кода
      // пустеет, а `port` остаётся — оставить такое правило значит отправить
      // напрямую ВЕСЬ трафик на 443 вместо одного geo-набора.
      final config = _decode('''
{
  "routing": {"rules": [
    {"type": "field", "ip": ["geoip:sberbank"], "port": "443", "outboundTag": "direct"},
    {"type": "field", "domain": ["geosite:sberbank"], "network": "tcp", "outboundTag": "block"},
    {"type": "field", "ip": ["geoip:ru"], "port": "443", "outboundTag": "direct"}
  ]},
  "outbounds": [{"protocol": "freedom"}]
}''');
      stripUnknownGeoFromConfig(config, index);

      final rules = _rules(config);
      expect(rules.length, 1);
      expect(rules.single['ip'], ['geoip:ru']);
      expect(rules.single['port'], '443');
    });

    test('a dns server that lost its expectIPs filter goes with it', () {
      final config = _decode('''
{
  "dns": {"servers": [
    {"address": "8.8.8.8", "expectIPs": ["geoip:sberbank"]},
    {"address": "9.9.9.9", "expectIPs": ["geoip:ru", "geoip:sberbank"]}
  ]},
  "outbounds": [{"protocol": "freedom"}]
}''');
      stripUnknownGeoFromConfig(config, index);

      final servers = (config['dns'] as Map)['servers'] as List;
      expect(servers.length, 1);
      expect((servers.single as Map)['expectIPs'], ['geoip:ru']);
    });

    test('keeps everything when the geo index is empty', () {
      final config = _decode(_customConfig);
      expect(stripUnknownGeoFromConfig(config, GeoAssetIndex.empty), isEmpty);
      expect(_rules(config).length, 5);
    });

    test('drops a dns server whose domains were all unknown', () {
      final config = _decode('''
{
  "dns": {"servers": [
    "1.1.1.1",
    {"address": "8.8.8.8", "domains": ["geosite:sberbank"]},
    {"address": "9.9.9.9", "domains": ["geosite:google", "geosite:sberbank"]}
  ]},
  "outbounds": [{"protocol": "freedom"}]
}''');
      stripUnknownGeoFromConfig(config, index);
      final servers = (config['dns'] as Map)['servers'] as List;
      expect(servers.length, 2);
      expect(servers.first, '1.1.1.1');
      expect(((servers[1] as Map)['domains'] as List), ['geosite:google']);
    });
  });

  group('ServerItem with a custom config', () {
    test('reports protocol, name and endpoint of the primary outbound', () {
      final item = ServerItem.fromRaw(_customConfig);
      expect(item.protocol, 'custom');
      expect(item.displayName, '🇳🇱 Обход [Gold] - Нидерланды');
      expect(item.address, 'nl1.example.com');
      expect(item.port, 443);
      expect(item.countryCode, 'NL');
    });

    test('falls back to the server address when there is no remark', () {
      final item = ServerItem.fromRaw(
        '{"outbounds": [{"protocol": "vless", "settings": '
        '{"address": "e.example.com", "port": 443}}]}',
      );
      expect(item.derivedName, 'e.example.com');
    });
  });

  group('validateServerConfig', () {
    test('accepts a full xray config', () {
      expect(ServersNotifier.validateServerConfig(_customConfig), isNull);
    });

    test('explains a sing-box config instead of "unsupported format"', () {
      final error = ServersNotifier.validateServerConfig(_singboxConfig);
      expect(error, contains('sing-box'));
    });
  });

  group('splitServerImportPayload', () {
    test('keeps a multi-line json config whole', () {
      final configs = splitServerImportPayload(_customConfig);
      expect(configs.length, 1);
      expect(CustomXrayConfig.tryParse(configs.single), isNotNull);
    });

    test('splits a json array into separate servers', () {
      expect(splitServerImportPayload('[$_customConfig, $_customConfig]').length, 2);
    });

    test('still splits a list of links line by line', () {
      final configs = splitServerImportPayload(
        'vless://uuid@a.example.com:443#A\n\nvless://uuid@b.example.com:443#B\n',
      );
      expect(configs.length, 2);
    });

    test('hands broken json over as one payload, not as line noise', () {
      expect(splitServerImportPayload(_singboxConfig).length, 1);
    });
  });

  group('ConfigGeneratorV2 with a custom config', () {
    const settings = AppSettings(
      localPort: 2080,
      httpPort: 2081,
      xrayCore: XrayCoreSettings(logLevel: 'info'),
    );

    test('keeps the author routing and dns, replaces the inbounds', () {
      final config = _decode(
        ConfigGeneratorV2.generateConfig(_customConfig, settings),
      );

      // Инбаунды наши: в них ходит нативная часть, чужие порты ей не подходят.
      final inbounds = (config['inbounds'] as List)
          .map((i) => (i as Map).cast<String, dynamic>())
          .toList();
      expect(inbounds.map((i) => i['port']), containsAll([2080, 2081]));
      expect(inbounds.map((i) => i['tag']), contains('socks-in'));
      expect(inbounds.any((i) => i['port'] == 10808), isFalse);

      // Авторские правила целы и в своём порядке: наши узнаются по ruleTag,
      // у автора его нет.
      final authorRules =
          _rules(config).where((r) => r['ruleTag'] == null).toList();
      expect(authorRules.length, 5);
      expect(authorRules.first['ip'], ['185.73.195.0/24']);
      expect(authorRules.last['outboundTag'], 'proxy');

      // Dns и аутбаунды — авторские.
      expect((config['dns'] as Map)['servers'], ['1.1.1.1', '1.0.0.1']);
      expect(
        ((config['outbounds'] as List).first as Map)['streamSettings'],
        {'network': 'tcp', 'security': 'reality'},
      );

      // Уровень логов из настроек: без info ядро не печатает правила, и экран
      // «Соединения» остаётся без вердиктов.
      expect((config['log'] as Map)['loglevel'], 'info');
      // Своё поле имени ядру не отдаём.
      expect(config.containsKey('remarks'), isFalse);
    });

    test('strips geo codes missing from the bundled databases', () {
      final config = _decode(
        ConfigGeneratorV2.generateConfig(
          _customConfig,
          settings,
          geoIndex: const GeoAssetIndex(
            geoipCodes: {'ru'},
            geositeCodes: {'google'},
          ),
        ),
      );
      final flattened = jsonEncode(config);
      expect(flattened.contains('geosite:sberbank'), isFalse);
      expect(flattened.contains('geosite:google'), isTrue);
    });

    test('guards the LAN inbounds the author knows nothing about', () {
      final config = _decode(
        ConfigGeneratorV2.generateConfig(
          _customConfig,
          settings.copyWith(lanSharing: true),
        ),
      );
      final rules = _rules(config);
      expect(rules.first['ruleTag'], 'lan-allow');
      expect(rules.first['inboundTag'], ['socks-lan', 'http-lan']);
      expect(rules.first['outboundTag'], 'proxy');
      expect(rules[1]['ruleTag'], 'lan-deny');
      // Автор завёл blackhole сам — свой дописывать незачем.
      expect(rules[1]['outboundTag'], 'block');
      // Защита LAN идёт раньше всего остального, включая пользовательские
      // списки: инбаунд слушает 0.0.0.0, и пускать в него кого попало нельзя.
      expect(
        rules.indexWhere((r) => r['ruleTag'] == 'user-direct-domains'),
        greaterThan(1),
      );
    });

    test('adds a blackhole for the LAN deny rule when the author has none', () {
      final config = _decode(
        ConfigGeneratorV2.generateConfig(
          '{"outbounds": [{"tag": "proxy", "protocol": "vless", "settings": '
          '{"address": "f.example.com", "port": 443}}]}',
          settings.copyWith(lanSharing: true),
        ),
      );
      final rules = _rules(config);
      expect(rules[1]['outboundTag'], 'keq-block');
      expect(_outboundTags(config), contains('keq-block'));
    });

    test('applies the user routing lists before the author rules', () {
      final config = _decode(
        ConfigGeneratorV2.generateConfig(
          _customConfig,
          settings.copyWith(
            directRules: 'bypass.example.com',
            proxyRules: 'via.example.net',
            blockedRules: 'ads.example.org, 10.1.2.0/24',
          ),
        ),
      );
      final rules = _rules(config);
      final tags = rules.map((r) => r['ruleTag']).toList();

      // Порядок тот же, что и у обычного сервера: блок → обход → прокси.
      final block = tags.indexOf('user-block-domains');
      final direct = tags.indexOf('user-direct-domains');
      final proxy = tags.indexOf('user-proxy-domains');
      final firstAuthor = rules.indexWhere((r) => r['ruleTag'] == null);
      expect(block, isNonNegative);
      expect(block, lessThan(direct));
      expect(direct, lessThan(proxy));
      // Названное руками важнее заготовки провайдера.
      expect(proxy, lessThan(firstAuthor));

      expect(rules[block]['domain'], ['domain:ads.example.org']);
      expect(rules[block]['outboundTag'], 'block');
      expect(rules[direct]['outboundTag'], 'direct');
      expect(rules[tags.indexOf('user-block-ips')]['ip'], ['10.1.2.0/24']);
      // Свои freedom/blackhole не нужны — у автора они уже есть.
      expect(jsonEncode(config['outbounds']).contains('keq-'), isFalse);
    });

    test('unmatched traffic follows the app setting', () {
      final config = _decode(
        ConfigGeneratorV2.generateConfig(
          '{"outbounds": [{"tag": "out", "protocol": "vless", "settings": '
          '{"address": "f.example.com", "port": 443}}]}',
          settings.copyWith(
            directRules: '',
            finalOutbound: AppSettings.finalOutboundBlock,
          ),
        ),
      );
      final rules = _rules(config);

      expect(rules.last['ruleTag'], 'final');
      expect(rules.last['outboundTag'], 'keq-block');
      expect(_outboundTags(config), contains('keq-block'));
      // freedom никто не просил — и его нет.
      expect(_outboundTags(config), isNot(contains('keq-direct')));
    });

    test('ping config sends everything to the author primary outbound', () {
      final config = _decode(
        ConfigGeneratorV2.generatePingConfig(
          _customConfig,
          settings,
          socksPort: 28150,
          resolvedServerIp: '203.0.113.9',
          httpInbound: true,
        ),
      );

      expect((config['log'] as Map)['loglevel'], 'none');
      final inbounds = (config['inbounds'] as List)
          .map((i) => (i as Map).cast<String, dynamic>())
          .toList();
      expect(inbounds.length, 1);
      expect(inbounds.single['protocol'], 'http');
      expect(inbounds.single['port'], 28150);

      final rules = _rules(config);
      // Сам сервер и приватные сети мимо туннеля, всё остальное — в прокси.
      expect(rules.first['ip'], ['203.0.113.9']);
      expect(rules.first['outboundTag'], 'keq-ping-direct');
      expect(rules[1]['domain'], ['full:nl1.example.com']);
      expect(rules.last['outboundTag'], 'proxy');
      // Авторские правила в пробу не попадают: они могли бы увести её в direct.
      expect(rules.any((r) => r['protocol'] != null), isFalse);
      expect(
        (config['outbounds'] as List).last,
        {'protocol': 'freedom', 'tag': 'keq-ping-direct'},
      );
    });
  });
}
