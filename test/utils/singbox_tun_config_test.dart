import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/tunnel/app_routing_mode.dart';
import 'package:keqdroid/utils/singbox_tun_config.dart';

List<Map<String, dynamic>> _rules(String json) {
  final map = jsonDecode(json) as Map<String, dynamic>;
  return ((map['route'] as Map)['rules'] as List)
      .cast<Map<String, dynamic>>();
}

Map<String, dynamic>? _processRule(List<Map<String, dynamic>> rules, String name) {
  for (final r in rules) {
    final procs = r['process_name'];
    if (procs is List && procs.contains(name)) return r;
  }
  return null;
}

void main() {
  test('TUN inbound uses route sniff action, not legacy inbound sniff fields', () {
    final json = SingBoxTunConfigGen.generate(
      localSocksPort: 10808,
      socksUsername: 'u',
      socksPassword: 'p',
      serverIpToExclude: '1.2.3.4',
      settings: const AppSettings(),
    );
    final map = jsonDecode(json) as Map<String, dynamic>;
    final inbound = (map['inbounds'] as List).first as Map<String, dynamic>;

    expect(inbound.containsKey('sniff'), isFalse);
    expect(inbound.containsKey('sniff_override_destination'), isFalse);

    final rules = (map['route'] as Map)['rules'] as List;
    final sniffRule = rules.first as Map<String, dynamic>;
    expect(sniffRule['action'], 'sniff');
    expect(sniffRule['inbound'], ['tun-in']);
    expect(sniffRule.containsKey('sniff_override_destination'), isFalse);

    final icmpRule = rules.firstWhere(
      (r) => (r as Map)['protocol'] == 'icmp',
    ) as Map<String, dynamic>;
    expect(icmpRule['outbound'], 'direct');

    final tunSubnetRule = rules.firstWhere(
      (r) =>
          (r as Map).containsKey('ip_cidr') &&
          ((r['ip_cidr'] as List).contains('172.19.0.0/30')),
    ) as Map<String, dynamic>;
    expect(tunSubnetRule['outbound'], 'direct');
  });

  test('cores and the app itself bypass the TUN (ping originates locally)', () {
    final rules = _rules(SingBoxTunConfigGen.generate(
      localSocksPort: 10808,
      socksUsername: 'u',
      socksPassword: 'p',
      serverIpToExclude: '1.2.3.4',
      settings: const AppSettings(),
      appProcessName: 'keqdroid.exe',
    ));

    final xrayRule = _processRule(rules, 'xray.exe');
    expect(xrayRule, isNotNull, reason: 'xray.exe must bypass the TUN');
    expect(xrayRule!['outbound'], 'direct');

    final singRule = _processRule(rules, 'sing-box.exe');
    expect(singRule, isNotNull);
    expect(singRule!['outbound'], 'direct');

    final appRule = _processRule(rules, 'keqdroid.exe');
    expect(appRule, isNotNull, reason: 'app exe must bypass for local ping');
    expect(appRule!['outbound'], 'direct');
  });

  test('onlySelected: selected processes proxied, everything else direct', () {
    final json = SingBoxTunConfigGen.generate(
      localSocksPort: 10808,
      socksUsername: 'u',
      socksPassword: 'p',
      serverIpToExclude: '1.2.3.4',
      settings: const AppSettings(),
      managedProcessNames: const ['chrome.exe'],
      routingMode: AppRoutingMode.onlySelected,
    );
    final map = jsonDecode(json) as Map<String, dynamic>;
    final rules = _rules(json);

    final chromeRule = _processRule(rules, 'chrome.exe');
    expect(chromeRule, isNotNull);
    expect(chromeRule!['outbound'], 'proxy');
    expect((map['route'] as Map)['final'], 'direct');
  });

  test('mixed-case process name keeps its real case (sing-box match is case-sensitive)', () {
    final rules = _rules(SingBoxTunConfigGen.generate(
      localSocksPort: 10808,
      socksUsername: 'u',
      socksPassword: 'p',
      serverIpToExclude: '1.2.3.4',
      settings: const AppSettings(),
      managedProcessNames: const ['Telegram.exe'],
      routingMode: AppRoutingMode.onlySelected,
    ));

    // The exact on-disk case must be present, otherwise sing-box never matches
    // and Telegram falls through to the `direct` final rule.
    final rule = _processRule(rules, 'Telegram.exe');
    expect(rule, isNotNull, reason: 'exact-case key must be emitted');
    expect(rule!['outbound'], 'proxy');
    // A lowercase fallback variant is also emitted for resilience.
    expect((rule['process_name'] as List), contains('telegram.exe'));
  });

  test('allExceptSelected: selected processes direct, everything else proxied', () {
    final json = SingBoxTunConfigGen.generate(
      localSocksPort: 10808,
      socksUsername: 'u',
      socksPassword: 'p',
      serverIpToExclude: '1.2.3.4',
      settings: const AppSettings(),
      managedProcessNames: const ['chrome.exe'],
      routingMode: AppRoutingMode.allExceptSelected,
    );
    final map = jsonDecode(json) as Map<String, dynamic>;
    final rules = _rules(json);

    final chromeRule = _processRule(rules, 'chrome.exe');
    expect(chromeRule, isNotNull);
    expect(chromeRule!['outbound'], 'direct');
    expect((map['route'] as Map)['final'], 'proxy');
  });
}
