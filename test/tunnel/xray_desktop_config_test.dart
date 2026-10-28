import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/tunnel/xray_desktop_config.dart';

/// Счётчики и программа в журнале на ПК: раньше их давал мост keqrnel через
/// clash API, теперь сам xray (metrics и патч xray-desktop-process).
void main() {
  Map<String, dynamic> prepared(
    Map<String, dynamic> config, {
    bool processLog = false,
  }) =>
      jsonDecode(withXrayDesktopSession(
        jsonEncode(config),
        metricsPort: 41234,
        processLog: processLog,
      )) as Map<String, dynamic>;

  test('metrics только на loopback, счётчики входов включены', () {
    final config = prepared({
      'outbounds': [
        {'protocol': 'freedom', 'tag': 'proxy'},
      ],
    });
    expect(config['metrics'], {'listen': '127.0.0.1:41234'});
    expect(config['stats'], isEmpty);
    expect((config['policy'] as Map)['system'], {
      'statsInboundUplink': true,
      'statsInboundDownlink': true,
    });
  });

  test('уровни политики из генератора не теряются', () {
    final config = prepared({
      'policy': {
        'levels': {
          '1': {'connIdle': 60},
        },
      },
      'outbounds': const [],
    });
    expect(
      ((config['policy'] as Map)['levels'] as Map)['1'],
      {'connIdle': 60},
    );
  });

  test('метка поиска программы только в отладке и один раз', () {
    bool marked(Map<String, dynamic> c) => (c['outbounds'] as List)
        .any((o) => (o as Map)['tag'] == kXrayProcessLogTag);
    final base = {
      'outbounds': [
        {'protocol': 'freedom', 'tag': 'proxy'},
      ],
    };
    expect(marked(prepared(base)), isFalse);
    final debug = prepared(base, processLog: true);
    expect(marked(debug), isTrue);
    expect(
      (debug['outbounds'] as List).first,
      {'protocol': 'freedom', 'tag': 'proxy'},
      reason: 'первый выход у xray основной',
    );
    final twice = prepared(debug, processLog: true);
    expect(
      (twice['outbounds'] as List)
          .where((o) => (o as Map)['tag'] == kXrayProcessLogTag)
          .length,
      1,
    );
  });

  test('запасное имя адаптера меняет только вход TUN', () {
    final source = {
      'inbounds': [
        {
          'tag': 'tun-in',
          'protocol': 'tun',
          'settings': {'name': 'tun-keqdis', 'mtu': 1500},
        },
        {
          'tag': 'socks-in',
          'protocol': 'socks',
          'settings': {'auth': 'noauth'},
        },
      ],
    };
    final inbounds = jsonDecode(withXrayDesktopSession(
      jsonEncode(source),
      metricsPort: 41234,
      tunName: 'tun-keqdis2',
    ))['inbounds'] as List;
    expect(inbounds[0]['settings'], {'name': 'tun-keqdis2', 'mtu': 1500});
    expect(inbounds[1]['settings'], {'auth': 'noauth'});

    final untouched = jsonDecode(withXrayDesktopSession(
      jsonEncode(source),
      metricsPort: 41234,
    ))['inbounds'] as List;
    expect(untouched[0]['settings']['name'], 'tun-keqdis');
  });

  test('трафик это сумма по всем входам', () {
    expect(
      xrayInboundTotals({
        'stats': {
          'inbound': {
            'tun-in': {'uplink': 100, 'downlink': 1000},
            'socks-in': {'uplink': 5, 'downlink': 50},
            'api': 'мусор',
          },
          'outbound': {
            'proxy': {'uplink': 999999, 'downlink': 999999},
          },
        },
        'memstats': {'Alloc': 1},
      }),
      (down: 1050, up: 105),
    );
    expect(xrayInboundTotals(const {}), (down: 0, up: 0));
  });
}
