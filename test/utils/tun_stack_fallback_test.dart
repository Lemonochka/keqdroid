import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/tun_settings.dart';
import 'package:keqdroid/utils/singbox_tun_config.dart';

/// Ядро без `-tags with_gvisor` на `stack: gvisor` не ругается в конфиге, а
/// падает при СТАРТЕ («gVisor is not included in this build»): TUN не
/// поднимается вовсе. Умолчание у нас теперь gvisor, поэтому чужая сборка
/// keqrnel (`go build ./...` без тега) означала бы «туннель не работает у
/// всех». Понижаем стек до system — он есть в любой сборке.
String _config(String stack, {bool ein = false}) =>
    SingBoxTunConfigGen.generate(
      localSocksPort: 2080,
      socksUsername: 'u',
      socksPassword: 'p',
      serverIpToExclude: '198.51.100.10',
      settings: AppSettings(
        tun: TunSettings(stack: stack, endpointIndependentNat: ein),
      ),
      windows: true,
    );

Map<String, dynamic> _tunInbound(String config) =>
    ((jsonDecode(config) as Map<String, dynamic>)['inbounds'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((i) => i['type'] == 'tun');

void main() {
  test('gvisor понижается до system, когда ядро без gVisor', () {
    final result = applyTunStackFallback(
      _config(TunSettings.stackGvisor, ein: true),
      gvisorAvailable: false,
    );
    expect(result.downgradedFrom, TunSettings.stackGvisor);
    final tun = _tunInbound(result.config);
    expect(tun['stack'], TunSettings.stackSystem);
    // endpoint_independent_nat живёт только на gvisor/mixed.
    expect(tun.containsKey('endpoint_independent_nat'), isFalse);
  });

  test('mixed понижается так же', () {
    final result = applyTunStackFallback(
      _config(TunSettings.stackMixed),
      gvisorAvailable: false,
    );
    expect(result.downgradedFrom, TunSettings.stackMixed);
    expect(_tunInbound(result.config)['stack'], TunSettings.stackSystem);
  });

  test('ядро с gVisor конфиг не трогает', () {
    final config = _config(TunSettings.stackGvisor);
    final result = applyTunStackFallback(config, gvisorAvailable: true);
    expect(result.downgradedFrom, isNull);
    expect(result.config, config);
  });

  test('«выяснить не удалось» — тоже не трогает', () {
    // null ≠ «нет gVisor»: переписывать выбор пользователя по незнанию нельзя.
    final config = _config(TunSettings.stackGvisor);
    final result = applyTunStackFallback(config, gvisorAvailable: null);
    expect(result.downgradedFrom, isNull);
    expect(result.config, config);
  });

  test('system и так system — понижать нечего', () {
    final config = _config(TunSettings.stackSystem);
    final result = applyTunStackFallback(config, gvisorAvailable: false);
    expect(result.downgradedFrom, isNull);
    expect(result.config, config);
  });

  test('битый json возвращается как есть, без исключения', () {
    final result = applyTunStackFallback('{not json', gvisorAvailable: false);
    expect(result.downgradedFrom, isNull);
    expect(result.config, '{not json');
  });
}
