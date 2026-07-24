import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/tunnel/app_routing_mode.dart';
import 'package:keqdroid/utils/singbox_tun_config.dart';

String _routeFinal(String json) =>
    (jsonDecode(json) as Map<String, dynamic>)['route']['final'] as String;

List<Map<String, dynamic>> _rules(String json) =>
    (((jsonDecode(json) as Map<String, dynamic>)['route'] as Map)['rules']
            as List)
        .cast<Map<String, dynamic>>();

bool _hasKillSwitchCatch(List<Map<String, dynamic>> rules) => rules.any((r) {
      final cidr = r['ip_cidr'];
      return cidr is List &&
          cidr.contains('0.0.0.0/1') &&
          cidr.contains('128.0.0.0/1') &&
          r['outbound'] == 'proxy';
    });

String _gen(AppSettings settings,
        {AppRoutingMode routingMode = AppRoutingMode.allProxy}) =>
    SingBoxTunConfigGen.generate(
      localSocksPort: 10808,
      socksUsername: 'u',
      socksPassword: 'p',
      serverIpToExclude: '1.2.3.4',
      settings: settings,
      routingMode: routingMode,
    );

void main() {
  group('SingBoxTunConfigGen route.final', () {
    test('allProxy + proxy → final proxy', () {
      expect(_routeFinal(_gen(const AppSettings())), 'proxy');
    });

    test('allProxy + direct → final direct (bypass)', () {
      expect(
        _routeFinal(_gen(
            const AppSettings(finalOutbound: AppSettings.finalOutboundDirect))),
        'direct',
      );
    });

    test('allProxy + block → final block', () {
      expect(
        _routeFinal(_gen(
            const AppSettings(finalOutbound: AppSettings.finalOutboundBlock))),
        'block',
      );
    });

    test('kill switch on proxy final forces block + adds proxy catch rule', () {
      final json = _gen(const AppSettings(killSwitch: true));
      expect(_routeFinal(json), 'block');
      expect(_hasKillSwitchCatch(_rules(json)), isTrue);
    });

    test('kill switch does not hijack a direct final (no forced block)', () {
      final json = _gen(const AppSettings(
        killSwitch: true,
        finalOutbound: AppSettings.finalOutboundDirect,
      ));
      expect(_routeFinal(json), 'direct');
      expect(_hasKillSwitchCatch(_rules(json)), isFalse);
    });

    test('kill switch leaves a block final as block, no proxy catch rule', () {
      final json = _gen(const AppSettings(
        killSwitch: true,
        finalOutbound: AppSettings.finalOutboundBlock,
      ));
      expect(_routeFinal(json), 'block');
      expect(_hasKillSwitchCatch(_rules(json)), isFalse);
    });

    test('onlySelected split keeps final direct regardless of finalOutbound',
        () {
      final json = _gen(
        const AppSettings(finalOutbound: AppSettings.finalOutboundProxy),
        routingMode: AppRoutingMode.onlySelected,
      );
      expect(_routeFinal(json), 'direct');
    });

    test('allExceptSelected split keeps final proxy (per-app mode governs)', () {
      final json = _gen(
        const AppSettings(finalOutbound: AppSettings.finalOutboundDirect),
        routingMode: AppRoutingMode.allExceptSelected,
      );
      expect(_routeFinal(json), 'proxy');
    });
  });
}
