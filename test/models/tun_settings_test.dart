import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/tun_settings.dart';

void main() {
  test('defaults are gvisor/9000 — what sing-box itself would pick', () {
    const tun = TunSettings();
    // system-стек на Windows терминирует TCP листенером на адресе TUN и живёт
    // правилом Windows Firewall; не встало правило — туннель поднят, а трафика
    // нет. gvisor держит стек в процессе ядра и от фаервола не зависит.
    expect(tun.stack, 'gvisor');
    expect(tun.mtu, 9000);
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
    expect(tun.stack, TunSettings.defaultStack);
    expect(tun.mtu, TunSettings.minMtu);
    expect(tun.strictRoute, 'auto');
    expect(tun.udpTimeoutSec, TunSettings.maxUdpTimeoutSec);
  });

  test('прежняя пара умолчаний (system/1400) мигрирует на новую', () {
    // Настройки пишутся целиком при любом изменении, поэтому старая пара лежит
    // почти у всех — и почти ни у кого не выбрана осознанно.
    final migrated = TunSettings.fromJson({
      'stack': 'system',
      'mtu': 1400,
      'strictRoute': 'auto',
      'udpTimeoutSec': 300,
      'autoRoute': true,
    });
    expect(migrated.stack, 'gvisor');
    expect(migrated.mtu, 9000);

    // …но только один раз: после записи маркер версии есть, и выбор
    // пользователя (пусть даже совпавший со старым дефолтом) остаётся его.
    final kept = TunSettings.fromJson(migrated
        .copyWith(stack: 'system', mtu: 1400)
        .toJson());
    expect(kept.stack, 'system');
    expect(kept.mtu, 1400);
  });

  test('свои значения миграция не трогает', () {
    final tun = TunSettings.fromJson({'stack': 'system', 'mtu': 1500});
    expect(tun.stack, 'system');
    expect(tun.mtu, 1500);
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
