import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/tunnel/wintun_adapters.dart';
import 'package:keqdroid/utils/desktop_tun.dart';

/// ID устройств сверены с журналом Kernel-PnP/Configuration на ПК, где
/// 27.10.2026 Windows отказывала в адаптере: так их видит Windows.
void main() {
  test('ID адаптеров совпадают с теми, что пишет Windows', () {
    expect(
      xrayWintunInstanceId(kTunInterfaceName),
      r'SWD\Wintun\{C4648041-AEA1-9741-D3E8-27B20B6BB7E5}',
    );
    expect(
      mihomoWintunInstanceId(kTunInterfaceName),
      r'SWD\Wintun\{867A508A-BCB3-1503-38B0-AF5237C35289}',
    );
  });

  test('уборка знает только свои три устройства', () {
    final ids = ourWintunInstanceIds();
    expect(ids.toSet(), hasLength(3));
    expect(ids, contains(xrayWintunInstanceId(kTunFallbackInterfaceName)));
    // адаптер Tailscale с того же ПК, чужой и живой
    expect(
      ids,
      isNot(contains(r'SWD\Wintun\{37217669-42DA-4657-A55B-0D995D328250}')),
    );
  });

  test('первая попытка под обычным именем, дальше запасное', () {
    expect(xrayTunNameForAttempt(1), kTunInterfaceName);
    expect(xrayTunNameForAttempt(2), kTunFallbackInterfaceName);
    expect(xrayTunNameForAttempt(3), kTunFallbackInterfaceName);
    expect(kTunFallbackInterfaceName, matches(RegExp(r'^[a-z0-9-]+$')));
  });
}
