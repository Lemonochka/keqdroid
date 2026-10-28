import 'dart:convert';

// метка для tool/patches/xray-desktop-process.patch: с ней ядро ищет программу и у локальных SOCKS и HTTP
const kXrayProcessLogTag = 'keq-process-log';

// KEQ_STOP_ON_STDIN_EOF, tool/patches/xray-desktop-stdin-stop.patch
const kXrayStopOnStdinEof = 'KEQ_STOP_ON_STDIN_EOF';

// счётчики и программу в журнале раньше давал мост keqrnel через clash API, теперь сам xray
String withXrayDesktopSession(
  String config, {
  required int metricsPort,
  bool processLog = false,
  String? tunName,
}) {
  final map = jsonDecode(config) as Map<String, dynamic>;
  if (tunName != null) {
    for (final inbound in (map['inbounds'] as List?) ?? const []) {
      if (inbound is Map &&
          inbound['protocol'] == 'tun' &&
          inbound['settings'] is Map) {
        (inbound['settings'] as Map)['name'] = tunName;
      }
    }
  }
  map['stats'] = <String, dynamic>{};
  map['metrics'] = {'listen': '127.0.0.1:$metricsPort'};
  final policy = {...?(map['policy'] as Map?)?.cast<String, dynamic>()};
  policy['system'] = {
    ...?(policy['system'] as Map?)?.cast<String, dynamic>(),
    'statsInboundUplink': true,
    'statsInboundDownlink': true,
  };
  map['policy'] = policy;
  if (processLog) {
    final outbounds = [...?(map['outbounds'] as List?)];
    if (!outbounds.any((o) => o is Map && o['tag'] == kXrayProcessLogTag)) {
      outbounds.add({'protocol': 'blackhole', 'tag': kXrayProcessLogTag});
    }
    map['outbounds'] = outbounds;
  }
  return const JsonEncoder.withIndent('  ').convert(map);
}

// сумма по всем входам, как downloadTotal у clash
({int down, int up}) xrayInboundTotals(Map<String, dynamic> vars) {
  final stats = vars['stats'];
  final inbound = stats is Map ? stats['inbound'] : null;
  var down = 0;
  var up = 0;
  if (inbound is Map) {
    for (final counters in inbound.values) {
      if (counters is! Map) continue;
      down += (counters['downlink'] as num?)?.toInt() ?? 0;
      up += (counters['uplink'] as num?)?.toInt() ?? 0;
    }
  }
  return (down: down, up: up);
}
