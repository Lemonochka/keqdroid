import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/server_name_utils.dart';

void main() {
  group('ServerNameUtils.extractCountryCode', () {
    test('extracts country code from regional indicator flag emoji', () {
      expect(ServerNameUtils.extractCountryCode('🇩🇪 Germany 01'), 'DE');
      expect(ServerNameUtils.extractCountryCode('🇺🇸 US node'), 'US');
    });
  });
}
