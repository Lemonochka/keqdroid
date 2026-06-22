import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/routing_entry.dart';

void main() {
  group('splitGeoipTokens', () {
    test('extracts geoip codes and keeps plain IPs', () {
      final r = splitGeoipTokens([
        'geoip:ru',
        '10.0.0.0/8',
        'geoip:private',
        '1.2.3.4',
      ]);
      expect(r.geoipCodes, ['ru', 'private']);
      expect(r.plainIps, ['10.0.0.0/8', '1.2.3.4']);
    });
  });
}
