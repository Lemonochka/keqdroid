import 'dart:convert';
import 'dart:io';

import '../models/connection_entry.dart';
import '../platform/vpn_native_bridge.dart';
import '../tunnel/linux_tunnel_backend.dart';
import '../tunnel/windows_tunnel_backend.dart';
import 'connections_tracker.dart';
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

  /// Память между опросами: держит живые соединения и сводит одинаковые.
  static final ConnectionsTracker _tracker = ConnectionsTracker();

  /// Другая сессия ядра — накопленное больше не про неё. Дёргает экран, когда
  /// меняется состояние туннеля.
  static void resetTracker() {
    _tracker.reset();
    _appNames.clear();
    _decisions.clear();
    _decisionsPort = null;
  }

  static Future<ConnectionsSnapshot> snapshot() async {
    final raw = await _rawSnapshot();
    return _tracker.merge(raw, sessionToken: _sessionToken(raw));
  }

  /// Что источник отдал прямо сейчас — до свёртки и без памяти о предыдущих
  /// опросах.
  static Future<ConnectionsSnapshot> _rawSnapshot() async {
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

  /// Метка сессии для трекера: смена источника или порта clash_api означает
  /// другое ядро. На Android постоянна — там сессию сбрасывает экран по
  /// состоянию туннеля ([resetTracker]).
  static String _sessionToken(ConnectionsSnapshot snapshot) =>
      '${snapshot.source.name}:${_activeClashPort() ?? ''}';

  /// true — источник в принципе умеет отдавать владельца соединения: на
  /// десктопе это процесс из clash_api, на Android — приложение, найденное по
  /// сокету через систему. Имя всё равно бывает пустым (на Android нужен
  /// дебаг-режим и живое соединение), и тогда плитка просто его не рисует.
  static bool get supportsProcessNames =>
      Platform.isWindows || Platform.isLinux || Platform.isAndroid;

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

      final resolved = await _resolveEngineVerdicts(entries, port);
      return ConnectionsSnapshot(
        entries: resolved,
        source: ConnectionsSource.coreApi,
        // Хотя бы одно соединение осталось без настоящего вердикта — значит
        // ядро не печатает решения (уровень логов ниже Info).
        ruleInfoAvailable: !resolved.any((e) => e.decidedByCore),
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

  /// Тег аутбаунда, за которым в конфиге keqrnel стоит встроенный xray.
  /// Соединение с этим аутбаундом sing-box не маршрутизировал — он передал его
  /// движку, и настоящее решение принимает уже тот.
  static const _engineOutboundTag = 'proxy';

  /// Накопленные решения ядра: буфер лога держит только хвост (64 КиБ), а
  /// соединение может жить дольше, чем его строка в логе. Ключ — назначение.
  static final Map<String, XrayRouteDecision> _decisions = {};
  static int? _decisionsPort;
  static const _decisionsLimit = 500;

  /// Достаёт из лога ядра, куда оно на самом деле отправило соединение.
  ///
  /// clash_api видит только слой sing-box, а он в proxy-режиме отдаёт движку
  /// вообще всё (`route.final: proxy`) — без этого экран рисовал PROXY даже там,
  /// где правило Direct уводило трафик мимо туннеля.
  static Future<List<ConnectionEntry>> _resolveEngineVerdicts(
    List<ConnectionEntry> entries,
    int port,
  ) async {
    final viaEngine = entries
        .where((e) => e.outbound.toLowerCase() == _engineOutboundTag)
        .toList();
    if (viaEngine.isEmpty) return entries;

    // Смена сессии = другой набор соединений, старые решения не про них.
    if (_decisionsPort != port) {
      _decisions.clear();
      _decisionsPort = port;
    }

    try {
      final log = await DebugLogService.getXrayLogs(maxLines: 400);
      final fresh = XrayAccessLogParser.parseRouteDecisions(log);
      if (fresh.isNotEmpty) {
        _decisions.addAll(fresh);
        while (_decisions.length > _decisionsLimit) {
          _decisions.remove(_decisions.keys.first);
        }
      }
    } catch (_) {
      // Лог недоступен — покажем «решает ядро», это честнее выдумки.
    }

    return [
      for (final entry in entries)
        if (entry.outbound.toLowerCase() != _engineOutboundTag)
          entry
        else
          _applyDecision(entry),
    ];
  }

  static ConnectionEntry _applyDecision(ConnectionEntry entry) {
    final decision = _decisions[XrayAccessLogParser.targetKeyFor(
      entry.network,
      entry.host,
      entry.destPort,
    )];
    if (decision == null || decision.outbound.isEmpty) {
      return entry.withRouting(
        rule: '',
        outbound: entry.outbound,
        decidedByCore: true,
      );
    }
    return entry.withRouting(
      rule: decision.rule,
      outbound: decision.outbound,
      decidedByCore: false,
    );
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
    final snapshot = XrayAccessLogParser.parse(text);
    if (!Platform.isAndroid) return snapshot;
    return withAppNames(
      snapshot,
      peers: Tun2SocksLogParser.parse(await VpnNativeBridge.getTun2SocksLogs()),
      resolve: VpnNativeBridge.resolveConnectionOwners,
      cache: _appNames,
    );
  }

  /// Копия снимка с пометкой, что владельцев определить нечем.
  static ConnectionsSnapshot _withoutAppNames(ConnectionsSnapshot s) =>
      ConnectionsSnapshot(
        entries: s.entries,
        source: s.source,
        note: s.note,
        ruleInfoAvailable: s.ruleInfoAvailable,
        appNamesAvailable: false,
      );

  /// Дополняет соединения именами приложений-владельцев.
  ///
  /// Связка двухступенчатая: лог tun2socks даёт по назначению сокет
  /// приложения, а система по паре сокетов — uid и имя. Закрытые соединения не
  /// спрашиваем вовсе: система ищет их в живой таблице сокетов и на закрытые
  /// отвечает «владельца нет».
  /// Найденные имена, чтобы не спрашивать систему об одном и том же каждые две
  /// секунды: экран опрашивается по таймеру, а соединение живёт дольше.
  static final Map<String, String> _appNames = {};
  static const _appNamesLimit = 300;

  static Future<ConnectionsSnapshot> withAppNames(
    ConnectionsSnapshot snapshot, {
    required Map<String, Tun2SocksPeer> peers,
    required Future<List<String>> Function(List<Map<String, Object?>>) resolve,
    Map<String, String>? cache,
  }) async {
    if (peers.isEmpty) {
      // Лога tun2socks нет вовсе — туннель поднимали без дебаг-режима.
      return snapshot.entries.isEmpty
          ? snapshot
          : _withoutAppNames(snapshot);
    }

    final entries = [...snapshot.entries];
    final indexes = <int>[];
    final requests = <Map<String, Object?>>[];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final known = cache?[entry.id];
      if (known != null && known.isNotEmpty) {
        entries[i] = entry.withProcess(known);
        continue;
      }
      if (entry.closed) continue;
      // Спрашиваем по IP: host к этому моменту мог смениться на домен.
      final ip = entry.destIp.isNotEmpty ? entry.destIp : entry.host;
      final peer = peers[Tun2SocksLogParser.keyFor(
        entry.network,
        ip,
        entry.destPort,
      )];
      if (peer == null) continue;
      indexes.add(i);
      requests.add({
        'protocol': entry.network,
        'srcIp': peer.ip,
        'srcPort': peer.port,
        'dstIp': ip,
        'dstPort': entry.destPort,
      });
    }
    final names = requests.isEmpty
        ? const <String>[]
        : await resolve(requests);
    for (var i = 0; i < indexes.length && i < names.length; i++) {
      final name = names[i];
      if (name.isEmpty) continue;
      final index = indexes[i];
      entries[index] = entries[index].withProcess(name);
      if (cache != null) {
        cache[entries[index].id] = name;
        while (cache.length > _appNamesLimit) {
          cache.remove(cache.keys.first);
        }
      }
    }
    return ConnectionsSnapshot(
      entries: entries,
      source: snapshot.source,
      note: snapshot.note,
      ruleInfoAvailable: snapshot.ruleInfoAvailable,
      appNamesAvailable: snapshot.appNamesAvailable,
    );
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

  /// Штамп времени xray: `2026/08/05 12:34:56.789012`. Идёт в UTC: Go на
  /// Android остаётся без базы часовых поясов.
  static final _timestamp = RegExp(
    r'(\d{4})/(\d{2})/(\d{2})\s+(\d{2}):(\d{2}):(\d{2})',
  );

  /// Префикс `08-09 22:43:40 `, который дописывает наш forkexec.c по
  /// `localtime_r` — местное время устройства. Года в нём нет, берём из
  /// штампа xray на той же строке.
  static final _deviceTimestamp = RegExp(
    r'^(\d{2})-(\d{2})\s+(\d{2}):(\d{2}):(\d{2})\s',
  );

  /// `[Info] [3159036192] proxy/socks: …` — идентификатор сессии. Именно он
  /// связывает строки одного соединения: у access-строки его нет, зато есть
  /// адрес клиента, а у остальных наоборот.
  static final _sessionLine = RegExp(r'\[Info\]\s*\[(\d+)\]\s*(.+)$');

  /// `proxy/socks: TCP Connect request to tcp:216.58.198.162:443` и
  /// `transport/internet/udp: establishing new connection for udp:8.8.8.8:53`
  /// — единственные строки, где сессия названа вместе с настоящим адресом
  /// назначения (до подмены доменом).
  static final _sessionDest = RegExp(
    r'(?:TCP Connect request to|establishing new connection for)\s+'
    r'([a-z0-9]+):(.+?):(\d+)\s*$',
    caseSensitive: false,
  );

  /// `proxy/socks: client UDP connection from udp:127.0.0.1:36948` — адрес
  /// клиента, тот же, что стоит в access-строке после `from`.
  static final _sessionClient = RegExp(
    r'client UDP connection from\s+(\S+)',
    caseSensitive: false,
  );

  /// `app/dispatcher: sniffed domain: googleads.g.doubleclick.net` — имя,
  /// вынюханное из SNI. В access-строку оно не попадает никогда: её назначение
  /// инбаунд записывает раньше, чем сниффер успевает прочитать поток.
  static final _sessionSniffed = RegExp(
    r'sniffed domain:\s*(\S+)',
    caseSensitive: false,
  );

  /// `app/proxyman/inbound: connection ends > …` — соединение закрылось.
  /// Хвост строки это причина закрытия, она не нужна; важен сам факт и
  /// идентификатор сессии перед ним.
  static final _sessionEnded = RegExp(
    r'connection ends',
    caseSensitive: false,
  );

  /// Решения роутинга по назначению: `network:host:port` → правило и аутбаунд.
  ///
  /// Ядро печатает их на каждое соединение (уровень логов Info) и в том числе
  /// когда работает как встроенный движок без своих инбаундов — тогда это
  /// вообще единственный источник настоящего вердикта: clash_api sing-box'а
  /// видит только «отдал движку».
  static Map<String, XrayRouteDecision> parseRouteDecisions(String log) {
    // Последняя запись выигрывает: соединений к одному хосту много, а правило
    // для них одно и то же.
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
        // Аутбаунд ядро в этой строке не называет — только «ни одно правило
        // не совпало»; тег аутбаунда, если он был известен, не затираем.
        byTarget[target] = XrayRouteDecision(
          rule: _defaultRouteMarker,
          outbound: byTarget[target]?.outbound ?? '',
        );
      }
    }
    return byTarget;
  }

  /// Строки одного соединения, собранные по идентификатору сессии.
  ///
  /// Ядро разносит сведения о соединении по нескольким строкам, и склеить их
  /// по адресу назначения нельзя: после сниффинга маршрутизация оперирует уже
  /// доменом, а access-строка так и осталась с IP.
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

    // Два способа найти сессию по access-строке. Адрес клиента точен (он у
    // каждого соединения свой), но ядро называет его только для UDP; для TCP
    // остаётся адрес назначения, а к одному IP:порту соединений бывает много.
    // Поэтому сессии одного назначения храним списком в порядке лога и
    // раздаём по одной: k-я access-строка получает k-ю сессию. «Выигрывает
    // последняя» вешало закрытие последнего соединения на все остальные — живое
    // соединение к тому же хосту выглядело закрытым.
    final sessions = parseSessions(log);
    final byClient = <String, XraySessionTrace>{};
    final byDest = <String, List<XraySessionTrace>>{};
    for (final trace in sessions.values) {
      if (trace.clientKey.isNotEmpty) byClient[trace.clientKey] = trace;
      if (trace.destKey.isNotEmpty) {
        byDest.putIfAbsent(trace.destKey, () => []).add(trace);
      }
    }
    // Сколько сессий этого назначения уже разобрано.
    final destCursor = <String, int>{};

    final lines = log.split('\n');

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
      final trace = byClient[source.toLowerCase()] ??
          _nextTraceForDest(byDest[target], target, destCursor);

      // Домен — в заголовок, IP уезжает строкой ниже: по одному IP гугла
      // ходит десяток разных сервисов, и понять по нему ничего нельзя.
      final domain = trace?.domain ?? '';
      final id = '$source>$network:$host:$port';
      entries[id] = ConnectionEntry(
        id: id,
        network: network,
        host: domain.isNotEmpty ? domain : host,
        destPort: port,
        destIp: domain.isNotEmpty ? host : '',
        source: source,
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

    // Живое наверх, закрытое вниз — внутри групп порядок прежний, свежие
    // первыми. Лог помнит и вчерашнее, и без этого оно перемешано с текущим.
    final seen = entries.values.toList().reversed;
    final list = [
      ...seen.where((e) => !e.closed),
      ...seen.where((e) => e.closed),
    ];
    return ConnectionsSnapshot(
      entries: list,
      source: ConnectionsSource.coreLog,
      // Строк роутинга нет — значит уровень логов ниже Info, и правило ядро
      // просто не печатает. Экран должен предложить это исправить, а не молчать.
      ruleInfoAvailable: sawRoutingLines,
    );
  }

  /// Очередная сессия этого назначения: соединений к одному адресу много, и
  /// каждой access-строке достаётся своя. Когда сессий меньше, чем строк
  /// (часть уехала из хвоста лога), остаток делит последнюю — правило и домен у
  /// них общие, а вот закрытие лучше не приписывать чужому соединению.
  static XraySessionTrace? _nextTraceForDest(
    List<XraySessionTrace>? traces,
    String target,
    Map<String, int> cursor,
  ) {
    if (traces == null || traces.isEmpty) return null;
    final index = cursor.update(target, (v) => v + 1, ifAbsent: () => 0);
    return index < traces.length ? traces[index] : traces.last;
  }

  /// Маркер «правило не совпало, сработало финальное действие».
  static const _defaultRouteMarker = '*';

  /// Ключ решения для одного назначения — как его строит [parseRouteDecisions].
  static String targetKeyFor(String network, String host, int port) =>
      _targetKey(network, host, '$port');

  /// Тег нашего catch-all правила в сгенерированном конфиге, см. config_gen.
  /// Ядро печатает его как обычное правило, но по смыслу это «не совпало
  /// ничего, сработало финальное действие».
  static const _finalRuleTag = 'final';

  /// true — правило в записи означает «сработал catch-all».
  static bool isDefaultRoute(String rule) =>
      rule == _defaultRouteMarker || rule == _finalRuleTag;

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
    final xray = _timestamp.firstMatch(line);
    // Штамп xray — UTC, и показывать его как есть значит врать на часовой
    // пояс. Префикс от forkexec.c уже в местном времени, берём его, а год —
    // из штампа рядом, в префиксе года нет.
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

/// Собранные по идентификатору сессии сведения об одном соединении.
class XraySessionTrace {
  /// `network:ip:port` назначения, как его увидел инбаунд — до подмены
  /// вынюханным доменом.
  String destKey = '';

  /// Адрес клиента (`udp:127.0.0.1:36948`) — им access-строка и сессия
  /// связываются точно, один к одному. Ядро называет его только для UDP.
  String clientKey = '';

  /// Домен из SNI/HTTP Host, если сниффер его достал.
  String domain = '';

  /// Тег сработавшего правила и выбранный аутбаунд.
  String rule = '';
  String outbound = '';

  /// Ядро сообщило о закрытии соединения.
  bool closed = false;
}

/// Адрес приложения на TUN — второй конец соединения, тот, что ищет система.
class Tun2SocksPeer {
  const Tun2SocksPeer({required this.ip, required this.port});
  final String ip;
  final int port;
}

/// Разбор лога tun2socks: `[TCP] 10.0.0.2:41234 <-> 216.58.198.162:443`.
///
/// Это единственное место, где виден исходный сокет приложения. В access-лог
/// xray попадает уже наш собственный сокет со стороны SOCKS (`127.0.0.1:…`),
/// принадлежащий tun2socks, — спрашивать систему про него бессмысленно, она
/// честно ответит, что владелец keqdroid.
class Tun2SocksLogParser {
  Tun2SocksLogParser._();

  /// Префикс строки и формат времени у tun2socks свои и от версии к версии
  /// меняются, поэтому цепляемся только за саму пару адресов.
  static final _line = RegExp(
    r'\[(TCP|UDP)\]\s+(\S+):(\d+)\s+<->\s+(\S+):(\d+)',
    caseSensitive: false,
  );

  static String keyFor(String network, String ip, int port) =>
      '${network.toLowerCase()}:${ip.trim().toLowerCase()}:$port';

  /// Назначение → адрес приложения. Последняя запись выигрывает: к одному
  /// адресу ходят по многу раз, и свежая связка вернее старой.
  static Map<String, Tun2SocksPeer> parse(String log) {
    final byTarget = <String, Tun2SocksPeer>{};
    for (final line in log.split('\n')) {
      final m = _line.firstMatch(line);
      if (m == null) continue;
      final port = int.tryParse(m.group(5)!);
      final srcPort = int.tryParse(m.group(3)!);
      if (port == null || srcPort == null) continue;
      byTarget[keyFor(m.group(1)!, m.group(4)!, port)] =
          Tun2SocksPeer(ip: m.group(2)!, port: srcPort);
    }
    return byTarget;
  }
}

/// Решение роутинга ядра для одного назначения.
class XrayRouteDecision {
  const XrayRouteDecision({required this.rule, required this.outbound});

  /// Тег правила (`ruleTag`), `*` — сработал catch-all, пусто — правило есть,
  /// но без тега.
  final String rule;

  /// Куда ядро отправило соединение: `proxy` / `direct` / `block`.
  final String outbound;
}
