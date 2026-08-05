import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/tunnel/app_routing_mode.dart';
import 'package:keqdroid/utils/singbox_tun_config.dart';

/// sing-box (1.11+) не читает v2fly .dat вообще, поэтому geo-токены в TUN-конфиг
/// попадать не должны — их исполняет встроенный xray. Раньше `geosite:telegram`
/// превращался в `domain_suffix: telegram` (мёртвое правило: ни telegram.org,
/// ни t.me так не матчатся), а при финале «обход» трафик до xray не доезжал
/// вовсе — отсюда жалоба «геосайты не учитываются, не грузит ниче».
String _config(AppSettings settings, {AppRoutingMode? mode}) =>
    SingBoxTunConfigGen.generate(
      localSocksPort: 10808,
      socksUsername: 'u',
      socksPassword: 'p',
      serverIpToExclude: '1.2.3.4',
      settings: settings,
      routingMode: mode ?? AppRoutingMode.allProxy,
    );

List<Map<String, dynamic>> _rules(String json) =>
    (((jsonDecode(json) as Map)['route'] as Map)['rules'] as List)
        .cast<Map<String, dynamic>>();

String _final(String json) =>
    ((jsonDecode(json) as Map)['route'] as Map)['final'] as String;

Iterable<String> _allStrings(List<Map<String, dynamic>> rules, String key) =>
    rules.expand((r) {
      final v = r[key];
      return v is List ? v.map((e) => e.toString()) : const <String>[];
    });

void main() {
  test('geosite: tokens never become sing-box domain rules', () {
    final rules = _rules(_config(const AppSettings(
      proxyRules: 'geosite:telegram, youtube.com',
      directRules: 'geosite:category-ru, vk.com',
      blockedRules: 'geosite:category-ads-all',
    )));

    for (final key in ['domain', 'domain_suffix', 'domain_regex']) {
      final values = _allStrings(rules, key).toList();
      expect(
        values.where((v) => v.contains('telegram')),
        isEmpty,
        reason: '$key must not carry a geosite code as a literal domain',
      );
      expect(values.where((v) => v.startsWith('category-')), isEmpty);
    }
    // Обычные домены из того же списка на месте.
    expect(_allStrings(rules, 'domain_suffix'), containsAll(['youtube.com', 'vk.com']));
  });

  test('geoip: codes (including private) stay out of ip_cidr', () {
    // sing-box NewIPCIDRItem принимает только префикс/адрес: любой geoip:-токен
    // в ip_cidr роняет конфиг на загрузке, и ядро выходит ещё до туннеля.
    final rules = _rules(_config(const AppSettings(
      directRules: 'geoip:private, geoip:ru, 10.8.0.0/24',
      proxyRules: 'geoip:telegram',
    )));

    final cidrs = _allStrings(rules, 'ip_cidr').toList();
    expect(cidrs.where((c) => c.toLowerCase().startsWith('geoip:')), isEmpty);
    expect(cidrs, contains('10.8.0.0/24'));
  });

  test('geo rules in proxy/block hand the remainder to xray when final is not proxy', () {
    // Финал «обход»: без этого не совпавшее с правилами sing-box уходило
    // напрямую, и geosite:telegram → proxy не срабатывал вообще.
    final bypass = _config(const AppSettings(
      finalOutbound: AppSettings.finalOutboundDirect,
      proxyRules: 'geosite:telegram',
    ));
    expect(_final(bypass), 'proxy');

    final blocked = _config(const AppSettings(
      finalOutbound: AppSettings.finalOutboundBlock,
      blockedRules: 'geosite:category-ads-all',
    ));
    expect(_final(blocked), 'proxy');
  });

  test('without geo rules the chosen final action is untouched', () {
    expect(
      _final(_config(const AppSettings(
        finalOutbound: AppSettings.finalOutboundDirect,
        proxyRules: 'youtube.com',
      ))),
      'direct',
    );
    expect(
      _final(_config(const AppSettings(
        finalOutbound: AppSettings.finalOutboundBlock,
      ))),
      'block',
    );
  });

  test('geo rules only in the direct list keep the final action', () {
    // Direct-geo при финале direct ничего не меняет: результат тот же, гонять
    // остаток через xray незачем.
    expect(
      _final(_config(const AppSettings(
        finalOutbound: AppSettings.finalOutboundDirect,
        directRules: 'geosite:category-ru',
      ))),
      'direct',
    );
  });

  test('per-app split keeps its own final even with geo rules', () {
    // В onlySelected финал значит «невыбранные приложения идут напрямую» —
    // подменять его на proxy нельзя, иначе сплит по приложениям сломается.
    expect(
      _final(_config(
        const AppSettings(proxyRules: 'geosite:telegram'),
        mode: AppRoutingMode.onlySelected,
      )),
      'direct',
    );
  });
}
