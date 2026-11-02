import 'dart:convert';

import '../models/app_settings.dart';
import '../models/server_item.dart';
import '../tunnel/vpn_backend.dart';
import 'custom_clash_config.dart';
import 'vpn_core_support.dart';

enum ClashMemberKind { node, group, direct, block, other }

// на xray подписка остаётся списком серверов, иначе выбор ядра в настройках молча перестал бы работать.
// «Не учитывать правила провайдера» выключает шаблон целиком, как и профиль от провайдера
bool clashTemplateApplies(AppSettings settings) =>
    !settings.ignoreProviderRules &&
    preferredBackend(settings.vpnCore) == VpnBackend.mihomo;

String? templatedSessionConfig({
  required ServerItem server,
  required String? template,
  required AppSettings settings,
  Map<String, String> choices = const {},
}) {
  if (!clashTemplateApplies(settings) || template == null) return null;
  final parsed = ClashTemplate.fromBody(template);
  final node = parsed?.nodeFor(server);
  if (parsed == null || node == null) return null;
  return parsed.sessionConfig(node: node, choices: choices);
}

class ClashTemplateGroup {
  const ClashTemplateGroup({
    required this.name,
    required this.members,
    required this.fromProviders,
  });

  final String name;
  final List<String> members;

  // состав из proxy-providers знает только запущенный mihomo
  final bool fromProviders;
}

// без групп select шаблон не храним: подписка работает как раньше
class ClashTemplate {
  ClashTemplate._(this.config, this.mainGroup, this.groups);

  final CustomClashConfig config;

  // цель MATCH: в ней выбирают нажатием на сервер
  final String mainGroup;

  final List<ClashTemplateGroup> groups;

  static ClashTemplate? fromBody(String body) {
    if (!CustomClashConfig.looksLikeClash(body)) return null;
    final config = CustomClashConfig.tryParse(body.trim());
    return config == null ? null : _of(config);
  }

  String encode() => config.encode();

  static const _builtins = {
    'DIRECT',
    'REJECT',
    'REJECT-DROP',
    'PASS',
    'COMPATIBLE',
  };

  static ClashTemplate? _of(CustomClashConfig config) {
    final nodes = [
      for (final p in config.proxies)
        if ((p['name']?.toString() ?? '').isNotEmpty &&
            CustomClashConfig.serverOf(p).address.isNotEmpty)
          p['name'].toString(),
    ];
    if (nodes.isEmpty) return null;
    final allProxies = [
      for (final p in config.proxies)
        if ((p['name']?.toString() ?? '').isNotEmpty) p['name'].toString(),
    ];
    final raw = config.map['proxy-groups'];
    if (raw is! List) return null;
    final byName = <String, Map<String, dynamic>>{
      for (final g in raw)
        if (g is Map && (g['name']?.toString() ?? '').isNotEmpty)
          g['name'].toString(): g.cast<String, dynamic>(),
    };
    if (byName.isEmpty) return null;
    // на relay и незнакомом типе ядро отказало бы всему шаблону, а узлами подписка работает (outboundgroup/parser.go)
    if (byName.values.any((g) => !_groupTypes.contains(g['type']?.toString()))) {
      return null;
    }

    final matched = _matchTarget(config.map['rules']);
    final main =
        matched != null && byName.containsKey(matched) ? matched : byName.keys.first;

    final groups = <ClashTemplateGroup>[];
    for (final MapEntry(key: name, value: g) in byName.entries) {
      if (name == main || g['type']?.toString() != 'select') continue;
      if (_isSet(g['hidden'])) continue;
      final fromProviders = _isSet(g['use']) ||
          _isSet(g['include-all']) ||
          _isSet(g['include-all-providers']);
      final members = _members(g, allProxies);
      if (members.length < 2 && !fromProviders) continue;
      groups.add(ClashTemplateGroup(
        name: name,
        members: members,
        fromProviders: fromProviders,
      ));
    }
    if (groups.isEmpty) return null;
    return ClashTemplate._(config, main, groups);
  }

  static const _groupTypes = {'select', 'url-test', 'fallback', 'load-balance'};

  static bool _isSet(Object? value) =>
      value != null &&
      value != false &&
      !(value is List && value.isEmpty) &&
      !const {'', '0', 'false'}.contains(value.toString().toLowerCase());

  static String? _matchTarget(Object? rules) {
    if (rules is! List) return null;
    for (final rule in rules) {
      final parts = rule.toString().split(',');
      if (parts.length >= 2 && parts.first.trim().toUpperCase() == 'MATCH') {
        return parts[1].trim();
      }
    }
    return null;
  }

  // как ядро (adapter/outboundgroup/parser.go): свои пункты, потом узлы по filter, без exclude-filter.
  // у ядра regexp2, у нас RegExp: на простых шаблонах совпадают, непонятный фильтр не применяем
  static List<String> _members(Map<String, dynamic> g, List<String> allProxies) {
    List<RegExp>? patterns(Object? raw) {
      final text = raw?.toString() ?? '';
      if (text.isEmpty) return null;
      try {
        return [for (final f in text.split('`')) RegExp(f)];
      } on FormatException {
        return null;
      }
    }

    final out = <String>[
      for (final m in (g['proxies'] is List ? g['proxies'] as List : const []))
        m.toString(),
    ];
    if (_isSet(g['include-all']) || _isSet(g['include-all-proxies'])) {
      final filter = patterns(g['filter']);
      out.addAll(filter == null
          ? allProxies
          : allProxies.where((p) => filter.any((r) => r.hasMatch(p))));
    }
    final exclude = patterns(g['exclude-filter']);
    final seen = <String>{};
    return [
      for (final m in out)
        if (seen.add(m) && !(exclude?.any((r) => r.hasMatch(m)) ?? false)) m,
    ];
  }

  ClashMemberKind kindOf(String member) {
    final upper = member.toUpperCase();
    if (upper == 'DIRECT') return ClashMemberKind.direct;
    if (upper == 'REJECT' || upper == 'REJECT-DROP') return ClashMemberKind.block;
    if (config.proxies.any((p) => p['name']?.toString() == member)) {
      return ClashMemberKind.node;
    }
    final raw = config.map['proxy-groups'];
    if (raw is List && raw.any((g) => g is Map && g['name']?.toString() == member)) {
      return ClashMemberKind.group;
    }
    return ClashMemberKind.other;
  }

  String? groupType(String name) {
    final raw = config.map['proxy-groups'];
    if (raw is! List) return null;
    for (final g in raw) {
      if (g is Map && g['name']?.toString() == name) return g['type']?.toString();
    }
    return null;
  }

  String? currentOf(ClashTemplateGroup group, Map<String, String> choices) {
    final chosen = choices[group.name];
    if (chosen != null && (group.members.contains(chosen) || group.fromProviders)) {
      return chosen;
    }
    return group.members.firstOrNull;
  }

  // правленный руками сервер исполняется как правлен, мимо шаблона
  String? nodeFor(ServerItem server) {
    if (server.configOverridden) return null;
    final names = {
      for (final p in config.proxies)
        if ((p['name']?.toString() ?? '').isNotEmpty) p['name'].toString(),
    };
    final single = server.protocol == 'clash'
        ? server.clashConfig?.proxies.firstOrNull
        : null;
    final own = single != null ? single['name']?.toString() : server.derivedName;
    if (own != null && names.contains(own)) return own;
    final byAddress = [
      for (final p in config.proxies)
        if (CustomClashConfig.serverOf(p).address == server.address &&
            CustomClashConfig.serverOf(p).port == server.port)
          p['name'].toString(),
    ];
    return byAddress.length == 1 ? byAddress.single : null;
  }

  // выбор передаём порядком: select без выбора берёт первый пункт (selector.go), а store-selected выключен,
  // иначе cache.db вернул бы прошлый выбор поверх сделанного без подключения
  String sessionConfig({
    required String node,
    Map<String, String> choices = const {},
  }) {
    final out = (jsonDecode(config.encode()) as Map).cast<String, dynamic>();
    final proxies = [...(out['proxies'] as List)];
    final at = proxies.indexWhere((p) => p is Map && p['name']?.toString() == node);
    // первый узел шаблона для генератора это сервер сессии: его адрес идёт напрямую
    if (at > 0) proxies.insert(0, proxies.removeAt(at));
    out['proxies'] = proxies;

    final groups = [
      for (final g in (out['proxy-groups'] as List))
        if (g is Map) g.cast<String, dynamic>(),
    ];
    final known = {
      ..._builtins,
      for (final p in proxies)
        if (p is Map) p['name']?.toString() ?? '',
      for (final g in groups) g['name']?.toString() ?? '',
    };
    // узел из proxy-providers ядро по имени из списка не найдёт и откажет всему конфигу
    void prefer(Map<String, dynamic> g, String member) {
      if (!known.contains(member)) return;
      final rest = [
        for (final m in (g['proxies'] is List ? g['proxies'] as List : const []))
          if (m.toString() != member) m,
      ];
      g['proxies'] = [member, ...rest];
    }

    final main = groups.firstWhere((g) => g['name']?.toString() == mainGroup);
    // всё остальное идёт через сервер, который выбрали, даже если у автора тут автовыбор
    main['type'] = 'select';
    prefer(main, node);
    for (final MapEntry(key: name, value: member) in choices.entries) {
      if (name == mainGroup) continue;
      for (final g in groups) {
        if (g['name']?.toString() == name && g['type']?.toString() == 'select') {
          prefer(g, member);
        }
      }
    }
    groups
      ..remove(main)
      ..insert(0, main);
    out['proxy-groups'] = groups;

    final profile = out['profile'];
    out['profile'] = {
      if (profile is Map) ...profile.cast<String, dynamic>(),
      'store-selected': false,
    };
    return const JsonEncoder.withIndent('  ').convert(out);
  }
}
