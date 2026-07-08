import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/tun_settings.dart';
import 'package:keqdroid/models/xray_core_settings.dart';
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

  Map<String, dynamic> proxyDnsFor(AppSettings settings) {
    final json = SingBoxTunConfigGen.generate(
      localSocksPort: 10808,
      socksUsername: 'u',
      socksPassword: 'p',
      serverIpToExclude: '1.2.3.4',
      settings: settings,
    );
    final map = jsonDecode(json) as Map<String, dynamic>;
    final servers =
        ((map['dns'] as Map)['servers'] as List).cast<Map<String, dynamic>>();
    return servers.firstWhere((s) => s['tag'] == 'proxy-dns');
  }

  test('default proxy-dns is DoH over the tunnel (port 53 may be blocked)', () {
    // Многие VPS режут исходящий 53 → UDP/TCP DNS через прокси умирали с EOF,
    // «сайты не грузятся» при живом туннеле. DoH:443 неотличим от HTTPS.
    final proxyDns = proxyDnsFor(const AppSettings());
    expect(proxyDns['type'], 'https');
    expect(proxyDns['server'], '1.1.1.1');
    expect(proxyDns['detour'], 'proxy');
  });

  test('custom plain-IP DNS rides TCP (never UDP) over the SOCKS detour', () {
    final proxyDns = proxyDnsFor(
      const AppSettings(
        xrayCore: XrayCoreSettings(dnsUseCustom: true, dnsServers: '8.8.8.8'),
      ),
    );
    expect(proxyDns['type'], 'tcp');
    expect(proxyDns['server'], '8.8.8.8');
    expect(proxyDns['detour'], 'proxy');
  });

  test('kill switch (allProxy): final becomes block, split CIDRs go to proxy', () {
    final json = SingBoxTunConfigGen.generate(
      localSocksPort: 10808,
      socksUsername: 'u',
      socksPassword: 'p',
      serverIpToExclude: '1.2.3.4',
      settings: const AppSettings(killSwitch: true),
    );
    final map = jsonDecode(json) as Map<String, dynamic>;
    final rules = _rules(json);

    final splitRule = rules.firstWhere(
      (r) => (r['ip_cidr'] as List?)?.contains('0.0.0.0/1') == true,
    );
    expect(splitRule['outbound'], 'proxy');
    expect(splitRule['ip_cidr'] as List, contains('128.0.0.0/1'));
    // весь несматченный трафик блокируется, а не утекает напрямую
    expect((map['route'] as Map)['final'], 'block');
  });

  test('kill switch is inert outside allProxy routing', () {
    final json = SingBoxTunConfigGen.generate(
      localSocksPort: 10808,
      socksUsername: 'u',
      socksPassword: 'p',
      serverIpToExclude: '1.2.3.4',
      settings: const AppSettings(killSwitch: true),
      routingMode: AppRoutingMode.onlySelected,
    );
    final map = jsonDecode(json) as Map<String, dynamic>;
    expect((map['route'] as Map)['final'], 'direct');
  });

  Map<String, dynamic> tunInboundFor(AppSettings settings) {
    final json = SingBoxTunConfigGen.generate(
      localSocksPort: 10808,
      socksUsername: 'u',
      socksPassword: 'p',
      serverIpToExclude: '1.2.3.4',
      settings: settings,
    );
    final map = jsonDecode(json) as Map<String, dynamic>;
    return (map['inbounds'] as List).first as Map<String, dynamic>;
  }

  test('default tun inbound matches the legacy hardcoded values', () {
    final inbound = tunInboundFor(const AppSettings());
    expect(inbound['stack'], 'system');
    expect(inbound['mtu'], 1400);
    expect(inbound['auto_route'], isTrue);
    // дефолтные значения не должны раздувать конфиг новыми ключами
    expect(inbound.containsKey('endpoint_independent_nat'), isFalse);
    expect(inbound.containsKey('udp_timeout'), isFalse);
  });

  test('tun settings flow into the inbound (stack, mtu, udp_timeout, EIN)', () {
    final inbound = tunInboundFor(const AppSettings(
      tun: TunSettings(
        stack: 'gvisor',
        mtu: 9000,
        strictRoute: TunSettings.strictRouteOn,
        endpointIndependentNat: true,
        udpTimeoutSec: 60,
      ),
    ));
    expect(inbound['stack'], 'gvisor');
    expect(inbound['mtu'], 9000);
    expect(inbound['strict_route'], isTrue);
    expect(inbound['endpoint_independent_nat'], isTrue);
    // sing-box 1.13 (keqrnel): badoption.Duration — строка вида "60s"
    expect(inbound['udp_timeout'], '60s');
  });

  test('endpoint_independent_nat is dropped on the system stack', () {
    // system-стек его не поддерживает — не шлём ядру бессмысленный ключ
    final inbound = tunInboundFor(const AppSettings(
      tun: TunSettings(stack: 'system', endpointIndependentNat: true),
    ));
    expect(inbound.containsKey('endpoint_independent_nat'), isFalse);
  });

  test('strict route on/off overrides the platform default', () {
    final on = tunInboundFor(const AppSettings(
      tun: TunSettings(strictRoute: TunSettings.strictRouteOn),
    ));
    expect(on['strict_route'], isTrue);

    final off = tunInboundFor(const AppSettings(
      tun: TunSettings(strictRoute: TunSettings.strictRouteOff),
    ));
    expect(off['strict_route'], isFalse);
  });

  test('auto_route can be disabled for manual route management', () {
    final inbound = tunInboundFor(const AppSettings(
      tun: TunSettings(autoRoute: false),
    ));
    expect(inbound['auto_route'], isFalse);
  });

  test('custom DNS is ignored while dnsUseCustom is off', () {
    final proxyDns = proxyDnsFor(
      const AppSettings(
        xrayCore: XrayCoreSettings(dnsUseCustom: false, dnsServers: '8.8.8.8'),
      ),
    );
    expect(proxyDns['type'], 'https'); // дефолтный DoH, а не выключенный кастом
  });
}
