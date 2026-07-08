import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/tun_settings.dart';

void main() {
  test('defaults match the previously hardcoded tun inbound', () {
    const tun = TunSettings();
    expect(tun.stack, 'system');
    expect(tun.mtu, 1400);
    expect(tun.strictRoute, 'auto');
    expect(tun.endpointIndependentNat, isFalse);
    expect(tun.udpTimeoutSec, 300);
    expect(tun.autoRoute, isTrue);
    expect(tun.isDefault, isTrue);
  });

  test('strict route auto keeps old per-platform behavior', () {
    const tun = TunSettings();
    expect(tun.strictRouteEnabled(windows: true), isFalse);
    expect(tun.strictRouteEnabled(windows: false), isTrue);

    const on = TunSettings(strictRoute: TunSettings.strictRouteOn);
    expect(on.strictRouteEnabled(windows: true), isTrue);

    const off = TunSettings(strictRoute: TunSettings.strictRouteOff);
    expect(off.strictRouteEnabled(windows: false), isFalse);
  });

  test('json roundtrip preserves all fields', () {
    const tun = TunSettings(
      stack: 'gvisor',
      mtu: 9000,
      strictRoute: 'on',
      endpointIndependentNat: true,
      udpTimeoutSec: 60,
      autoRoute: false,
    );
    expect(TunSettings.fromJson(tun.toJson()), tun);
  });

  test('fromJson sanitizes garbage back to safe values', () {
    final tun = TunSettings.fromJson({
      'stack': 'lwip', // удалённый из sing-box стек
      'mtu': 40,
      'strictRoute': 'maybe',
      'udpTimeoutSec': 999999,
    });
    expect(tun.stack, 'system');
    expect(tun.mtu, TunSettings.minMtu);
    expect(tun.strictRoute, 'auto');
    expect(tun.udpTimeoutSec, TunSettings.maxUdpTimeoutSec);
  });

  test('missing "tun" key in stored AppSettings falls back to defaults', () {
    // Старые установки без ключа tun не должны падать и не должны менять
    // поведение туннеля.
    final settings = AppSettings.fromJson({'localPort': 2080});
    expect(settings.tun.isDefault, isTrue);
  });

  test('AppSettings json roundtrip keeps tun settings', () {
    const settings = AppSettings(
      tun: TunSettings(stack: 'mixed', mtu: 1500),
    );
    final restored = AppSettings.fromJsonString(settings.toJsonString());
    expect(restored.tun.stack, 'mixed');
    expect(restored.tun.mtu, 1500);
    expect(restored, settings);
  });
}
