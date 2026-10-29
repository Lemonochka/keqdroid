import 'dart:convert';

import 'package:yaml/yaml.dart';

// храним JSON: YAML 1.2 его надмножество, и mihomo разбирает тем же парсером. инбаунды автора не берём никогда
class CustomClashConfig {
  CustomClashConfig._(this.map);

  final Map<String, dynamic> map;

  static const _requiredKey = 'proxies';

  static const _remarkKeys = ['remarks', 'remark', 'name', 'profile-name'];

  // tun самый опасный: ядро полезет поднимать своё устройство поверх VpnService, и сессия умрёт
  static const _strippedKeys = {
    'tun',
    'port',
    'socks-port',
    'mixed-port',
    'redir-port',
    'tproxy-port',
    'bind-address',
    'authentication',
    'skip-auth-prefixes',
    'lan-allowed-ips',
    'lan-disallowed-ips',
    'listeners',
    'external-controller',
    'external-controller-tls',
    'external-controller-unix',
    'external-controller-pipe',
    'external-controller-cors',
    'external-ui',
    'external-ui-url',
    'external-ui-name',
    'secret',
    'tls',
    'interface-name',
    'routing-mark',
    // автообновление geo это поход в сеть до того, как поднялся туннель
    'geo-auto-update',
    'geo-update-interval',
    'geox-url',
  };

  static bool looksLikeClash(String raw) {
    final text = raw.trimLeft();
    if (text.isEmpty) return false;
    if (text.startsWith('{')) {
      // или proxy-providers: без этого профиль на провайдерах уезжал в неизвестный формат, то есть на xray
      return RegExp(r'"(proxies|proxy-providers)"\s*:').hasMatch(text);
    }
    return RegExp(r'^(proxies|proxy-groups|proxy-providers)\s*:', multiLine: true)
        .hasMatch(text);
  }

  static CustomClashConfig? tryParse(String raw) {
    final decoded = _decode(raw);
    if (decoded == null) return null;
    return _fromMap(decoded);
  }

  static CustomClashConfig? _fromMap(Map<String, dynamic> map) {
    if (proxiesOf(map).any((p) =>
        p['type'] != null &&
        (p['server']?.toString().trim().isNotEmpty ?? false))) {
      return CustomClashConfig._(map);
    }
    if (usesProviderNodes(map)) return CustomClashConfig._(map);
    return null;
  }

  // группы обязательны: без них primaryTarget вернёт DIRECT, и трафик молча пойдёт мимо туннеля
  static bool usesProviderNodes(Map<String, dynamic> map) {
    final providers = map['proxy-providers'];
    if (providers is! Map || providers.isEmpty) return false;
    final groups = map['proxy-groups'];
    return groups is List && groups.isNotEmpty;
  }

  bool get usesProviders => proxies.isEmpty && usesProviderNodes(map);

  static String? describeProblem(String raw) {
    final decoded = _decode(raw);
    if (decoded == null) {
      final reason = _decodeError(raw);
      return reason == null
          ? 'not a Clash config: expected a YAML or JSON object'
          : 'YAML could not be parsed ($reason)';
    }
    if (_fromMap(decoded) != null) return null;
    if (proxiesOf(decoded).isEmpty) {
      final providers = decoded['proxy-providers'];
      if (providers is Map && providers.isNotEmpty) {
        return 'nodes live in "proxy-providers" but the config has no '
            '"proxy-groups" to route through';
      }
      return 'no "proxies" and no "proxy-providers" — nothing to connect '
          'through';
    }
    return '"proxies" carry no type/server — this is not a proxy list';
  }

  static String? _decodeError(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return 'empty response';
    try {
      loadYaml(text);
      return null;
    } on Object catch (e) {
      final message = e.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      return message.length > 200 ? '${message.substring(0, 200)}…' : message;
    }
  }

  static List<String> extractConfigs(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return const [];
    final decoded = _decodeRaw(text);
    if (decoded is Map<String, dynamic>) {
      final config = _fromMap(decoded);
      return config == null ? const [] : [config.encode()];
    }
    if (decoded is List) {
      final out = <String>[];
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        final config = _fromMap(item);
        if (config != null) out.add(config.encode());
      }
      return out;
    }
    return const [];
  }

  static Map<String, dynamic>? _decode(String raw) {
    final decoded = _decodeRaw(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  static Object? _decodeRaw(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('{') || text.startsWith('[')) {
      try {
        return _plain(jsonDecode(text));
      } on Object {
        // не JSON, пробуем как YAML
      }
    }
    try {
      return _plain(loadYaml(text), yamlMerge: true);
    } on Object {
      return null;
    }
  }

  // слияние << из YAML 1.1: package:yaml его не знает, а go-yaml у mihomo раскрывает. без этого узлы на якорях теряли type
  static Object? _plain(Object? node, {bool yamlMerge = false}) {
    if (node is Map) {
      final out = <String, dynamic>{};
      for (final entry in node.entries) {
        final key = entry.key.toString();
        if (!yamlMerge || key != '<<') {
          out[key] = _plain(entry.value, yamlMerge: yamlMerge);
          continue;
        }
        final sources = entry.value;
        for (final source in sources is List ? sources : [sources]) {
          if (source is! Map) continue;
          final merged = _plain(source, yamlMerge: true) as Map<String, dynamic>;
          for (final m in merged.entries) {
            if (!node.containsKey(m.key) && !out.containsKey(m.key)) {
              out[m.key] = m.value;
            }
          }
        }
      }
      return out;
    }
    if (node is List) {
      return [for (final item in node) _plain(item, yamlMerge: yamlMerge)];
    }
    return node;
  }

  String encode() => const JsonEncoder.withIndent('  ').convert(map);

  static List<Map<String, dynamic>> proxiesOf(Map<String, dynamic> map) {
    final raw = map[_requiredKey];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map) item.cast<String, dynamic>(),
    ];
  }

  List<Map<String, dynamic>> get proxies => proxiesOf(map);

  String get remarks {
    for (final key in _remarkKeys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  // на группу, а не на узел: узлы переключают внутри неё, и правило должно ехать за выбором
  String get primaryTarget {
    final groups = map['proxy-groups'];
    if (groups is List) {
      for (final group in groups) {
        if (group is! Map) continue;
        final name = group['name']?.toString().trim() ?? '';
        if (name.isNotEmpty) return name;
      }
    }
    final first = proxies.isEmpty ? null : proxies.first;
    final name = first?['name']?.toString().trim() ?? '';
    return name.isEmpty ? 'DIRECT' : name;
  }

  static const _builtinTargets = {
    'DIRECT',
    'REJECT',
    'REJECT-DROP',
    'COMPATIBLE',
    'PASS',
    'PASS-RULE',
  };

  // exclude-filter ядро сверяет с именами и у явного списка (groupbase.go), а имена мы меняем
  static bool _coreFillsGroup(Map<String, dynamic> group) {
    bool set(Object? value) =>
        value != null &&
        value != false &&
        !(value is List && value.isEmpty) &&
        !const {'', '0', 'false'}.contains(value.toString().toLowerCase());
    return set(group['use']) ||
        set(group['include-all']) ||
        set(group['include-all-proxies']) ||
        set(group['include-all-providers']) ||
        set(group['exclude-filter']);
  }

  // в маршрут идут узлы и группы, до которых дотягивается primaryTarget, под именами tag, tag-1...
  // имена автора совпали бы с узлами сессии. null, если состав группы набирает ядро (use, include-all)
  ({List<Map<String, dynamic>> proxies, List<Map<String, dynamic>> groups})?
      routeNodes(String tag) {
    final proxyByName = <String, Map<String, dynamic>>{
      for (final proxy in proxies)
        if ((proxy['name']?.toString() ?? '').isNotEmpty)
          proxy['name'].toString(): proxy,
    };
    final rawGroups = map['proxy-groups'];
    final groupByName = <String, Map<String, dynamic>>{
      if (rawGroups is List)
        for (final group in rawGroups)
          if (group is Map && (group['name']?.toString() ?? '').isNotEmpty)
            group['name'].toString(): group.cast<String, dynamic>(),
    };

    final start = primaryTarget;
    if (!proxyByName.containsKey(start) && !groupByName.containsKey(start)) {
      return null;
    }
    final names = <String, String>{start: tag};
    final queue = [start];
    bool reach(Object? ref) {
      final name = ref?.toString() ?? '';
      if (name.isEmpty || _builtinTargets.contains(name)) return true;
      if (names.containsKey(name)) return true;
      if (!proxyByName.containsKey(name) && !groupByName.containsKey(name)) {
        return false;
      }
      names[name] = '$tag-${names.length}';
      queue.add(name);
      return true;
    }

    for (var i = 0; i < queue.length; i++) {
      final group = groupByName[queue[i]];
      if (group != null) {
        if (_coreFillsGroup(group)) return null;
        final members = group['proxies'];
        if (members is! List || members.isEmpty) return null;
        if (!members.every(reach)) return null;
        if (!reach(group['empty-fallback'])) return null;
      } else if (!reach(proxyByName[queue[i]]!['dialer-proxy'])) {
        return null;
      }
    }

    String rename(Object? ref) => names[ref?.toString()] ?? ref.toString();
    Map<String, dynamic> copy(Map<String, dynamic> node) =>
        (jsonDecode(jsonEncode(node)) as Map).cast<String, dynamic>();
    return (
      proxies: [
        for (final proxy in proxies)
          if (names.containsKey(proxy['name']?.toString()))
            {
              ...copy(proxy),
              'name': rename(proxy['name']),
              if (proxy['dialer-proxy'] != null)
                'dialer-proxy': rename(proxy['dialer-proxy']),
            },
      ],
      groups: [
        for (final MapEntry(key: name, value: group) in groupByName.entries)
          if (names.containsKey(name))
            {
              ...copy(group),
              'name': rename(name),
              'proxies': [for (final m in group['proxies'] as List) rename(m)],
              if (group['empty-fallback'] != null)
                'empty-fallback': rename(group['empty-fallback']),
            },
      ],
    );
  }

  ({String address, int port}) get endpoint {
    for (final proxy in proxies) {
      final address = proxy['server']?.toString().trim() ?? '';
      if (address.isEmpty) continue;
      final port = int.tryParse(proxy['port']?.toString() ?? '') ?? 0;
      return (address: address, port: port);
    }
    return (address: '', port: 0);
  }

  String get address => endpoint.address;
  int get port => endpoint.port;

  // наши списки перед авторским MATCH: после catch-all правило не сработает никогда
  Map<String, dynamic> buildSessionConfig({
    required Map<String, dynamic> inbound,
    required Map<String, dynamic> sniffer,
    required String logLevel,
    Map<String, dynamic>? dns,
    List<String> prependRules = const [],
    List<String> appendRules = const [],
    List<Map<String, dynamic>> extraProxies = const [],
    List<Map<String, dynamic>> extraGroups = const [],
    Map<String, dynamic> extra = const {},
  }) {
    final out = Map<String, dynamic>.from(map);
    for (final key in _remarkKeys) {
      out.remove(key);
    }
    for (final key in _strippedKeys) {
      out.remove(key);
    }

    out.addAll(inbound);
    out['log-level'] = logLevel;
    out['sniffer'] = sniffer;
    out['geodata-mode'] = true;
    out['geo-auto-update'] = false;
    out['find-process-mode'] = 'off';

    // DNS автора только включённый: с выключенным ядро идёт в системный резолвер, а на Android его нет
    final authorDns = out['dns'];
    final authorDnsEnabled =
        authorDns is Map && authorDns['enable'] == true &&
            (authorDns['nameserver'] as List?)?.isNotEmpty == true;
    if (!authorDnsEnabled && dns != null) out['dns'] = dns;

    out['rules'] = _mergeRules(
      authorRules: _rulesOf(out),
      prepend: prependRules,
      append: appendRules,
    );

    // после авторских: первым у автора должен остаться его узел
    if (extraProxies.isNotEmpty) {
      final authorProxies = out['proxies'];
      out['proxies'] = [
        if (authorProxies is List) ...authorProxies,
        ...extraProxies,
      ];
    }
    if (extraGroups.isNotEmpty) {
      final authorGroups = out['proxy-groups'];
      out['proxy-groups'] = [
        if (authorGroups is List) ...authorGroups,
        ...extraGroups,
      ];
    }

    out.addAll(extra);
    return out;
  }

  // то же, что у xray: его сайты в DIRECT и REJECT и его MATCH уходят, свой MATCH ставит генератор
  CustomClashConfig withoutProviderRules() {
    final raw = map['rules'];
    if (raw is! List) return this;
    return CustomClashConfig._({
      ...map,
      'rules': [
        for (final rule in raw)
          if (!_isProviderSiteRule(rule.toString())) rule,
      ],
    });
  }

  bool get hasProviderRules => _rulesOf(map).any(_isProviderSiteRule);

  static const _siteRuleTypes = {
    'DOMAIN',
    'DOMAIN-SUFFIX',
    'DOMAIN-KEYWORD',
    'DOMAIN-REGEX',
    'DOMAIN-WILDCARD',
    'GEOSITE',
    'GEOIP',
    'IP-CIDR',
    'IP-CIDR6',
    'IP-SUFFIX',
    'IP-ASN',
    'RULE-SET',
  };

  static const _localTargets = {'DIRECT', 'REJECT', 'REJECT-DROP'};

  static bool _isProviderSiteRule(String rule) {
    final parsed = _parseRule(rule);
    if (parsed == null) return false;
    if (parsed.type == 'MATCH') return true;
    if (!_localTargets.contains(parsed.target.toUpperCase())) return false;
    if (_siteRuleTypes.contains(parsed.type)) return true;
    if (const {'AND', 'OR', 'NOT'}.contains(parsed.type)) {
      final payload = parsed.payload.toUpperCase();
      return _siteRuleTypes.any((type) => payload.contains('($type,'));
    }
    return false;
  }

  // у AND, OR, NOT и SUB-RULE условие в скобках со своими запятыми, цель после закрывающей
  static ({String type, String payload, String target})? _parseRule(String rule) {
    final text = rule.trim();
    final comma = text.indexOf(',');
    if (comma < 0) return null;
    final type = text.substring(0, comma).trim().toUpperCase();
    var rest = text.substring(comma + 1).trimLeft();
    if (type == 'MATCH') {
      return (type: type, payload: '', target: rest.split(',').first.trim());
    }
    final String payload;
    if (rest.startsWith('(')) {
      var depth = 0;
      var end = -1;
      for (var i = 0; i < rest.length; i++) {
        if (rest[i] == '(') depth++;
        if (rest[i] == ')' && --depth == 0) {
          end = i;
          break;
        }
      }
      if (end < 0) return null;
      payload = rest.substring(0, end + 1);
      rest = rest.substring(end + 1).trimLeft();
      if (!rest.startsWith(',')) return null;
      rest = rest.substring(1);
    } else {
      final next = rest.indexOf(',');
      if (next < 0) return null;
      payload = rest.substring(0, next);
      rest = rest.substring(next + 1);
    }
    return (type: type, payload: payload, target: rest.split(',').first.trim());
  }

  static List<String> _rulesOf(Map<String, dynamic> map) {
    final raw = map['rules'];
    if (raw is! List) return const [];
    return [for (final rule in raw) rule.toString()];
  }

  // своего MATCH не добавляем: без авторского ядро само шлёт в DIRECT, это его решение
  static List<String> _mergeRules({
    required List<String> authorRules,
    required List<String> prepend,
    required List<String> append,
  }) {
    final matchIndex = authorRules.indexWhere(
      (rule) => rule.trimLeft().toUpperCase().startsWith('MATCH'),
    );
    if (matchIndex < 0) {
      return [...prepend, ...authorRules, ...append];
    }
    return [
      ...prepend,
      ...authorRules.take(matchIndex),
      ...append,
      ...authorRules.skip(matchIndex),
    ];
  }
}
