/// Куда mihomo отправит соединение: первое совпавшее правило, как в
/// `tunnel.match`.
///
/// Логические правила и `SUB-RULE` разбираются тем же способом, что в ядре
/// (`rules/logic/logic.go`: скобки считаются стеком, берутся только верхние
/// диапазоны), поэтому сломанная вложенность ловится здесь, а не на машине
/// пользователя. Понимает типы, которые пишут наши генераторы; geo-правила
/// не совпадают никогда — тесты на них не опираются.
library;

import 'dart:io' show InternetAddress;

/// Соединение глазами ядра. [inType] — тип входа: `TUN`, `HTTP`, `SOCKS5`.
/// [path] пустой — процесс лежит в `C:\Apps\<process>`. [resolvesTo] — адрес,
/// который ядро получит, если правилу понадобится резолв домена.
class SimConn {
  const SimConn({
    this.process = '',
    String? path,
    this.host = '',
    this.ip = '',
    this.resolvesTo = '',
    this.inType = 'TUN',
    this.port = 443,
    this.network = 'TCP',
  }) : _path = path;

  final String process;
  final String? _path;
  final String host;
  final String ip;
  final String resolvesTo;
  final String inType;
  final int port;
  final String network;

  String get path => _path ?? (process.isEmpty ? '' : 'C:\\Apps\\$process');
}

/// Цель первого совпавшего правила. Нет совпадения и `MATCH` — `DIRECT`, как
/// у ядра.
String simulateMihomo(
  Map<String, dynamic> config,
  SimConn conn,
) {
  final rules = [for (final r in config['rules'] as List) '$r'];
  final subRules = <String, List<String>>{
    for (final MapEntry(:key, :value)
        in ((config['sub-rules'] as Map?) ?? const {}).entries)
      '$key': [for (final r in value as List) '$r'],
  };
  final providers = <String, List<String>>{
    for (final MapEntry(:key, :value)
        in ((config['rule-providers'] as Map?) ?? const {}).entries)
      if (value is Map && value['payload'] is List)
        '$key': [for (final d in value['payload'] as List) '$d'],
  };
  final sim = _Sim(conn, subRules, providers);
  for (final rule in rules) {
    final hit = sim.matchTop(rule);
    if (hit != null) return hit;
  }
  return 'DIRECT';
}

/// Цели всех правил, которых ядро не найдёт: та же проверка, что в
/// `config.parseRules` — у `SUB-RULE` цель — набор, у остальных — выход.
/// Пустой список — конфиг по этой части разберётся.
List<String> unknownMihomoTargets(Map<String, dynamic> config) {
  final outbounds = <String>{
    'DIRECT',
    'REJECT',
    'REJECT-DROP',
    'PASS',
    for (final p in (config['proxies'] as List?) ?? const []) '${p['name']}',
    for (final g in (config['proxy-groups'] as List?) ?? const [])
      '${g['name']}',
  };
  final sets = <String>{
    for (final k in ((config['sub-rules'] as Map?) ?? const {}).keys) '$k',
  };
  final providers = <String>{
    for (final k in ((config['rule-providers'] as Map?) ?? const {}).keys) '$k',
  };
  final problems = <String>[];
  void check(String raw) {
    final p = _parse(raw, needTarget: true);
    final known = outbounds.contains(p.target) ||
        (p.type == 'SUB-RULE' && sets.contains(p.target));
    if (!known) problems.add('$raw: нет цели ${p.target}');
    if (p.type == 'RULE-SET' && !providers.contains(p.payload)) {
      problems.add('$raw: нет набора ${p.payload}');
    }
  }

  for (final r in (config['rules'] as List?) ?? const []) {
    check('$r');
  }
  for (final list in ((config['sub-rules'] as Map?) ?? const {}).values) {
    for (final r in list as List) {
      check('$r');
    }
  }
  return problems;
}

/// Верхние подправила логического правила, как `Logic.parsePayload`.
List<String> mihomoLogicParts(String payload) {
  if (!payload.startsWith('(') || !payload.endsWith(')')) {
    throw FormatException('payload format error: $payload');
  }
  final stack = <int>[];
  final ranges = <(int, int)>[];
  for (var i = 0; i < payload.length; i++) {
    final c = payload[i];
    if (c == '(') {
      stack.add(i);
    } else if (c == ')') {
      if (stack.isEmpty) throw FormatException("missing '(': $payload");
      ranges.add((stack.removeLast(), i));
    }
  }
  if (stack.isNotEmpty) throw FormatException('missing ): $payload');
  ranges.sort((a, b) => a.$1.compareTo(b.$1));
  final picked = <(int, int)>[];
  for (final rr in ranges) {
    if (rr.$1 == 0 && rr.$2 == payload.length - 1) continue;
    if (picked.any((r) => r.$1 < rr.$1 && r.$2 > rr.$2)) continue;
    picked.add(rr);
  }
  return [for (final r in picked) payload.substring(r.$1 + 1, r.$2)];
}

class _Parsed {
  _Parsed(this.type, this.payload, this.target, this.params);
  final String type;
  final String payload;
  final String target;
  final List<String> params;
}

/// `ParseRulePayload` ядра: у логических правил и регулярок запятые остаются
/// в полезной нагрузке, цель — последний элемент.
_Parsed _parse(String raw, {required bool needTarget}) {
  var item = raw.split(',').map((s) => s.trim()).toList();
  final type = item.first.toUpperCase();
  var payload = '';
  var target = '';
  var params = <String>[];
  if (item.length > 1) {
    switch (type) {
      case 'MATCH':
        target = item[1];
      case 'NOT' ||
            'OR' ||
            'AND' ||
            'SUB-RULE' ||
            'DOMAIN-REGEX' ||
            'PROCESS-NAME-REGEX' ||
            'PROCESS-PATH-REGEX':
        if (needTarget) {
          target = item.last;
          item = item.sublist(0, item.length - 1);
        }
        payload = item.sublist(1).join(',');
      default:
        payload = item[1];
        if (item.length > 2) {
          if (needTarget) {
            target = item[2];
            params = item.sublist(3);
          } else {
            params = item.sublist(2);
          }
        }
    }
  }
  return _Parsed(type, payload, target, params);
}

class _Sim {
  _Sim(this.conn, this.subRules, this.providers) : dstIp = conn.ip;

  final SimConn conn;
  final Map<String, List<String>> subRules;
  final Map<String, List<String>> providers;

  /// Адрес назначения; правило с резолвом заполняет его, и дальше его видят
  /// все следующие правила — как `metadata.DstIP` в ядре.
  String dstIp;

  String? matchTop(String raw) {
    final p = _parse(raw, needTarget: true);
    if (p.target.isEmpty) throw FormatException('format invalid: $raw');
    if (p.type == 'SUB-RULE') {
      if (!_subRuleCondition(p.payload)) return null;
      return _matchSubRules(p.target);
    }
    return _matches(p) ? p.target : null;
  }

  bool _subRuleCondition(String payload) {
    final parts = mihomoLogicParts('($payload)');
    if (parts.length != 1) {
      throw FormatException('Sub-Rule rule must contain one rule: $payload');
    }
    return _matchInner(parts.single);
  }

  String? _matchSubRules(String name) {
    final list = subRules[name];
    if (list == null) throw StateError('sub-rule [$name] not found');
    for (final raw in list) {
      final hit = matchTop(raw);
      if (hit != null) return hit;
    }
    return null;
  }

  bool _matchInner(String raw) {
    final p = _parse(raw, needTarget: false);
    if (p.type == 'MATCH' || p.type == 'SUB-RULE') {
      throw FormatException('unsupported rule type [${p.type}] on logic rule');
    }
    return _matches(p);
  }

  bool _matches(_Parsed p) {
    final host = conn.host.toLowerCase();
    bool resolveUnlessNoResolve() {
      if (!p.params.contains('no-resolve') &&
          dstIp.isEmpty &&
          conn.resolvesTo.isNotEmpty) {
        dstIp = conn.resolvesTo;
      }
      return dstIp.isNotEmpty;
    }

    return switch (p.type) {
      'MATCH' => true,
      'AND' => mihomoLogicParts(p.payload).every(_matchInner),
      'OR' => mihomoLogicParts(p.payload).any(_matchInner),
      'NOT' => () {
          final parts = mihomoLogicParts(p.payload);
          if (parts.length != 1) throw FormatException('not: ${p.payload}');
          return !_matchInner(parts.single);
        }(),
      'IN-TYPE' => p.payload
          .split('/')
          .map((t) => t.trim().toUpperCase())
          .any((t) =>
              t == conn.inType ||
              (t == 'SOCKS' && conn.inType.startsWith('SOCKS'))),
      'NETWORK' => p.payload.toUpperCase() == conn.network.toUpperCase(),
      'DST-PORT' => p.payload.split('/').any((part) {
          final range = part.trim().split('-');
          return conn.port >= int.parse(range.first) &&
              conn.port <= int.parse(range.last);
        }),
      'PROCESS-NAME' => conn.process.toLowerCase() == p.payload.toLowerCase(),
      'PROCESS-NAME-REGEX' =>
        RegExp(p.payload, caseSensitive: false).hasMatch(conn.process),
      'PROCESS-PATH-REGEX' =>
        RegExp(p.payload, caseSensitive: false).hasMatch(conn.path),
      'DOMAIN' => host.isNotEmpty && host == p.payload.toLowerCase(),
      'DOMAIN-SUFFIX' => host.isNotEmpty &&
          (host == p.payload.toLowerCase() ||
              host.endsWith('.${p.payload.toLowerCase()}')),
      'DOMAIN-KEYWORD' =>
        host.isNotEmpty && host.contains(p.payload.toLowerCase()),
      'RULE-SET' => host.isNotEmpty &&
          (providers[p.payload] ?? const []).any((entry) {
            final suffix = entry.startsWith('+.') ? entry.substring(2) : entry;
            return host == suffix || host.endsWith('.$suffix');
          }),
      'IP-CIDR' || 'IP-CIDR6' =>
        resolveUnlessNoResolve() && _inCidr(dstIp, p.payload),
      'GEOIP' || 'GEOSITE' => false,
      _ => throw UnsupportedError('симулятор не знает правила ${p.type}'),
    };
  }
}

bool _inCidr(String ip, String cidr) {
  final slash = cidr.indexOf('/');
  final net = InternetAddress.tryParse(cidr.substring(0, slash));
  final addr = InternetAddress.tryParse(ip);
  if (net == null || addr == null || net.type != addr.type) return false;
  final bits = int.parse(cidr.substring(slash + 1));
  final a = addr.rawAddress;
  final n = net.rawAddress;
  for (var i = 0; i < bits; i++) {
    final mask = 0x80 >> (i % 8);
    if ((a[i ~/ 8] & mask) != (n[i ~/ 8] & mask)) return false;
  }
  return true;
}
