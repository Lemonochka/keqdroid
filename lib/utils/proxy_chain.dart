import 'dart:convert';

// через sockopt.dialerProxy: proxySettings.tag выбрасывает собственный транспорт узла (REALITY, XHTTP),
// а оба поля разом ядро не принимает
class ProxyChainConfig {
  static const String scheme = 'keqchain';
  static const String _prefix = '$scheme://';

  static const int maxHops = 8;

  // у xray узлом бывает только это, mihomo связывает через dialer-proxy любой свой исходящий (chainHopBackends)
  static const Set<String> xrayHopProtocols = {
    'vless',
    'vmess',
    'trojan',
    'ss',
    'hysteria',
    'hysteria2',
    'hy2',
  };

  final String name;
  final List<ProxyChainHop> hops;

  const ProxyChainConfig({required this.name, required this.hops});

  static bool looksLikeChain(String raw) =>
      raw.trimLeft().toLowerCase().startsWith(_prefix);

  static ProxyChainConfig? tryParse(String raw) {
    if (!looksLikeChain(raw)) return null;
    final Object? decoded;
    try {
      // normalize добивает padding: без выравнивания длины декодер падает
      decoded = jsonDecode(
        utf8.decode(base64.decode(base64.normalize(_payloadOf(raw)))),
      );
    } on Object {
      return null;
    }
    if (decoded is! Map) return null;

    final rawHops = decoded['hops'];
    if (rawHops is! List) return null;

    final hops = <ProxyChainHop>[];
    for (final item in rawHops) {
      if (item is! Map) continue;
      final config = item['config']?.toString().trim() ?? '';
      if (config.isEmpty) continue;
      final id = item['id']?.toString().trim() ?? '';
      hops.add(
        ProxyChainHop(
          serverId: id.isEmpty ? null : id,
          name: item['name']?.toString().trim() ?? '',
          config: config,
        ),
      );
    }
    if (hops.isEmpty) return null;

    return ProxyChainConfig(
      name: decoded['name']?.toString().trim() ?? '',
      hops: List.unmodifiable(hops),
    );
  }

  static String? describeProblem(String raw) {
    if (!looksLikeChain(raw)) return 'Not a proxy chain link';
    final parsed = tryParse(raw);
    if (parsed == null) return 'Damaged proxy chain link';
    if (parsed.hops.length < 2) {
      return 'A proxy chain needs at least two nodes';
    }
    if (parsed.hops.length > maxHops) {
      return 'A proxy chain holds at most $maxHops nodes';
    }
    return null;
  }

  static String _payloadOf(String raw) {
    final trimmed = raw.trim();
    final body = trimmed.substring(_prefix.length);
    final hash = body.indexOf('#');
    return (hash >= 0 ? body.substring(0, hash) : body).replaceAll(
      RegExp(r'\s+'),
      '',
    );
  }

  String encode() {
    final json = jsonEncode({
      'v': 1,
      'name': name,
      'hops': [
        for (final hop in hops)
          {
            if (hop.serverId != null) 'id': hop.serverId,
            if (hop.name.isNotEmpty) 'name': hop.name,
            'config': hop.config,
          },
      ],
    });
    return '$_prefix${base64Url.encode(utf8.encode(json)).replaceAll('=', '')}';
  }

  ProxyChainConfig copyWith({String? name, List<ProxyChainHop>? hops}) =>
      ProxyChainConfig(name: name ?? this.name, hops: hops ?? this.hops);

  ProxyChainHop get entry => hops.first;

  ProxyChainHop get exit => hops.last;

  ProxyChainConfig refreshed(Map<String, ({String config, String name})> live) {
    var changed = false;
    final updated = <ProxyChainHop>[];
    for (final hop in hops) {
      final id = hop.serverId;
      final actual = id == null ? null : live[id];
      if (actual == null ||
          (actual.config == hop.config && actual.name == hop.name)) {
        updated.add(hop);
        continue;
      }
      changed = true;
      updated.add(hop.copyWith(config: actual.config, name: actual.name));
    }
    return changed ? copyWith(hops: List.unmodifiable(updated)) : this;
  }

  @override
  String toString() => 'ProxyChainConfig($name, ${hops.length} hops)';
}

class ProxyChainHop {
  final String? serverId;

  final String name;

  final String config;

  const ProxyChainHop({required this.config, this.serverId, this.name = ''});

  ProxyChainHop copyWith({String? config, String? name}) => ProxyChainHop(
    serverId: serverId,
    name: name ?? this.name,
    config: config ?? this.config,
  );

  @override
  String toString() => 'ProxyChainHop($name)';
}
