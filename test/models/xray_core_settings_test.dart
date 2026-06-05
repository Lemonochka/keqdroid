import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/xray_core_settings.dart';

void main() {
  group('XrayCoreSettings', () {
    test('buildDnsBlock uses custom servers', () {
      const core = XrayCoreSettings(
        dnsUseCustom: true,
        dnsServers: '1.1.1.1\n8.8.8.8',
      );
      final dns = core.buildDnsBlock(directDomains: []);
      final servers = dns['servers'] as List;
      expect(servers.length, 2);
      expect((servers[0] as Map)['address'], '1.1.1.1');
    });

    test('buildXmuxMap returns null when disabled', () {
      expect(const XrayCoreSettings().buildXmuxMap(), isNull);
    });

    test('round-trips JSON', () {
      const core = XrayCoreSettings(
        xmuxEnabled: true,
        xmuxMaxConcurrency: '8-16',
        logLevel: 'info',
      );
      final restored =
          XrayCoreSettings.fromJson(core.toJson());
      expect(restored, core);
    });
  });
}
