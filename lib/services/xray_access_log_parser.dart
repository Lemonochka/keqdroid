import '../models/connection_entry.dart';

class XrayAccessLogParser {
  XrayAccessLogParser._();

  // -> правило сработало, >> дефолтный аутбаунд, ==> тег навязан платформой
  static final _access = RegExp(
    r'from\s+(\S+)\s+(accepted|rejected)\s+([a-z0-9]+):(.+?):(\d+)'
    r'(?:\s+\[([^\]]*)\])?',
    caseSensitive: false,
  );

  // HTTP-вход пишет URL запроса (proxy/http/server.go), у CONNECT без схемы: //хост:порт
  static final _accessUrl = RegExp(
    r'from\s+(\S+)\s+(accepted|rejected)\s+(?:([a-z]+):)?//([^/?#\s]+)\S*'
    r'(?:\s+\[([^\]]*)\])?',
    caseSensitive: false,
  );

  // tool/patches/xray-desktop-process.patch, последним: в пути бывают пробелы
  static final _process = RegExp(r'\sprocess:\s(.+)$');

  static final _detour = RegExp(
    r'(?:Hit route rule:\s*\[([^\]]*)\]\s*so\s*)?taking detour\s*'
    r'\[([^\]]*)\]\s*for\s*\[([a-z0-9]+):(.+?):(\d+)\]',
    caseSensitive: false,
  );

  static final _defaultRoute = RegExp(
    r'default route for\s+([a-z0-9]+):(.+?):(\d+)',
    caseSensitive: false,
  );

  static final _timestamp = RegExp(
    r'(\d{4})/(\d{2})/(\d{2})\s+(\d{2}):(\d{2}):(\d{2})',
  );

  static final _deviceTimestamp = RegExp(
    r'^(\d{2})-(\d{2})\s+(\d{2}):(\d{2}):(\d{2})\s',
  );

  static final _sessionLine = RegExp(r'\[Info\]\s*\[(\d+)\]\s*(.+)$');

  static final _sessionDest = RegExp(
    r'(?:TCP Connect request to|establishing new connection for)\s+'
    r'([a-z0-9]+):(.+?):(\d+)\s*$',
    caseSensitive: false,
  );

  static final _sessionClient = RegExp(
    r'client UDP connection from\s+(\S+)',
    caseSensitive: false,
  );

  static final _sessionTun = RegExp(
    r'processing from\s+(\S+)\s+to\s+([a-z0-9]+):(.+?):(\d+)\s*$',
    caseSensitive: false,
  );

  // в access-строку SNI не попадает: инбаунд пишет назначение раньше сниффера
  static final _sessionSniffed = RegExp(
    r'sniffed domain:\s*(\S+)',
    caseSensitive: false,
  );

  static final _sessionEnded = RegExp(
    r'connection ends',
    caseSensitive: false,
  );

  // всё, что читает parse: новый образец разбора добавлять и сюда
  static bool isConnectionLine(String line) =>
      line.contains(' accepted ') ||
      line.contains(' rejected ') ||
      line.contains('taking detour') ||
      line.contains('default route for') ||
      _sessionMarkers.any(line.contains);

  static const _sessionMarkers = [
    'processing from',
    'sniffed domain',
    'connection ends',
    'client UDP connection from',
    'TCP Connect request to',
    'establishing new connection for',
  ];

  static Map<String, XrayRouteDecision> parseRouteDecisions(String log) {
    final byTarget = <String, XrayRouteDecision>{};
    for (final line in log.split('\n')) {
      final detour = _detour.firstMatch(line);
      if (detour != null) {
        final target =
            _targetKey(detour.group(3), detour.group(4), detour.group(5));
        byTarget[target] = XrayRouteDecision(
          rule: detour.group(1)?.trim() ?? '',
          outbound: detour.group(2)?.trim() ?? '',
        );
        continue;
      }
      final fallback = _defaultRoute.firstMatch(line);
      if (fallback != null) {
        final target = _targetKey(
          fallback.group(1),
          fallback.group(2),
          fallback.group(3),
        );
        byTarget[target] = XrayRouteDecision(
          rule: _defaultRouteMarker,
          outbound: byTarget[target]?.outbound ?? '',
        );
      }
    }
    return byTarget;
  }

  static Map<String, XraySessionTrace> parseSessions(String log) {
    final sessions = <String, XraySessionTrace>{};
    for (final raw in log.split('\n')) {
      final match = _sessionLine.firstMatch(raw.trimRight());
      if (match == null) continue;
      final trace = sessions.putIfAbsent(
        match.group(1)!,
        XraySessionTrace.new,
      );
      final rest = match.group(2)!;

      if (_sessionEnded.hasMatch(rest)) {
        trace.closed = true;
        continue;
      }
      final sniffed = _sessionSniffed.firstMatch(rest);
      if (sniffed != null) {
        trace.domain = sniffed.group(1)!.trim();
        continue;
      }
      final tun = _sessionTun.firstMatch(rest);
      if (tun != null) {
        trace.clientKey = tun.group(1)!.trim().toLowerCase();
        trace.destKey = _targetKey(tun.group(2), tun.group(3), tun.group(4));
        continue;
      }
      final client = _sessionClient.firstMatch(rest);
      if (client != null) {
        trace.clientKey = client.group(1)!.trim().toLowerCase();
        continue;
      }
      final dest = _sessionDest.firstMatch(rest);
      if (dest != null) {
        trace.destKey =
            _targetKey(dest.group(1), dest.group(2), dest.group(3));
        continue;
      }
      final detour = _detour.firstMatch(rest);
      if (detour != null) {
        trace.rule = detour.group(1)?.trim() ?? '';
        trace.outbound = detour.group(2)?.trim() ?? '';
        continue;
      }
      if (_defaultRoute.hasMatch(rest)) trace.rule = _defaultRouteMarker;
    }
    return sessions;
  }

  static ConnectionsSnapshot parse(String log) {
    final decisions = parseRouteDecisions(log);
    final sawRoutingLines = decisions.isNotEmpty;
    final rulesByTarget = {
      for (final e in decisions.entries)
        if (e.value.rule.isNotEmpty) e.key: e.value.rule,
    };
    final outboundByTarget = {
      for (final e in decisions.entries)
        if (e.value.outbound.isNotEmpty) e.key: e.value.outbound,
    };

    // k-я access-строка получает k-ю сессию: при выигрыше последней закрытие одного соединения вешалось на все
    final sessions = parseSessions(log);
    final byClient = <String, XraySessionTrace>{};
    final byDest = <String, List<XraySessionTrace>>{};
    for (final trace in sessions.values) {
      if (trace.clientKey.isNotEmpty) byClient[trace.clientKey] = trace;
      if (trace.destKey.isNotEmpty) {
        byDest.putIfAbsent(trace.destKey, () => []).add(trace);
      }
    }
    final destCursor = <String, int>{};

    final lines = log.split('\n');

    final entries = <String, ConnectionEntry>{};
    for (final line in lines) {
      final access = _accessLine(line);
      if (access == null) continue;
      final (:source, :rejected, :network, :host, :port, :detourField) =
          access;
      if (host.isEmpty) continue;

      final (inbound, outbound) = _splitDetour(detourField);
      final target = _targetKey(network, host, '$port');
      final trace = byClient[source.toLowerCase()] ??
          _nextTraceForDest(byDest[target], target, destCursor);

      final domain = trace?.domain ?? '';
      final id = '$source>$network:$host:$port';
      entries[id] = ConnectionEntry(
        id: id,
        network: network,
        host: domain.isNotEmpty ? domain : host,
        destPort: port,
        destIp: domain.isNotEmpty ? host : '',
        source: _plainAddress(source),
        process: _process.firstMatch(line)?.group(1)?.trim() ?? '',
        inbound: inbound,
        outbound: outbound.isNotEmpty
            ? outbound
            : (trace?.outbound.isNotEmpty ?? false)
                ? trace!.outbound
                : (outboundByTarget[target] ?? ''),
        rule: (trace?.rule.isNotEmpty ?? false)
            ? trace!.rule
            : (rulesByTarget[target] ?? ''),
        startedAt: _parseTimestamp(line),
        rejected: rejected,
        closed: trace?.closed ?? false,
      );
    }

    final seen = entries.values.toList().reversed;
    final list = [
      ...seen.where((e) => !e.closed),
      ...seen.where((e) => e.closed),
    ];
    return ConnectionsSnapshot(
      entries: list,
      source: ConnectionsSource.coreLog,
      ruleInfoAvailable: sawRoutingLines,
    );
  }

  static ({
    String source,
    bool rejected,
    String network,
    String host,
    int port,
    String detourField,
  })? _accessLine(String line) {
    final url = _accessUrl.firstMatch(line);
    if (url != null) {
      final authority = url.group(4)!;
      final hostPort = authority.substring(authority.lastIndexOf('@') + 1);
      final colon = hostPort.lastIndexOf(':');
      final hasPort = colon > hostPort.lastIndexOf(']');
      final defaultPort = url.group(3)?.toLowerCase() == 'https' ? 443 : 80;
      return (
        source: url.group(1)!.trim(),
        rejected: url.group(2)!.toLowerCase() == 'rejected',
        network: 'tcp',
        host: hasPort ? hostPort.substring(0, colon) : hostPort,
        port: hasPort
            ? int.tryParse(hostPort.substring(colon + 1)) ?? 0
            : defaultPort,
        detourField: url.group(5)?.trim() ?? '',
      );
    }
    final m = _access.firstMatch(line);
    if (m == null) return null;
    return (
      source: m.group(1)!.trim(),
      rejected: m.group(2)!.toLowerCase() == 'rejected',
      network: m.group(3)!.toLowerCase(),
      host: m.group(4)!.trim(),
      port: int.tryParse(m.group(5)!) ?? 0,
      detourField: m.group(6)?.trim() ?? '',
    );
  }

  static XraySessionTrace? _nextTraceForDest(
    List<XraySessionTrace>? traces,
    String target,
    Map<String, int> cursor,
  ) {
    if (traces == null || traces.isEmpty) return null;
    final index = cursor.update(target, (v) => v + 1, ifAbsent: () => 0);
    return index < traces.length ? traces[index] : traces.last;
  }

  static const _defaultRouteMarker = '*';

  static String targetKeyFor(String network, String host, int port) =>
      _targetKey(network, host, '$port');

  static const _finalRuleTag = 'final';

  static bool isDefaultRoute(String rule) =>
      rule == _defaultRouteMarker || rule == _finalRuleTag;

  static String _targetKey(String? network, String? host, String? port) =>
      '${network?.toLowerCase()}:${host?.trim().toLowerCase()}:$port';

  // приставку сети xray дописывает сам, а система ищет владельца по голому адресу
  static String _plainAddress(String address) =>
      address.replaceFirst(RegExp(r'^(tcp|udp):', caseSensitive: false), '');

  static (String inbound, String outbound) _splitDetour(String raw) {
    if (raw.isEmpty) return ('', '');
    for (final sep in const [' ==> ', ' -> ', ' >> ']) {
      final idx = raw.indexOf(sep);
      if (idx >= 0) {
        return (
          raw.substring(0, idx).trim(),
          raw.substring(idx + sep.length).trim(),
        );
      }
    }
    return ('', raw.trim());
  }

  static DateTime? _parseTimestamp(String line) {
    final xray = _timestamp.firstMatch(line);
    // штамп xray в UTC, префикс от forkexec.c в местном времени, год берём из штампа
    final device = _deviceTimestamp.firstMatch(line);
    try {
      if (device != null) {
        return DateTime(
          xray != null ? int.parse(xray.group(1)!) : DateTime.now().year,
          int.parse(device.group(1)!),
          int.parse(device.group(2)!),
          int.parse(device.group(3)!),
          int.parse(device.group(4)!),
          int.parse(device.group(5)!),
        );
      }
      if (xray == null) return null;
      return DateTime(
        int.parse(xray.group(1)!),
        int.parse(xray.group(2)!),
        int.parse(xray.group(3)!),
        int.parse(xray.group(4)!),
        int.parse(xray.group(5)!),
        int.parse(xray.group(6)!),
      );
    } catch (_) {
      return null;
    }
  }
}

class XraySessionTrace {
  String destKey = '';

  String clientKey = '';

  String domain = '';

  String rule = '';
  String outbound = '';

  bool closed = false;
}


class XrayRouteDecision {
  const XrayRouteDecision({required this.rule, required this.outbound});

  final String rule;

  final String outbound;
}
