import 'dart:convert';

import 'deprecated_xray_fields.dart';
import 'geo_asset_index.dart';
import 'geo_rule_sanitizer.dart';
import 'removed_tls_fields.dart';

class CustomXrayConfig {
  CustomXrayConfig._(this.json);

  final Map<String, dynamic> json;

  static const _localOutboundProtocols = {
    'freedom',
    'blackhole',
    'dns',
    'loopback',
  };

  static const _requiredKey = 'outbounds';

  static const _remarkKeys = ['remarks', 'remark', 'ps', 'name', 'label'];

  static bool looksLikeJson(String raw) => raw.trimLeft().startsWith('{');

  static CustomXrayConfig? tryParse(String raw) {
    if (!looksLikeJson(raw)) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on Object {
      return null;
    }
    if (decoded is! Map) return null;
    final map = _asStringMap(decoded);
    return _fromMap(map);
  }

  static CustomXrayConfig? _fromMap(Map<String, dynamic> map) {
    final outbounds = _outboundsOf(map);
    if (outbounds.isEmpty) return null;
    // у sing-box аутбаунд по type, у xray по protocol, а protocol у SSR-узла sing-box значит обфускацию
    if (!outbounds.any(_isXrayOutbound)) return null;
    return CustomXrayConfig._(map);
  }

  static String? describeProblem(String raw) {
    if (!looksLikeJson(raw)) return 'Not a JSON object';
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on Object catch (e) {
      return 'Invalid JSON: $e';
    }
    if (decoded is! Map) return 'JSON config must be an object';
    final map = _asStringMap(decoded);
    final outbounds = _outboundsOf(map);
    if (outbounds.isEmpty) {
      return 'JSON config has no "outbounds" — this is not an Xray config';
    }
    if (!outbounds.any(_isXrayOutbound)) {
      return 'This looks like a sing-box config (outbounds use "type"). '
          'Only Xray JSON configs are supported.';
    }
    return null;
  }

  static bool _isXrayOutbound(Map<String, dynamic> outbound) =>
      outbound.containsKey('protocol') && !outbound.containsKey('type');

  static List<String> extractConfigs(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return const [];
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on Object {
      try {
        decoded = jsonDecode(_withoutComments(text));
      } on Object {
        return const [];
      }
    }
    if (decoded is Map) {
      final config = _fromMap(_asStringMap(decoded));
      return config == null ? const [] : [config.encode()];
    }
    if (decoded is List) {
      final out = <String>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final config = _fromMap(_asStringMap(item));
        if (config != null) out.add(config.encode());
      }
      return out;
    }
    return const [];
  }

  // сам xray читает // /* */ и # вне строк (infra/conf/json/reader.go), примеры Xray-examples ими полны
  static String _withoutComments(String text) {
    final out = StringBuffer();
    String? quote;
    var i = 0;
    while (i < text.length) {
      final c = text[i];
      final next = i + 1 < text.length ? text[i + 1] : '';
      if (quote != null) {
        out.write(c);
        if (c == '\\' && next.isNotEmpty) {
          out.write(next);
          i += 2;
          continue;
        }
        if (c == quote) quote = null;
        i++;
      } else if (c == '"' || c == "'") {
        quote = c;
        out.write(c);
        i++;
      } else if (c == '#' || (c == '/' && next == '/')) {
        while (i < text.length && text[i] != '\n') {
          i++;
        }
      } else if (c == '/' && next == '*') {
        final end = text.indexOf('*/', i + 2);
        i = end < 0 ? text.length : end + 2;
      } else {
        out.write(c);
        i++;
      }
    }
    return out.toString();
  }

  String encode() => const JsonEncoder.withIndent('  ').convert(json);

  String get remarks {
    for (final key in _remarkKeys) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  Map<String, dynamic>? get primaryOutbound {
    final outbounds = _outboundsOf(json);
    for (final outbound in outbounds) {
      final protocol = outbound['protocol']?.toString().toLowerCase() ?? '';
      if (_localOutboundProtocols.contains(protocol)) continue;
      return outbound;
    }
    return outbounds.isEmpty ? null : outbounds.first;
  }

  String get primaryOutboundTag {
    final tag = primaryOutbound?['tag']?.toString().trim() ?? '';
    return tag.isEmpty ? 'proxy' : tag;
  }

  // в маршрут идёт главный выход и те, через которые он ходит сам, под тегами tag, tag-1...
  // теги автора совпали бы с тегами сессии. null, если dialerProxy ведёт мимо его выходов
  List<Map<String, dynamic>>? routeOutbounds(String tag) {
    final primary = primaryOutbound;
    if (primary == null) return null;
    final byTag = <String, Map<String, dynamic>>{
      for (final outbound in _outboundsOf(json))
        if ((outbound['tag']?.toString() ?? '').isNotEmpty)
          outbound['tag'].toString(): outbound,
    };
    final picked = [primary];
    final tags = <String, String>{
      if ((primary['tag']?.toString() ?? '').isNotEmpty)
        primary['tag'].toString(): tag,
    };
    for (var i = 0; i < picked.length; i++) {
      final dialer = _dialerProxyOf(picked[i]);
      if (dialer == null || tags.containsKey(dialer)) continue;
      final next = byTag[dialer];
      if (next == null) return null;
      tags[dialer] = '$tag-${picked.length}';
      picked.add(next);
    }

    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < picked.length; i++) {
      final copy = (jsonDecode(jsonEncode(picked[i])) as Map).cast<String, dynamic>();
      copy['tag'] = i == 0 ? tag : tags[picked[i]['tag'].toString()];
      final sockopt = (copy['streamSettings'] as Map?)?['sockopt'];
      final dialer = _dialerProxyOf(copy);
      if (sockopt is Map && dialer != null) sockopt['dialerProxy'] = tags[dialer];
      out.add(copy);
    }
    final wrapped = <String, dynamic>{'outbounds': out};
    stripRemovedTlsFields(wrapped);
    migrateDeprecatedXrayFields(wrapped);
    return out;
  }

  static String? _dialerProxyOf(Map<String, dynamic> outbound) {
    final stream = outbound['streamSettings'];
    if (stream is! Map) return null;
    final sockopt = stream['sockopt'];
    if (sockopt is! Map) return null;
    final dialer = sockopt['dialerProxy']?.toString().trim() ?? '';
    return dialer.isEmpty ? null : dialer;
  }

  // по адресу tcp-пинг и исключение сервера из TUN, иначе коннект ядра к серверу уйдёт в петлю
  ({String address, int port}) get endpoint {
    for (final outbound in _outboundsOf(json)) {
      final protocol = outbound['protocol']?.toString().toLowerCase() ?? '';
      if (_localOutboundProtocols.contains(protocol)) continue;
      final found = _endpointOf(outbound);
      if (found != null) return found;
    }
    return (address: '', port: 0);
  }

  String get address => endpoint.address;
  int get port => endpoint.port;

  Map<String, dynamic>? get authorDns {
    final raw = json['dns'];
    if (raw is! Map) return null;
    final servers = raw['servers'];
    if (servers is! List || servers.isEmpty) return null;
    return _asStringMap(raw);
  }

  // хвост для случая, когда авторский резолвер недостижим: DPI режет udp:1.1.1.1:53 на российском входе,
  // а наш DoH идёт по 443. записи с domains в хвост не идут
  static Map<String, dynamic>? mergeDns(
    Map<String, dynamic>? author,
    Map<String, dynamic>? fallback,
  ) {
    if (author == null) return fallback;
    if (fallback == null) return author;

    final authorServers = (author['servers'] as List?) ?? const [];
    final seen = <String>{
      for (final server in authorServers) _dnsServerAddress(server),
    }..remove('');

    final tail = <Object?>[];
    for (final server in (fallback['servers'] as List?) ?? const []) {
      if (server is Map && server['domains'] != null) continue;
      final address = _dnsServerAddress(server);
      if (address.isEmpty || !seen.add(address)) continue;
      tail.add(server);
    }

    if (tail.isEmpty) return author;
    return <String, dynamic>{
      ...author,
      'servers': [...authorServers, ...tail],
    };
  }

  static String _dnsServerAddress(Object? server) {
    if (server is String) return server.trim();
    if (server is Map) return server['address']?.toString().trim() ?? '';
    return '';
  }

  Map<String, dynamic> buildSessionConfig({
    required List<Map<String, dynamic>> inbounds,
    required String logLevel,
    Map<String, dynamic>? dns,
    List<Map<String, dynamic>> prependRules = const [],
    List<Map<String, dynamic>> appendRules = const [],
    GeoAssetIndex? geoIndex,
  }) {
    final out = Map<String, dynamic>.from(json);
    for (final key in _remarkKeys) {
      out.remove(key);
    }

    final log = Map<String, dynamic>.from(
      (out['log'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
    log['loglevel'] = logLevel;
    out['log'] = log;

    out['inbounds'] = inbounds;

    final mergedDns = mergeDns(authorDns, dns);
    if (mergedDns != null) out['dns'] = mergedDns;

    if (prependRules.isNotEmpty || appendRules.isNotEmpty) {
      final routing = Map<String, dynamic>.from(
        (out['routing'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
      routing['rules'] = <Map<String, dynamic>>[
        ...prependRules,
        ...?_rulesOf(routing),
        ...appendRules,
      ];
      out['routing'] = routing;
    }

    if (geoIndex != null && !geoIndex.isEmpty) {
      stripUnknownGeoFromConfig(out, geoIndex);
    }
    stripRemovedTlsFields(out);
    migrateDeprecatedXrayFields(out);
    return out;
  }

  Map<String, dynamic> buildPingConfig({
    required List<Map<String, dynamic>> inbounds,
    required List<Map<String, dynamic>> rules,
  }) {
    final outbounds = _outboundsOf(json);
    final out = <String, dynamic>{
      'log': {'loglevel': 'none'},
      'dns': {
        'servers': ['8.8.8.8', '1.1.1.1'],
        'queryStrategy': 'UseIPv4',
      },
      'inbounds': inbounds,
      'outbounds': outbounds,
      'routing': {
        'domainStrategy': 'AsIs',
        'rules': rules,
      },
    };
    stripRemovedTlsFields(out);
    migrateDeprecatedXrayFields(out);
    return out;
  }

  // «Не учитывать правила провайдера»: уходят его сайты напрямую и в блок и его catch-all.
  // правила к его узлам и технические (протокол, порт, вход) остаются, без них ломаются конфиги на несколько узлов
  CustomXrayConfig withoutProviderRules() {
    final routing = json['routing'];
    if (routing is! Map) return this;
    final routingMap = _asStringMap(routing);
    final rules = _rulesOf(routingMap);
    if (rules == null) return this;
    final local = <String>{
      for (final outbound in _outboundsOf(json))
        if (const {'freedom', 'blackhole'}
            .contains(outbound['protocol']?.toString().toLowerCase()))
          outbound['tag']?.toString() ?? '',
    }..remove('');
    return CustomXrayConfig._({
      ...json,
      'routing': {
        ...routingMap,
        'rules': [
          for (final rule in rules)
            if (!_isProviderSiteRule(rule, local) && !_isCatchAll(rule)) rule,
        ],
      },
    });
  }

  bool get hasProviderRules {
    final routing = json['routing'];
    if (routing is! Map) return false;
    final before = _rulesOf(_asStringMap(routing))?.length ?? 0;
    final after = _rulesOf(
          _asStringMap(withoutProviderRules().json['routing'] as Map),
        )?.length ??
        0;
    return after < before;
  }

  static bool _isProviderSiteRule(Map<String, dynamic> rule, Set<String> local) =>
      local.contains(rule['outboundTag']?.toString()) &&
      (rule['domain'] != null || rule['ip'] != null);

  static const _notConditions = {
    'type',
    'ruleTag',
    'outboundTag',
    'balancerTag',
    'network',
  };

  // порт 0-65535 тоже catch-all: так его пишут провайдеры, у которых в конце «всё напрямую»
  static bool _isCatchAll(Map<String, dynamic> rule) {
    final conditions = rule.keys.where((k) => !_notConditions.contains(k)).toSet();
    if (conditions.isEmpty) return true;
    if (conditions.length != 1 || conditions.single != 'port') return false;
    final port = rule['port']?.toString().replaceAll(' ', '');
    return port == '0-65535' || port == '1-65535';
  }

  static Map<String, dynamic> _asStringMap(Map<dynamic, dynamic> raw) =>
      <String, dynamic>{for (final e in raw.entries) e.key.toString(): e.value};

  static List<Map<String, dynamic>> _outboundsOf(Map<String, dynamic> map) {
    final raw = map[_requiredKey];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map) _asStringMap(item),
    ];
  }

  static List<Map<String, dynamic>>? _rulesOf(Map<String, dynamic> routing) {
    final raw = routing['rules'];
    if (raw is! List) return null;
    return [
      for (final item in raw)
        if (item is Map) _asStringMap(item),
    ];
  }

  static ({String address, int port})? _endpointOf(
    Map<String, dynamic> outbound,
  ) {
    final settings = outbound['settings'];
    if (settings is! Map) return null;
    final s = _asStringMap(settings);

    for (final key in const ['vnext', 'servers']) {
      final list = s[key];
      if (list is! List) continue;
      for (final item in list) {
        if (item is! Map) continue;
        final entry = _endpointFields(_asStringMap(item));
        if (entry != null) return entry;
      }
    }

    final flat = _endpointFields(s);
    if (flat != null) return flat;

    final peers = s['peers'];
    if (peers is List) {
      for (final peer in peers) {
        if (peer is! Map) continue;
        final endpoint = _asStringMap(peer)['endpoint']?.toString() ?? '';
        final split = _splitHostPort(endpoint);
        if (split != null) return split;
      }
    }
    return null;
  }

  static ({String address, int port})? _endpointFields(
    Map<String, dynamic> map,
  ) {
    final address = (map['address'] ?? map['host'] ?? '').toString().trim();
    if (address.isEmpty) return null;
    final port = int.tryParse(map['port']?.toString() ?? '') ?? 0;
    return (address: address, port: port);
  }

  static ({String address, int port})? _splitHostPort(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final colon = value.lastIndexOf(':');
    if (colon <= 0) return null;
    final host = value.substring(0, colon).replaceAll(RegExp(r'^\[|\]$'), '');
    final port = int.tryParse(value.substring(colon + 1)) ?? 0;
    if (host.isEmpty) return null;
    return (address: host, port: port);
  }
}

({List<String> tokens, int removedRules}) previewUnknownGeo(
  Map<String, dynamic> config,
  GeoAssetIndex index,
) {
  if (index.isEmpty) return (tokens: const <String>[], removedRules: 0);
  final copy = jsonDecode(jsonEncode(config)) as Map<String, dynamic>;
  final before = _routingRuleCount(copy);
  final tokens = stripUnknownGeoFromConfig(copy, index);
  return (tokens: tokens, removedRules: before - _routingRuleCount(copy));
}

({int rules, List<String> tags}) previewDeadInboundRules(
  Map<String, dynamic> config,
  List<String> keptTags,
) {
  final routing = config['routing'];
  if (routing is! Map) return (rules: 0, tags: const <String>[]);
  final rules = routing['rules'];
  if (rules is! List) return (rules: 0, tags: const <String>[]);

  final dnsOutbounds = <String>{
    for (final o in (config['outbounds'] as List? ?? const []))
      if (o is Map &&
          o['protocol']?.toString().toLowerCase() == 'dns' &&
          o['tag'] is String)
        o['tag'] as String,
  };

  var dead = 0;
  final tags = <String>[];
  for (final rule in rules) {
    if (rule is! Map) continue;
    final raw = rule['inboundTag'];
    final ruleTags = switch (raw) {
      String s => [s],
      List l => [for (final t in l) t.toString()],
      _ => const <String>[],
    }.where((t) => t.trim().isNotEmpty).toList();
    if (ruleTags.isEmpty) continue;
    if (ruleTags.any(keptTags.contains)) continue;
    if (dnsOutbounds.contains(rule['outboundTag']?.toString())) continue;
    dead++;
    tags.addAll(ruleTags);
  }
  return (rules: dead, tags: tags);
}

int _routingRuleCount(Map<String, dynamic> config) {
  final routing = config['routing'];
  if (routing is! Map) return 0;
  final rules = routing['rules'];
  return rules is List ? rules.length : 0;
}

List<String> stripUnknownGeoFromConfig(
  Map<String, dynamic> config,
  GeoAssetIndex index,
) {
  final dropped = <String>[];
  if (index.isEmpty) return dropped;

  List<String>? clean(Object? raw) {
    if (raw is! List) return null;
    final kept = <String>[];
    for (final item in raw) {
      final token = item?.toString().trim() ?? '';
      if (token.isEmpty) continue;
      if (isKnownGeoToken(token, index)) {
        kept.add(token);
      } else if (geoSubstitutes(token, index) case final subs?) {
        kept.addAll(subs);
      } else {
        dropped.add(token);
      }
    }
    return kept;
  }

  final routing = config['routing'];
  if (routing is Map) {
    final rules = routing['rules'];
    if (rules is List) {
      final keptRules = <Object?>[];
      for (final rule in rules) {
        if (rule is! Map) {
          keptRules.add(rule);
          continue;
        }
        var lostCondition = false;
        for (final field in const ['domain', 'ip']) {
          final original = rule[field];
          final cleaned = clean(original);
          if (cleaned == null) continue;
          if (cleaned.isEmpty) {
            rule.remove(field);
            if (original is List && original.isNotEmpty) lostCondition = true;
          } else {
            rule[field] = cleaned;
          }
        }
        // условие вычистилось, значит правило стало бы шире задуманного ({ip: geoip:sberbank, port: 443} -> весь 443).
        // урезать можно, расширять нельзя. без условий xray падает на this rule has no effective fields
        if (lostCondition || !_ruleHasCondition(rule)) continue;
        keptRules.add(rule);
      }
      routing['rules'] = keptRules;
    }
  }

  final dns = config['dns'];
  if (dns is Map) {
    final servers = dns['servers'];
    if (servers is List) {
      final keptServers = <Object?>[];
      for (final server in servers) {
        if (server is! Map) {
          keptServers.add(server);
          continue;
        }
        final domains = clean(server['domains']);
        // сервер без доменов стал бы общим для всех запросов
        if (domains != null && domains.isEmpty) continue;
        if (domains != null) server['domains'] = domains;
        // пустой expectIPs значит принимать любой адрес, шире, чем хотел автор
        var lostFilter = false;
        for (final field in const ['expectIPs', 'expectedIPs']) {
          final original = server[field];
          final ips = clean(original);
          if (ips == null) continue;
          if (ips.isEmpty) {
            server.remove(field);
            if (original is List && original.isNotEmpty) lostFilter = true;
          } else {
            server[field] = ips;
          }
        }
        if (lostFilter) continue;
        keptServers.add(server);
      }
      dns['servers'] = keptServers;
    }
  }

  return dropped;
}

// ruleTag и domainMatcher это метки, а не условия. список по RawFieldRule в infra/conf/router.go:
// без process правило по программе из готового конфига выбрасывалось как пустое
bool _ruleHasCondition(Map<dynamic, dynamic> rule) => const [
      'domain',
      'domains',
      'ip',
      'port',
      'sourcePort',
      'network',
      'source',
      'sourceIP',
      'user',
      'vlessRoute',
      'inboundTag',
      'protocol',
      'attrs',
      'localIP',
      'localPort',
      'process',
      'localOS',
    ].any((field) {
      final value = rule[field];
      if (value == null) return false;
      if (value is Iterable) return value.isNotEmpty;
      if (value is String) return value.trim().isNotEmpty;
      if (value is Map) return value.isNotEmpty;
      return true;
    });
