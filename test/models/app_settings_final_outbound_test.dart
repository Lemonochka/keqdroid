import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';

void main() {
  group('AppSettings.finalOutbound', () {
    test('defaults to proxy', () {
      expect(const AppSettings().finalOutbound, AppSettings.finalOutboundProxy);
      expect(const AppSettings().finalOutbound, 'proxy');
    });

    test('normalizeFinalOutbound accepts the three valid values', () {
      expect(AppSettings.normalizeFinalOutbound('proxy'), 'proxy');
      expect(AppSettings.normalizeFinalOutbound('direct'), 'direct');
      expect(AppSettings.normalizeFinalOutbound('block'), 'block');
    });

    test('normalizeFinalOutbound is case-insensitive and trims', () {
      expect(AppSettings.normalizeFinalOutbound('  DIRECT '), 'direct');
      expect(AppSettings.normalizeFinalOutbound('Block'), 'block');
    });

    test('normalizeFinalOutbound falls back to proxy on junk/null', () {
      expect(AppSettings.normalizeFinalOutbound(null), 'proxy');
      expect(AppSettings.normalizeFinalOutbound(''), 'proxy');
      expect(AppSettings.normalizeFinalOutbound('nonsense'), 'proxy');
    });

    test('toJson carries finalOutbound', () {
      final json = const AppSettings(finalOutbound: 'direct').toJson();
      expect(json['finalOutbound'], 'direct');
    });

    test('fromJson reads finalOutbound', () {
      final s = AppSettings.fromJson(const {'finalOutbound': 'block'});
      expect(s.finalOutbound, 'block');
    });

    test('fromJson without the key defaults to proxy (backward compat)', () {
      final s = AppSettings.fromJson(const {});
      expect(s.finalOutbound, 'proxy');
    });

    test('fromJson normalizes an invalid stored value', () {
      final s = AppSettings.fromJson(const {'finalOutbound': 'weird'});
      expect(s.finalOutbound, 'proxy');
    });

    test('copyWith updates finalOutbound and leaves it otherwise', () {
      const base = AppSettings(finalOutbound: 'direct');
      expect(base.copyWith(finalOutbound: 'block').finalOutbound, 'block');
      expect(base.copyWith().finalOutbound, 'direct');
    });

    test('finalOutbound participates in equality and hashCode', () {
      const a = AppSettings(finalOutbound: 'proxy');
      const b = AppSettings(finalOutbound: 'direct');
      expect(a == b, isFalse);
      expect(a == const AppSettings(finalOutbound: 'proxy'), isTrue);
      expect(a.hashCode == const AppSettings().hashCode, isTrue);
    });

    test('json string round-trip preserves finalOutbound', () {
      const s = AppSettings(finalOutbound: 'block');
      final restored = AppSettings.fromJsonString(s.toJsonString());
      expect(restored.finalOutbound, 'block');
    });

    test('finalOutbounds lists exactly the three actions', () {
      expect(AppSettings.finalOutbounds, ['proxy', 'direct', 'block']);
    });
  });
}
