import 'dart:convert';

typedef PingProbe = ({String id, String configJson, int port});

abstract final class MultiPingConfig {
  static String mergeXray(List<PingProbe> probes) {
    if (probes.isEmpty) throw ArgumentError('no probes');

    final inbounds = <Map<String, dynamic>>[];
    final outbounds = <Map<String, dynamic>>[];
    final rules = <Map<String, dynamic>>[];
    Map<String, dynamic>? dns;
    String domainStrategy = 'AsIs';

    for (var i = 0; i < probes.length; i++) {
      final probe = probes[i];
      final config = jsonDecode(probe.configJson) as Map<String, dynamic>;
      final suffix = '-$i';

      dns ??= config['dns'] as Map<String, dynamic>?;
      final routing = config['routing'] as Map<String, dynamic>?;
      if (i == 0 && routing?['domainStrategy'] is String) {
        domainStrategy = routing!['domainStrategy'] as String;
      }

      final renamed = <String, String>{};
      final probeInbounds = <Map<String, dynamic>>[];
      for (final raw in (config['inbounds'] as List? ?? const [])) {
        final inbound = Map<String, dynamic>.from(raw as Map);
        final tag = inbound['tag']?.toString();
        if (tag != null) {
          renamed[tag] = '$tag$suffix';
          inbound['tag'] = '$tag$suffix';
        }
        inbound['port'] = probe.port;
        probeInbounds.add(inbound);
      }
      final probeOutbounds = <Map<String, dynamic>>[];
      for (final raw in (config['outbounds'] as List? ?? const [])) {
        final outbound = Map<String, dynamic>.from(raw as Map);
        final tag = outbound['tag']?.toString();
        if (tag != null) {
          renamed[tag] = '$tag$suffix';
          outbound['tag'] = '$tag$suffix';
        }
        probeOutbounds.add(outbound);
      }
      // вторым проходом: dialerProxy ссылается на соседний тег, и карта имён к этому моменту должна быть полной
      for (final outbound in probeOutbounds) {
        _renameDialerProxies(outbound, renamed);
      }
      outbounds.addAll(probeOutbounds);

      final inboundTags = [
        for (final inbound in probeInbounds) inbound['tag'].toString(),
      ];
      inbounds.addAll(probeInbounds);

      for (final raw in (routing?['rules'] as List? ?? const [])) {
        final rule = Map<String, dynamic>.from(raw as Map);
        final outboundTag = rule['outboundTag']?.toString();
        if (outboundTag != null && renamed.containsKey(outboundTag)) {
          rule['outboundTag'] = renamed[outboundTag];
        }
        final ruleInbounds = rule['inboundTag'];
        if (ruleInbounds is List) {
          rule['inboundTag'] = [
            for (final tag in ruleInbounds) renamed[tag.toString()] ?? tag,
          ];
        } else {
          // без inboundTag правило действовало бы на все пробы разом
          rule['inboundTag'] = inboundTags;
        }
        rules.add(rule);
      }
    }

    return jsonEncode({
      'log': {'loglevel': 'none'},
      'dns': ?dns,
      'inbounds': inbounds,
      'outbounds': outbounds,
      'routing': {'domainStrategy': domainStrategy, 'rules': rules},
    });
  }

  static void _renameDialerProxies(Object? node, Map<String, String> renamed) {
    if (node is Map) {
      for (final key in node.keys.toList()) {
        final value = node[key];
        if (key == 'dialerProxy' && value is String) {
          final next = renamed[value];
          if (next != null) node[key] = next;
          continue;
        }
        _renameDialerProxies(value, renamed);
      }
    } else if (node is List) {
      for (final item in node) {
        _renameDialerProxies(item, renamed);
      }
    }
  }

  // у листенера mihomo нет поля ходи через этот прокси, привязка через rule и sub-rules с MATCH
  static String mergeMihomo(
    List<PingProbe> probes, {
    required bool httpListeners,
  }) {
    if (probes.isEmpty) throw ArgumentError('no probes');

    final proxies = <Map<String, dynamic>>[];
    final groups = <Map<String, dynamic>>[];
    final listeners = <Map<String, dynamic>>[];
    final subRules = <String, List<String>>{};
    Map<String, dynamic>? base;

    for (var i = 0; i < probes.length; i++) {
      final probe = probes[i];
      final config = jsonDecode(probe.configJson) as Map<String, dynamic>;
      base ??= config;

      final renamed = <String, String>{};
      final probeProxies = <Map<String, dynamic>>[];
      for (final raw in (config['proxies'] as List? ?? const [])) {
        final proxy = Map<String, dynamic>.from(raw as Map);
        final name = proxy['name']?.toString();
        if (name != null) {
          renamed[name] = '$name-$i';
          proxy['name'] = '$name-$i';
        }
        probeProxies.add(proxy);
      }
      // группы приходят от готового Clash; их имена в той же карте, на них ссылаются правило и узлы
      final probeGroups = <Map<String, dynamic>>[];
      for (final raw in (config['proxy-groups'] as List? ?? const [])) {
        final group = Map<String, dynamic>.from(raw as Map);
        final name = group['name']?.toString();
        if (name != null) {
          renamed[name] = '$name-$i';
          group['name'] = '$name-$i';
        }
        probeGroups.add(group);
      }
      // без этого звено цепочки ссылалось бы на имя до переименования, и ядро не нашло бы его
      for (final proxy in probeProxies) {
        final via = renamed[proxy['dialer-proxy']?.toString()];
        if (via != null) proxy['dialer-proxy'] = via;
      }
      for (final group in probeGroups) {
        final members = group['proxies'];
        if (members is List) {
          group['proxies'] = [
            for (final m in members) renamed[m.toString()] ?? m,
          ];
        }
        final fallback = renamed[group['empty-fallback']?.toString()];
        if (fallback != null) group['empty-fallback'] = fallback;
      }
      proxies.addAll(probeProxies);
      groups.addAll(probeGroups);

      final ruleSet = 'probe-$i';
      subRules[ruleSet] = [
        for (final raw in (config['rules'] as List? ?? const []))
          _renameProxyInRule(raw.toString(), renamed),
      ];
      listeners.add({
        'name': ruleSet,
        'type': httpListeners ? 'http' : 'socks',
        'listen': '127.0.0.1',
        'port': '${probe.port}',
        if (!httpListeners) 'udp': false,
        'rule': ruleSet,
      });
    }

    final first = base!;
    return jsonEncode({
      'bind-address': '127.0.0.1',
      'allow-lan': false,
      'ipv6': first['ipv6'] ?? false,
      'mode': first['mode'] ?? 'rule',
      'log-level': 'silent',
      'find-process-mode': 'off',
      'geo-auto-update': false,
      if (first['dns'] != null) 'dns': first['dns'],
      'proxies': proxies,
      if (groups.isNotEmpty) 'proxy-groups': groups,
      'listeners': listeners,
      'sub-rules': subRules,
      // без rules mihomo считает конфиг неполным
      'rules': const ['MATCH,DIRECT'],
    });
  }

  static String _renameProxyInRule(String rule, Map<String, String> renamed) {
    final comma = rule.lastIndexOf(',');
    if (comma < 0) return rule;
    final head = rule.substring(0, comma + 1);
    final target = rule.substring(comma + 1).trim();
    return '$head${renamed[target] ?? target}';
  }
}
