import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

const _server =
    'vless://11111111-1111-1111-1111-111111111111@example.com:443?type=tcp&security=none#test';

/// Catch-all — последнее routing-правило: {outboundTag, network: 'tcp,udp'} без
/// domain/ip/inboundTag.
String _finalTag(String configJson) {
  final map = jsonDecode(configJson) as Map<String, dynamic>;
  final rules =
      ((map['routing'] as Map)['rules'] as List).cast<Map<String, dynamic>>();
  final catchAll = rules.last;
  expect(catchAll['network'], 'tcp,udp');
  expect(catchAll.containsKey('domain'), isFalse);
  expect(catchAll.containsKey('ip'), isFalse);
  expect(catchAll.containsKey('inboundTag'), isFalse);
  return catchAll['outboundTag'] as String;
}

void main() {
  setUp(() => Socks5Credentials().init('u', 'p'));

  group('ConfigGeneratorV2 final outbound', () {
    test('default settings send unmatched traffic to proxy', () {
      final cfg = ConfigGeneratorV2.generateConfig(_server, const AppSettings());
      expect(_finalTag(cfg), 'proxy');
    });

    test('finalOutbound=direct makes the catch-all direct (bypass)', () {
      final cfg = ConfigGeneratorV2.generateConfig(
        _server,
        const AppSettings(finalOutbound: AppSettings.finalOutboundDirect),
      );
      expect(_finalTag(cfg), 'direct');
    });

    test('finalOutbound=block makes the catch-all block', () {
      final cfg = ConfigGeneratorV2.generateConfig(
        _server,
        const AppSettings(finalOutbound: AppSettings.finalOutboundBlock),
      );
      expect(_finalTag(cfg), 'block');
    });

    test('the three outbound tags all exist so any final resolves', () {
      final cfg = ConfigGeneratorV2.generateConfig(_server, const AppSettings());
      final map = jsonDecode(cfg) as Map<String, dynamic>;
      final tags = (map['outbounds'] as List)
          .map((o) => (o as Map)['tag'] ?? (o)['protocol'])
          .toList();
      expect(tags, containsAll(<String>['proxy', 'direct', 'block']));
    });

    test('ping config always uses proxy as catch-all, ignoring finalOutbound',
        () {
      final cfg = ConfigGeneratorV2.generatePingConfig(
        _server,
        const AppSettings(finalOutbound: AppSettings.finalOutboundDirect),
        socksPort: ConfigGeneratorV2.ephemeralPingPort,
      );
      expect(_finalTag(cfg), 'proxy');
    });
  });
}
