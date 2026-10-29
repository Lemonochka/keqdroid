import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/custom_clash_config.dart';
import 'package:keqdroid/utils/custom_xray_config.dart';
import 'package:keqdroid/utils/geo_asset_index.dart';
import 'package:keqdroid/utils/geo_rule_sanitizer.dart';

// ru-direct из huzgnm/ru-direct собран из category-ru и российских зон, обе части у нас есть
const _index = GeoAssetIndex(
  geoipCodes: {'ru', 'private'},
  geositeCodes: {'category-ru', 'tld-ru', 'google', 'private'},
);

void main() {
  group('замена незнакомого геокода', () {
    test('ru-direct становится category-ru и tld-ru', () {
      expect(geoSubstitutes('geosite:ru-direct', _index),
          ['geosite:category-ru', 'geosite:tld-ru']);
      expect(geoSubstitutes('GEOSITE:RU-DIRECT', _index), hasLength(2));
    });

    test('без замены или без её кодов в базе — null, похожее имя не в счёт', () {
      expect(geoSubstitutes('geosite:ru-blocked', _index), isNull);
      expect(geoSubstitutes('geoip:ru-direct', _index), isNull);
      const thin = GeoAssetIndex(geoipCodes: {'ru'}, geositeCodes: {'category-ru'});
      expect(geoSubstitutes('geosite:ru-direct', thin), isNull);
    });

    test('в списках правил заменяется, незнакомое без замены выбрасывается', () {
      final out = stripUnknownGeoTokensText(
          'geosite:ru-direct, vk.com, geosite:no-such-list', _index);
      expect(out.text, 'geosite:category-ru, geosite:tld-ru, vk.com');
      expect(out.dropped, ['geosite:no-such-list']);
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
          'domain': ['geosite:category-ru', 'geosite:tld-ru'],
          'outboundTag': 'direct',
        },
      ]);
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
  });
}
