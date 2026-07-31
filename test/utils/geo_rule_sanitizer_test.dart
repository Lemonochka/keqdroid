import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/utils/geo_asset_index.dart';
import 'package:keqdroid/utils/geo_rule_sanitizer.dart';

void main() {
  const index = GeoAssetIndex(
    geoipCodes: {'ru', 'us', 'private'},
    geositeCodes: {'yandex', 'youtube', 'category-ads-all', 'google'},
  );

  AppSettings settings({
    String direct = '',
    String proxy = '',
    String blocked = '',
  }) =>
      AppSettings(
        directRules: direct,
        proxyRules: proxy,
        blockedRules: blocked,
      );

  group('isKnownGeoToken', () {
    test('non-geo tokens are always kept', () {
      for (final token in [
        'ru',
        'yandex.ru',
        '10.0.0.0/8',
        'domain:vk.com',
        'regexp:.*\\.ru\$',
        'full:example.com',
        'ext:geoip.dat:cn',
      ]) {
        expect(isKnownGeoToken(token, index), isTrue, reason: token);
      }
    });

    test('known codes pass, unknown ones do not', () {
      expect(isKnownGeoToken('geosite:yandex', index), isTrue);
      expect(isKnownGeoToken('GeoSite:YouTube', index), isTrue);
      expect(isKnownGeoToken('geoip:ru', index), isTrue);
      expect(isKnownGeoToken('geosite:sberbank', index), isFalse);
      expect(isKnownGeoToken('geoip:telegram', index), isFalse);
      expect(isKnownGeoToken('geosite:', index), isFalse);
    });

    test('negation and attribute syntax is resolved to the bare code', () {
      expect(isKnownGeoToken('geoip:!ru', index), isTrue);
      expect(isKnownGeoToken('geosite:google@ads', index), isTrue);
      expect(isKnownGeoToken('geoip:!nowhere', index), isFalse);
      expect(isKnownGeoToken('geosite:nowhere@ads', index), isFalse);
    });

    test('an empty database disables validation for that kind', () {
      const geoipOnly = GeoAssetIndex(geoipCodes: {'ru'}, geositeCodes: {});
      expect(isKnownGeoToken('geosite:whatever', geoipOnly), isTrue);
      expect(isKnownGeoToken('geoip:whatever', geoipOnly), isFalse);
    });
  });

  group('stripUnknownGeoTokens', () {
    test('drops unknown codes and reports them', () {
      final result = stripUnknownGeoTokens(
        settings(
          direct: 'geosite:yandex, geosite:sberbank, ru, 10.0.0.0/8',
          proxy: 'geosite:youtube\ngeoip:telegram\ngeosite:claude',
          blocked: 'geosite:category-ads-all, doubleclick.net',
        ),
        index,
      );

      expect(result.settings.directRules, 'geosite:yandex, ru, 10.0.0.0/8');
      expect(result.settings.proxyRules, 'geosite:youtube');
      expect(
        result.settings.blockedRules,
        'geosite:category-ads-all, doubleclick.net',
      );
      expect(
        result.dropped,
        ['geosite:sberbank', 'geoip:telegram', 'geosite:claude'],
      );
    });

    test('returns the very same settings when nothing is dropped', () {
      final input = settings(direct: 'geosite:yandex, ru');
      final result = stripUnknownGeoTokens(input, index);
      expect(identical(result.settings, input), isTrue);
      expect(result.dropped, isEmpty);
    });

    test('an empty index leaves the rules untouched', () {
      final input = settings(direct: 'geosite:sberbank, geoip:telegram');
      final result = stripUnknownGeoTokens(input, GeoAssetIndex.empty);
      expect(identical(result.settings, input), isTrue);
      expect(result.dropped, isEmpty);
    });

    test('a list made only of unknown codes becomes empty, not invalid', () {
      final result = stripUnknownGeoTokens(
        settings(blocked: 'geosite:nope, geoip:nope'),
        index,
      );
      expect(result.settings.blockedRules, isEmpty);
      expect(result.dropped, hasLength(2));
    });
  });
}
