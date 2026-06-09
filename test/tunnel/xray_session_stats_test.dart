import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/tunnel/xray_session_stats.dart';

void main() {
  test('parseStatsQueryOutput sums inbound socks/http traffic', () {
    const stdout = '''
{
  "stat": [
    {"name": "inbound>>>socks-in>>>traffic>>>downlink", "value": "1000"},
    {"name": "inbound>>>socks-in>>>traffic>>>uplink", "value": "200"},
    {"name": "inbound>>>http-in>>>traffic>>>downlink", "value": "3000"},
    {"name": "inbound>>>http-in>>>traffic>>>uplink", "value": "400"},
    {"name": "inbound>>>api>>>traffic>>>downlink", "value": "999"}
  ]
}
''';

    final parsed = XraySessionStats.parseStatsQueryOutput(stdout);
    expect(parsed, isNotNull);
    expect(parsed!.download, 4000);
    expect(parsed.upload, 600);
  });

  test('augmentConfig enables StatsService on loopback', () {
    final out = XraySessionStats.augmentConfig({'log': {'loglevel': 'warning'}});
    expect(out['stats'], isA<Map>());
    expect(out['api'], isA<Map>());
    final api = out['api'] as Map;
    expect(api['listen'], '127.0.0.1:${XraySessionStats.defaultApiPort}');
    final system = (out['policy'] as Map)['system'] as Map;
    expect(system['statsInboundUplink'], isTrue);
    expect(system['statsInboundDownlink'], isTrue);
  });
}
