import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/custom_clash_config.dart';
import 'package:keqdroid/utils/custom_xray_config.dart';
import 'package:keqdroid/utils/geo_asset_index.dart';
import 'package:keqdroid/utils/geo_rule_sanitizer.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';
import 'package:keqdroid/utils/provider_routing.dart';
import 'package:keqdroid/utils/rule_lists.dart';
import 'package:keqdroid/utils/traffic_routes.dart';

// ru-direct из huzgnm/ru-direct собран из category-ru, ru-available-only-inside и российских зон
const _index = GeoAssetIndex(
  geoipCodes: {'ru', 'private'},
  geositeCodes: {
    'category-ru',
    'ru-available-only-inside',
    'tld-ru',
    'google',
    'apple',
    'refilter',
    'private',
  },
);

const _ruDirect = [
  'geosite:category-ru',
  'geosite:ru-available-only-inside',
  'geosite:tld-ru',
];

void main() {
  group('замена незнакомого геокода', () {
    test('ru-direct становится category-ru, ru-available-only-inside и tld-ru', () {
      expect(geoSubstitutes('geosite:ru-direct', _index), _ruDirect);
      expect(geoSubstitutes('GEOSITE:RU-DIRECT', _index), hasLength(3));
    });

    test('ru-blocked становится refilter, у google-cn и apple-cn варианты для Китая', () {
      expect(geoSubstitutes('geosite:ru-blocked', _index), ['geosite:refilter']);
      expect(geoSubstitutes('geosite:google-cn', _index), ['geosite:google@cn']);
      expect(geoSubstitutes('geosite:apple-cn', _index), ['geosite:apple@cn']);
    });

    test('без замены или без её кодов в базе — null, похожее имя не в счёт', () {
      expect(geoSubstitutes('geosite:ru-blocked-all', _index), isNull);
      expect(geoSubstitutes('geoip:ru-direct', _index), isNull);
      const thin = GeoAssetIndex(
        geoipCodes: {'ru'},
        geositeCodes: {'category-ru', 'tld-ru'},
      );
      expect(geoSubstitutes('geosite:ru-direct', thin), isNull);
      expect(geoSubstitutes('geosite:apple-cn', thin), isNull);
    });

    test('в списках правил заменяется, незнакомое без замены выбрасывается', () {
      final out = stripUnknownGeoTokensText(
          'geosite:ru-direct, vk.com, geosite:no-such-list', _index);
      expect(out.text, '${_ruDirect.join(', ')}, vk.com');
      expect(out.dropped, ['geosite:no-such-list']);
    });

    test('предупреждение называет только то, что выкинется', () {
      expect(
        unknownGeoTokens('geosite:ru-direct, geosite:google-cn, geosite:no-such-list', _index),
        ['geosite:no-such-list'],
      );
    });

    test('в готовом JSON правило остаётся с заменой', () {
      final config = jsonDecode(jsonEncode({
        'routing': {
          'rules': [
            {
              'domain': ['geosite:ru-direct'],
              'outboundTag': 'direct',
            },
            {
              'domain': ['geosite:no-such-list'],
              'outboundTag': 'direct',
            },
          ],
        },
      })) as Map<String, dynamic>;
      final dropped = stripUnknownGeoFromConfig(config, _index);
      expect(dropped, ['geosite:no-such-list']);
      expect((config['routing'] as Map)['rules'], [
        {
          'domain': _ruDirect,
          'outboundTag': 'direct',
        },
      ]);
    });
  });

  // Ranteis 12.11.2026: профиль Happ с geosite:ru-direct и своей Geositeurl. замена терялась,
  // когда ничего не выброшено, и mihomo с xray отказывали конфигу целиком
  group('профиль маршрутизации провайдера с ru-direct', () {
    final link = 'happ://routing/add/${base64.encode(utf8.encode(jsonEncode({
          'Name': 'ru-direct',
          'GlobalProxy': 'true',
          'Geositeurl': 'https://provider.example/geosite.dat',
          'DirectSites': ['geosite:private', 'geosite:ru-direct', 'domain:reddit.com'],
          'DirectIp': ['geoip:private', 'geoip:ru'],
          'ProxySites': ['domain:ipinfo.io'],
        })))}';
    const server = 'trojan://secret@a.example.com:443?sni=a.example.com#A';

    AppSettings sanitized() {
      final routing = parseProviderRouting(link) as ProviderRoutingRules;
      final result =
          stripUnknownGeoTokens(foldRoutes(const AppSettings(), routing.routes), _index);
      expect(result.dropped, isEmpty);
      return result.settings;
    }

    test('в правилах напрямую стоит замена, а не ru-direct', () {
      final direct = routingEntries(sanitized().directRules);
      expect(direct, containsAll(['geosite:category-ru', 'geosite:tld-ru', 'domain:reddit.com']));
      expect(direct, isNot(contains('geosite:ru-direct')));
    });

    test('до mihomo и xray код не доходит', () {
      final settings = sanitized();
      final mihomo = MihomoConfigGen.generate(server, settings, socksPort: 10808);
      expect(mihomo, isNot(contains('ru-direct')));
      expect(mihomo, contains('GEOSITE,category-ru,DIRECT'));
      final xray = ConfigGeneratorV2.generateConfig(server, settings);
      expect(xray, isNot(contains('ru-direct')));
      expect(xray, contains('geosite:category-ru'));
    });
  });

  group('готовый Clash и незнакомые коды', () {
    const yaml = '''
proxies:
  - {name: A, type: socks5, server: a.example, port: 1080}
rules:
  - GEOSITE,ru-direct,DIRECT
  - GEOSITE,google@cn,A
  - GEOIP,lan,DIRECT,no-resolve
  - GEOIP,RU,DIRECT,no-resolve
  - GEOSITE,no-such-list,DIRECT
  - AND,((GEOSITE,no-such-list),(NETWORK,UDP)),REJECT
  - MATCH,A
''';

    test('замена по таблице, остальное с неизвестным кодом выбрасывается', () {
      final result = CustomClashConfig.tryParse(yaml)!.withKnownGeo(_index);
      expect(result.config.map['rules'], [
        'GEOSITE,category-ru,DIRECT',
        'GEOSITE,ru-available-only-inside,DIRECT',
        'GEOSITE,tld-ru,DIRECT',
        'GEOSITE,google@cn,A',
        'GEOIP,lan,DIRECT,no-resolve',
        'GEOIP,RU,DIRECT,no-resolve',
        'MATCH,A',
      ]);
      expect(result.dropped, ['geosite:no-such-list', 'geosite:no-such-list']);
    });

    test('пустая база ничего не трогает: не нам решать, что код неверный', () {
      final result = CustomClashConfig.tryParse(yaml)!.withKnownGeo(GeoAssetIndex.empty);
      expect(result.dropped, isEmpty);
      expect(result.config.map['rules'], hasLength(7));
    });

    test('IP-ASN выбрасывается всегда: базы нет, а за ней ядро полезло бы на GitHub', () {
      const asn = '''
proxies:
  - {name: A, type: socks5, server: a.example, port: 1080}
rules:
  - IP-ASN,62041,A,no-resolve
  - SRC-IP-ASN,13335,DIRECT
  - OR,((IP-ASN,44907),(DOMAIN,t.me)),A
  - DOMAIN-SUFFIX,telegram.org,A
  - MATCH,DIRECT
''';
      for (final index in [_index, GeoAssetIndex.empty]) {
        final result = CustomClashConfig.tryParse(asn)!.withKnownGeo(index);
        expect(result.config.map['rules'], [
          'DOMAIN-SUFFIX,telegram.org,A',
          'MATCH,DIRECT',
        ]);
        expect(result.dropped, ['ip-asn:62041', 'ip-asn:13335', 'ip-asn:44907']);
      }
    });
  });
}
