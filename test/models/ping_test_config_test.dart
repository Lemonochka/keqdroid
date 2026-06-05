import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/ping_test_config.dart';

void main() {
  group('PingTestConfig', () {
    test('resolves preset URLs', () {
      const s = AppSettings(pingTestTarget: PingTestConfig.targetCloudflare);
      expect(
        PingTestConfig.resolveTestUrl(s),
        PingTestConfig.presetUrls[PingTestConfig.targetCloudflare],
      );
    });

    test('resolves custom URL with https prefix', () {
      const s = AppSettings(
        pingTestTarget: PingTestConfig.targetCustom,
        pingTestUrlCustom: 'example.com/ping',
      );
      expect(
        PingTestConfig.resolveTestUrl(s),
        'https://example.com/ping',
      );
    });

    test('upgrades http custom URL to https for Android cleartext policy', () {
      const s = AppSettings(
        pingTestTarget: PingTestConfig.targetCustom,
        pingTestUrlCustom: 'http://example.com/ping',
      );
      expect(
        PingTestConfig.resolveTestUrl(s),
        'https://example.com/ping',
      );
    });

    test('preset URLs use https', () {
      for (final url in PingTestConfig.presetUrls.values) {
        expect(url.startsWith('https://'), isTrue, reason: url);
      }
    });

    test('rejects localhost custom URL', () {
      expect(
        PingTestConfig.validateCustomUrl('http://127.0.0.1/test'),
        isNotNull,
      );
    });
  });
}
