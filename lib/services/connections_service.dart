import 'dart:convert';
import 'dart:io';

import '../models/connection_entry.dart';
import '../tunnel/linux_tunnel_backend.dart';
import '../tunnel/windows_tunnel_backend.dart';
import 'debug_log_service.dart';

/// Снимок активных соединений ядра для дебаг-экрана.
///
/// Источник зависит от платформы, потому что ядра разные:
///  - desktop (keqrnel = sing-box + встроенный xray): clash_api ядра отдаёт
///    список соединений с процессом, доменом, правилом и счётчиками;
///  - Android (чистый libxray): API соединений у xray нет вовсе, поэтому
///    разбираем его access-лог — тот же файл, что показывает экран логов.
class ConnectionsService {
  ConnectionsService._();

  /// Сколько строк лога тянем на Android. 1200 строк ≈ несколько сотен
  /// соединений: больше незачем, файл кольцуется на 512 КБ.
  static const _androidLogLines = 1200;

  static Future<ConnectionsSnapshot> snapshot() async {
    if (Platform.isWindows || Platform.isLinux) {
      final api = await _fromClashApi();
      if (api.source == ConnectionsSource.coreApi) return api;
      // clash_api нет: движок `chain` (xray + sing-box) его не поднимает, да и
      // сессия могла уже закончиться. Access-лог xray остаётся — по нему видно
      // то же самое, только без процессов и байт.
      final log = await _fromAccessLog();
      return log.entries.isEmpty ? api : log;
    }
    if (Platform.isAndroid) return _fromAccessLog();
    return const ConnectionsSnapshot(
      entries: [],
      source: ConnectionsSource.unavailable,
      note: 'Connections view is not supported on this platform.',
    );
  }

  /// true — источник в принципе умеет отдавать процесс (clash_api ядра на
  /// десктопе). На Android xray не знает приложение-владельца сокета, и колонку
  /// процесса показывать нечем.
  static bool get supportsProcessNames => Platform.isWindows || Platform.isLinux;

  // ── desktop: clash_api ────────────────────────────────────────────────────

  static int? _activeClashPort() {
    if (Platform.isWindows) return WindowsTunnelBackend.activeInstance?.clashApiPort;
    if (Platform.isLinux) return LinuxTunnelBackend.activeInstance?.clashApiPort;
    return null;
  }

  static Future<ConnectionsSnapshot> _fromClashApi() async {
    final port = _activeClashPort();
    if (port == null) {
      return const ConnectionsSnapshot(
        entries: [],
        source: ConnectionsSource.unavailable,
        note: 'No active core session.',
      );
    }

    try {
      final req = await _http
          .get('127.0.0.1', port, '/connections')
          .timeout(const Duration(seconds: 3));
      final resp = await req.close().timeout(const Duration(seconds: 3));
      if (resp.statusCode != 200) {
        await resp.drain<void>();
        return ConnectionsSnapshot(
          entries: const [],
          source: ConnectionsSource.unavailable,
          note: 'Core API answered HTTP ${resp.statusCode}.',
        );
      }
      final body = await resp.transform(utf8.decoder).join();
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic>) {
        return const ConnectionsSnapshot(
          entries: [],
          source: ConnectionsSource.unavailable,
          note: 'Unexpected core API payload.',
        );
      }
      final raw = json['connections'];
      final entries = <ConnectionEntry>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is! Map) continue;
          final entry = _entryFromClashJson(item.cast<String, dynamic>());
          if (entry != null) entries.add(entry);
        }
      }
      // Свежие сверху: так видно то, что происходит прямо сейчас.
      entries.sort((a, b) {
        final at = a.startedAt, bt = b.startedAt;
        if (at == null || bt == null) return 0;
        return bt.compareTo(at);
      });
      return ConnectionsSnapshot(
        entries: entries,
        source: ConnectionsSource.coreApi,
      );
    } catch (e) {
      _resetHttp();
      return ConnectionsSnapshot(
        entries: const [],
        source: ConnectionsSource.unavailable,
        note: 'Core API unreachable: $e',
      );
    }
  }

  // Один keep-alive клиент на все опросы: экран обновляется каждые 2 секунды, и
  // новый HttpClient на каждый снимок — это сокет + закрытие на каждый тик.
  static HttpClient? _httpClient;

  static HttpClient get _http => _httpClient ??= HttpClient()
    ..connectionTimeout = const Duration(seconds: 2)
    ..idleTimeout = const Duration(seconds: 15);

  /// Порт clash_api живёт одну сессию ядра — на ошибке клиента не переиспользуем.
  static void _resetHttp() {
    _httpClient?.close(force: true);
    _httpClient = null;
  }

  static ConnectionEntry? _entryFromClashJson(Map<String, dynamic> json) {
    final meta = json['metadata'];
    if (meta is! Map) return null;
    final m = meta.cast<String, dynamic>();

    String str(String key) => m[key]?.toString().trim() ?? '';
    final destIp = str('destinationIP');
    final host = str('host').isNotEmpty ? str('host') : destIp;
    if (host.isEmpty) return null;

    final chains = (json['chains'] is List)
        ? (json['chains'] as List).map((e) => e.toString()).toList()
        : const <String>[];

    // clash отдаёт `rule` как "<описание правила> => <действие>" или "final".
    final rule = json['rule']?.toString().trim() ?? '';

    final id = json['id']?.toString() ??
        '${str('sourceIP')}:${str('sourcePort')}>$host:${str('destinationPort')}';

    return ConnectionEntry(
      id: id,
      network: str('network').isEmpty ? 'tcp' : str('network'),
      host: host,
      destPort: int.tryParse(str('destinationPort')) ?? 0,
      destIp: destIp == host ? '' : destIp,
      source: str('sourceIP').isEmpty
          ? ''
          : '${str('sourceIP')}:${str('sourcePort')}',
      process: str('processPath'),
      inbound: str('type'),
      // chains приходит от внешнего аутбаунда к внутреннему; для «куда ушло»
      // нужен первый — им и помечаем прокси/директ/блок.
      outbound: chains.isEmpty ? '' : chains.first,
      rule: rule == 'final' ? '' : rule,
      startedAt: DateTime.tryParse(json['start']?.toString() ?? '')?.toLocal(),
      upload: (json['upload'] as num?)?.toInt(),
      download: (json['download'] as num?)?.toInt(),
    );
  }

  // ── Android: access-лог xray ──────────────────────────────────────────────

  static Future<ConnectionsSnapshot> _fromAccessLog() async {
    final text = await DebugLogService.getXrayLogs(maxLines: _androidLogLines);
    if (text.trim().isEmpty) {
      return const ConnectionsSnapshot(
        entries: [],
        source: ConnectionsSource.unavailable,
        note: 'Core log is empty. Connect first.',
      );
    }
    return XrayAccessLogParser.parse(text);
  }
}

/// Разбор лога xray в список соединений.
///
/// Интересны две строки, которые ядро пишет на каждое соединение:
///
///   from 127.0.0.1:53182 accepted tcp:www.google.com:443 [socks-in -> proxy]
///   [Info] app/dispatcher: Hit route rule: [proxy-geosite] so taking detour
///           [proxy] for [tcp:www.google.com:443]
///
/// Первая (access-лог) идёт всегда, вторая — только при уровне логов Info, и
/// именно она несёт `ruleTag`. Связываем их по назначению: access-строка даёт
/// источник и инбаунд, строка роутинга — правило.
class XrayAccessLogParser {
  XrayAccessLogParser._();

  /// `from <src> accepted tcp:host:443 [in -> out]`.
  ///
  /// Detour-разделитель у xray разный по смыслу: `->` правило сработало,
  /// `>>` роутер не выбрал (дефолтный аутбаунд), `==>` тег навязан платформой.
  static final _access = RegExp(
    r'from\s+(\S+)\s+(accepted|rejected)\s+([a-z0-9]+):(.+?):(\d+)'
    r'(?:\s+\[([^\]]*)\])?',
    caseSensitive: false,
  );

  /// `Hit route rule: [tag] so taking detour [out] for [tcp:host:443]`
  /// либо `taking detour [out] for [tcp:host:443]` без тега правила.
  static final _detour = RegExp(
    r'(?:Hit route rule:\s*\[([^\]]*)\]\s*so\s*)?taking detour\s*'
    r'\[([^\]]*)\]\s*for\s*\[([a-z0-9]+):(.+?):(\d+)\]',
    caseSensitive: false,
  );

  /// `default route for tcp:host:443` — ни одно правило не совпало.
  static final _defaultRoute = RegExp(
    r'default route for\s+([a-z0-9]+):(.+?):(\d+)',
    caseSensitive: false,
  );

  /// Штамп времени xray: `2026/08/05 12:34:56.789012`.
  static final _timestamp = RegExp(
    r'(\d{4})/(\d{2})/(\d{2})\s+(\d{2}):(\d{2}):(\d{2})',
  );

  static ConnectionsSnapshot parse(String log) {
    // Правило по назначению: последняя запись выигрывает, соединений к одному
    // хосту много, а правило для них одно и то же.
    final rulesByTarget = <String, String>{};
    final outboundByTarget = <String, String>{};
    var sawRoutingLines = false;

    final lines = log.split('\n');
    for (final line in lines) {
      final detour = _detour.firstMatch(line);
      if (detour != null) {
        sawRoutingLines = true;
        final target = _targetKey(detour.group(3), detour.group(4), detour.group(5));
        final tag = detour.group(1)?.trim() ?? '';
        if (tag.isNotEmpty) rulesByTarget[target] = tag;
        final out = detour.group(2)?.trim() ?? '';
        if (out.isNotEmpty) outboundByTarget[target] = out;
        continue;
      }
      final fallback = _defaultRoute.firstMatch(line);
      if (fallback != null) {
        sawRoutingLines = true;
        rulesByTarget[_targetKey(
          fallback.group(1),
          fallback.group(2),
          fallback.group(3),
        )] = _defaultRouteMarker;
      }
    }

    // Соединения: по одному на пару источник→назначение, новые сверху.
    final entries = <String, ConnectionEntry>{};
    for (final line in lines) {
      final m = _access.firstMatch(line);
      if (m == null) continue;

      final source = m.group(1)!.trim();
      final rejected = m.group(2)!.toLowerCase() == 'rejected';
      final network = m.group(3)!.toLowerCase();
      final host = m.group(4)!.trim();
      final port = int.tryParse(m.group(5)!) ?? 0;
      if (host.isEmpty) continue;

      final detourField = m.group(6)?.trim() ?? '';
      final (inbound, outbound) = _splitDetour(detourField);
      final target = _targetKey(network, host, '$port');

      final id = '$source>$network:$host:$port';
      entries[id] = ConnectionEntry(
        id: id,
        network: network,
        host: host,
        destPort: port,
        source: source,
        inbound: inbound,
        outbound: outbound.isNotEmpty
            ? outbound
            : (outboundByTarget[target] ?? ''),
        rule: rulesByTarget[target] ?? '',
        startedAt: _parseTimestamp(line),
        rejected: rejected,
      );
    }

    final list = entries.values.toList().reversed.toList();
    return ConnectionsSnapshot(
      entries: list,
      source: ConnectionsSource.coreLog,
      // Строк роутинга нет — значит уровень логов ниже Info, и правило ядро
      // просто не печатает. Экран должен предложить это исправить, а не молчать.
      ruleInfoAvailable: sawRoutingLines,
    );
  }

  /// Маркер «правило не совпало, сработало финальное действие».
  static const _defaultRouteMarker = '*';

  /// true — правило в записи означает «сработал catch-all».
  static bool isDefaultRoute(String rule) => rule == _defaultRouteMarker;

  static String _targetKey(String? network, String? host, String? port) =>
      '${network?.toLowerCase()}:${host?.trim().toLowerCase()}:$port';

  /// `socks-in -> proxy` / `socks-in >> proxy` / `proxy` (без инбаунда).
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
    final m = _timestamp.firstMatch(line);
    if (m == null) return null;
    try {
      return DateTime(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
        int.parse(m.group(4)!),
        int.parse(m.group(5)!),
        int.parse(m.group(6)!),
      );
    } catch (_) {
      return null;
    }
  }
}
