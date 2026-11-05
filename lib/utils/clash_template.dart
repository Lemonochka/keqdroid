import 'dart:convert';

import '../models/app_settings.dart';
import '../models/server_item.dart';
import '../tunnel/vpn_backend.dart';
import 'custom_clash_config.dart';
import 'vpn_core_support.dart';

enum ClashMemberKind { node, group, direct, block, other }

// шаблон написан для mihomo: его серверы исполняет mihomo при любом ядре в настройках, как готовый конфиг Clash.
// «Не учитывать правила провайдера» выключает шаблон целиком, как и профиль от провайдера, и ядро снова из настроек
bool clashTemplateApplies(AppSettings settings) =>
    !settings.ignoreProviderRules && mihomoShipsHere;

// серверы, которые подключение отдаст шаблону: пинг и показ настроек обязаны решать ядро так же
Set<String> templateServerIds(
  Iterable<ServerItem> servers,
  AppSettings settings,
  String? Function(String subscriptionId) templateOf,
) {
  if (!clashTemplateApplies(settings)) return const {};
  final parsed = <String, ClashTemplate?>{};
  final ids = <String>{};
  for (final server in servers) {
    final sub = server.subscriptionId;
    if (sub == null) continue;
    final template = parsed.putIfAbsent(sub, () {
      final raw = templateOf(sub);
      return raw == null ? null : ClashTemplate.fromBody(raw);
    });
    if (template?.nodeFor(server) != null) ids.add(server.id);
  }
  return ids;
}

// ядро сервера так, как его решит подключение: сервер, взятый шаблоном, идёт через mihomo
VpnBackendChoice serverBackendChoice(
  ServerItem server, {
  required String preference,
  required bool viaTemplate,
}) {
  if (!viaTemplate) {
    return resolveVpnBackend(
      config: server.config,
      preference: preference,
      mihomoAvailable: mihomoShipsHere,
    );
  }
  return (
    backend: VpnBackend.mihomo,
    format: ServerFormat.clashYaml,
    skip: preferredBackend(preference) == VpnBackend.mihomo
        ? null
        : VpnCoreSkip.clashTemplate,
  );
}

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
    // нажатый сервер ставится в главную сам, но группы в ней (Public у Moondrop) иначе не выбрать ничем
    final mainGroup = byName[main]!;
    final mainMembers = _members(mainGroup, allProxies);
    if (mainMembers.any((m) => m != main && byName.containsKey(m))) {
      groups.insert(
        0,
        ClashTemplateGroup(
          name: main,
          members: mainMembers,
          fromProviders: _isSet(mainGroup['use']) ||
              _isSet(mainGroup['include-all']) ||
              _isSet(mainGroup['include-all-providers']),
        ),
      );
    }
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

  // url-test и fallback ядро умеет держать на одном узле (URLTest.Set), пока тот жив
  bool pinnable(String group) =>
      const {'url-test', 'fallback'}.contains(groupType(group));

  // группа (или DIRECT автора), которую выбрали в главной вместо нажатого сервера
  String? mainChoice(Map<String, String> choices) {
    final chosen = choices[mainGroup];
    if (chosen == null || chosen == mainGroup) return null;
    if (const {ClashMemberKind.node, ClashMemberKind.other}
        .contains(kindOf(chosen))) {
      return null;
    }
    final main = groups.where((g) => g.name == mainGroup).firstOrNull;
    return main != null && main.members.contains(chosen) ? chosen : null;
  }

  bool isRuleTarget(String group) {
    final subRules = config.map['sub-rules'];
    final lists = [
      config.map['rules'],
      if (subRules is Map) ...subRules.values,
    ];
    for (final list in lists) {
      if (list is! List) continue;
      for (final rule in list) {
        if (_ruleTarget(rule.toString()) == group) return true;
      }
    }
    return false;
  }

  // AND,((NETWORK,UDP),(DST-PORT,443)),REJECT: запятые внутри скобок цель не делят
  static String? _ruleTarget(String rule) {
    final parts = <String>[];
    var depth = 0;
    var start = 0;
    for (var i = 0; i < rule.length; i++) {
      final c = rule[i];
      if (c == '(') depth++;
      if (c == ')') depth--;
      if (c == ',' && depth == 0) {
        parts.add(rule.substring(start, i).trim());
        start = i + 1;
      }
    }
    parts.add(rule.substring(start).trim());
    if (parts.length < 2) return null;
    if (parts.first.toUpperCase() == 'MATCH') return parts[1];
    return parts.length >= 3 ? parts[2] : null;
  }

  // в какой группе её выбирают, если правила на неё не ведут
  String? parentOf(String group) {
    for (final g in groups) {
      if (g.name != group && g.members.contains(group)) return g.name;
    }
    return null;
  }

  String? currentOf(ClashTemplateGroup group, Map<String, String> choices) {
    if (group.name == mainGroup) return mainChoice(choices);
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
    // ссылка несёт имя обрезанным, а у провайдера бывает пробел по краю (Германия, 02.11.2026)
    final trimmed = [
      for (final name in names)
        if (own != null && name.trim() == own.trim()) name,
    ];
    if (trimmed.length == 1) return trimmed.single;
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
    prefer(main, mainChoice(choices) ?? node);
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
