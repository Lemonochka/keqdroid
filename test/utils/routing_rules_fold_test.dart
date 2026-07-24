import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/routing_rule.dart';
import 'package:keqdroid/utils/routing_rules_fold.dart';

RoutingRule _rule({
  required RuleType type,
  required List<String> values,
  required RuleAction action,
  bool enabled = true,
}) =>
    RoutingRule(
      id: 'id-${values.join()}-${action.value}',
      name: 'r',
      type: type,
      values: values,
      action: action,
      enabled: enabled,
    );

void main() {
  const base = AppSettings(
    directRules: 'existing-direct.com',
    proxyRules: 'existing-proxy.com',
    blockedRules: 'existing-block.com',
  );

  group('applyRoutingRules', () {
    test('empty rule list returns the settings unchanged (identical)', () {
      expect(identical(applyRoutingRules(base, const []), base), isTrue);
    });

    test('all-disabled rules leave settings unchanged', () {
      final out = applyRoutingRules(base, [
        _rule(
            type: RuleType.domain,
            values: ['x.com'],
            action: RuleAction.proxy,
            enabled: false),
      ]);
      expect(identical(out, base), isTrue);
    });

    test('domain proxy rule lands in proxyRules', () {
      final out = applyRoutingRules(base, [
        _rule(
            type: RuleType.domain,
            values: ['youtube.com'],
            action: RuleAction.proxy),
      ]);
      expect(out.proxyRules, contains('youtube.com'));
      expect(out.proxyRules, contains('existing-proxy.com'));
      // other lists untouched
      expect(out.directRules, base.directRules);
      expect(out.blockedRules, base.blockedRules);
    });

    test('direct action goes to directRules, block to blockedRules', () {
      final out = applyRoutingRules(base, [
        _rule(
            type: RuleType.ipCidr,
            values: ['10.1.2.0/24'],
            action: RuleAction.direct),
        _rule(
            type: RuleType.domain,
            values: ['ads.example'],
            action: RuleAction.block),
      ]);
      expect(out.directRules, contains('10.1.2.0/24'));
      expect(out.blockedRules, contains('ads.example'));
    });

    test('geoip values get the geoip: prefix', () {
      final out = applyRoutingRules(base, [
        _rule(type: RuleType.geoip, values: ['RU'], action: RuleAction.direct),
      ]);
      expect(out.directRules, contains('geoip:RU'));
    });

    test('geoip value already prefixed is not double-prefixed', () {
      final out = applyRoutingRules(base, [
        _rule(
            type: RuleType.geoip,
            values: ['geoip:us'],
            action: RuleAction.proxy),
      ]);
      expect(out.proxyRules, contains('geoip:us'));
      expect(out.proxyRules.contains('geoip:geoip:'), isFalse);
    });

    test('geosite values get the geosite: prefix', () {
      final out = applyRoutingRules(base, [
        _rule(
            type: RuleType.geosite,
            values: ['category-ads-all'],
            action: RuleAction.block),
      ]);
      expect(out.blockedRules, contains('geosite:category-ads-all'));
    });

    test('processName rules are skipped (handled by split tunneling)', () {
      final out = applyRoutingRules(base, [
        _rule(
            type: RuleType.processName,
            values: ['chrome.exe'],
            action: RuleAction.proxy),
      ]);
      expect(identical(out, base), isTrue);
    });

    test('blank values within a rule are dropped', () {
      final out = applyRoutingRules(base, [
        _rule(
            type: RuleType.domain,
            values: ['  ', 'real.com', ''],
            action: RuleAction.proxy),
      ]);
      expect(out.proxyRules, contains('real.com'));
    });

    test('a rule with only blank values changes nothing', () {
      final out = applyRoutingRules(base, [
        _rule(
            type: RuleType.domain,
            values: ['   ', ''],
            action: RuleAction.proxy),
      ]);
      expect(identical(out, base), isTrue);
    });

    test('multiple values from one rule all appear', () {
      final out = applyRoutingRules(base, [
        _rule(
            type: RuleType.domain,
            values: ['a.com', 'b.com'],
            action: RuleAction.proxy),
      ]);
      expect(out.proxyRules, contains('a.com'));
      expect(out.proxyRules, contains('b.com'));
    });

    test('appends onto an empty list without a leading separator', () {
      const empty = AppSettings(
        directRules: '',
        proxyRules: '',
        blockedRules: '',
      );
      final out = applyRoutingRules(empty, [
        _rule(
            type: RuleType.domain,
            values: ['solo.com'],
            action: RuleAction.proxy),
      ]);
      expect(out.proxyRules, 'solo.com');
    });
  });
}
