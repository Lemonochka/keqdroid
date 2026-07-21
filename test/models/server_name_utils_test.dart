import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/server_name_utils.dart';

void main() {
  group('ServerNameUtils.extractCountryCode', () {
    test('extracts country code from regional indicator flag emoji', () {
      expect(ServerNameUtils.extractCountryCode('🇩🇪 Germany 01'), 'DE');
      expect(ServerNameUtils.extractCountryCode('🇺🇸 US node'), 'US');
    });

    test('does not fabricate a flag from unrelated words', () {
      // Регресс: "cloudflARE" содержит "are" (ARE=ОАЭ) → раньше ложный флаг 🇦🇪.
      expect(ServerNameUtils.extractCountryCode('Cloudflare Warp-1'), isNull);
      expect(ServerNameUtils.extractCountryCode('Cloudflare Warp'), isNull);
      // "southamPTon" → "pt", "united kiNGdom" → "ng" — тоже больше не ловятся.
      expect(ServerNameUtils.extractCountryCode('Southampton'), isNull);
      expect(ServerNameUtils.extractCountryCode('United Kingdom'), isNot('NG'));
    });

    test('resolves real country names and codes as whole words', () {
      expect(ServerNameUtils.extractCountryCode('Estonia | 2 | HY2'), 'EE');
      expect(ServerNameUtils.extractCountryCode('Germany-Frankfurt'), 'DE');
      expect(ServerNameUtils.extractCountryCode('US-NYC'), 'US');
      expect(ServerNameUtils.extractCountryCode('Россия 1'), 'RU');
      expect(ServerNameUtils.extractCountryCode('Hong Kong 01'), 'HK');
    });
  });
}
