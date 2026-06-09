import 'dart:convert';
import 'dart:io';

/// Xray StatsService for live session counters on Windows Proxy mode.
///
/// TUN mode uses sing-box/Wintun adapter counters; loopback does not work on
/// Windows for 127.0.0.1 proxy traffic.
class XraySessionStats {
  XraySessionStats._();

  static const defaultApiPort = 10985;

  static Map<String, dynamic> augmentConfig(
    Map<String, dynamic> config, {
    int apiPort = defaultApiPort,
  }) {
    final out = Map<String, dynamic>.from(config);
    out['stats'] = <String, dynamic>{};
    out['api'] = {
      'tag': 'api',
      'listen': '127.0.0.1:$apiPort',
      'services': <String>['StatsService'],
    };
    final policy = Map<String, dynamic>.from(
      out['policy'] as Map<String, dynamic>? ?? {},
    );
    final system = Map<String, dynamic>.from(
      policy['system'] as Map<String, dynamic>? ?? {},
    );
    system['statsInboundUplink'] = true;
    system['statsInboundDownlink'] = true;
    policy['system'] = system;
    out['policy'] = policy;
    return out;
  }

  /// Returns cumulative inbound downlink/uplink bytes (user download/upload).
  static ({int download, int upload})? parseStatsQueryOutput(String stdout) {
    final dynamic decoded = jsonDecode(stdout);
    if (decoded is! Map) return null;
    final stats = decoded['stat'];
    if (stats is! List) return null;

    var download = 0;
    var upload = 0;
    for (final item in stats) {
      if (item is! Map) continue;
      final name = item['name']?.toString() ?? '';
      if (!name.startsWith('inbound>>>')) continue;
      final parts = name.split('>>>');
      if (parts.length != 4 || parts[2] != 'traffic') continue;
      if (parts[1] == 'api') continue;
      final value = int.tryParse(item['value']?.toString() ?? '') ?? 0;
      switch (parts[3]) {
        case 'downlink':
          download += value;
        case 'uplink':
          upload += value;
      }
    }
    return (download: download, upload: upload);
  }

  static Future<({int download, int upload})?> queryInboundCounters({
    required String xrayExecutable,
    int apiPort = defaultApiPort,
  }) async {
    try {
      final result = await Process.run(
        xrayExecutable,
        ['api', 'statsquery', '--server=127.0.0.1:$apiPort'],
        runInShell: false,
      );
      if (result.exitCode != 0) return null;
      final stdout = result.stdout?.toString() ?? '';
      if (stdout.trim().isEmpty) return null;
      return parseStatsQueryOutput(stdout);
    } catch (_) {
      return null;
    }
  }
}
