import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../utils/custom_clash_config.dart';
import '../utils/custom_xray_config.dart';
import '../utils/hysteria_uri.dart';
import '../utils/mieru_uri.dart';
import '../utils/mihomo_config_gen.dart';
import '../utils/raw_share_uri.dart';
import '../utils/singbox_outbounds.dart';
import '../utils/socks_uri.dart';
import '../utils/ssr_uri.dart';
import '../utils/vmess_json_link.dart';

abstract final class SubscriptionBodyParser {
  // регулярки ссылок и base64 на строке в мегабайты переполняют стек в AOT: 10 МБ падают, 3 МБ проходят
  static const _maxVariantLength = 1024 * 1024;

  static List<String> parseBody(String content) {
    final original = content.trim();
    // вариантов у такого тела нет вовсе: JSON Geodema на 1,09 МБ выпадал целиком, будто ссылок нет
    if (original.length > _maxVariantLength) {
      final large = _parseLargeStructured(original);
      if (large.isNotEmpty) return large;
    }
    final candidates = _collectTextVariants(original);

    for (final candidate in candidates) {
      final extractedLinks = <String>{
        ..._extractUriLinks(candidate),
        ..._extractUriLinks(_htmlUnescape(candidate)),
        ..._extractUriLinks(_jsUnescape(_htmlUnescape(candidate))),
      }.where((c) => !_isMetadataConfig(c)).toList();
      final customConfigs = _extractCustomConfigs(candidate);
      if (extractedLinks.isNotEmpty || customConfigs.isNotEmpty) {
        return [...customConfigs, ...extractedLinks];
      }

      final singbox = SingboxOutbounds.translate(
        candidate,
      ).links.where((c) => !_isMetadataConfig(c)).toList();
      if (singbox.isNotEmpty) return singbox;

      final structured = _extractConfigsFromStructuredContent(candidate);
      if (structured.isNotEmpty) return structured;

      final clashConfigs = _extractClashConfigs(candidate);
      if (clashConfigs.isNotEmpty) return clashConfigs;

      final lines = LineSplitter.split(
        candidate,
      ).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      final hasOnlyMetadataLinks =
          lines.isNotEmpty &&
          lines.every((l) => !_isValidConfig(l) || _isMetadataConfig(l));
      final hasHwidGateMarkers = lines.any(_isHwidGateConfig);
      final providerGateMessage = _detectProviderGateMessage(lines);

      final configs = LineSplitter.split(candidate)
          .map((l) => l.trim())
          .where(_isValidConfig)
          .where((c) => !_isMetadataConfig(c))
          .toList();
      if (configs.isNotEmpty) return configs;
      if (hasOnlyMetadataLinks && providerGateMessage != null) {
        throw FormatException(providerGateMessage);
      }
      if (hasOnlyMetadataLinks && hasHwidGateMarkers) {
        throw const FormatException(
          'Subscription contains only service links. Provider asks to enable/bind HWID for this client.',
        );
      }
    }

    for (final candidate in candidates) {
      final unsupported = _detectUnsupportedFormat(candidate);
      if (unsupported != null) {
        throw FormatException(unsupported);
      }
    }
    throw const FormatException(
      'No supported proxy links found. Expected URI lines like vless://, vmess://, trojan://, ss://, ssr://, hysteria://, hysteria2://, hy2://, tuic://, anytls://, mierus:// or socks://',
    );
  }

  // порядок как в parseBody, но без регулярок по всему тексту, а YAML только у похожего на Clash
  static List<String> _parseLargeStructured(String body) {
    if (body.startsWith('[') || body.startsWith('{')) {
      final xray = CustomXrayConfig.extractConfigs(
        body,
      ).where(_isUsableCustomConfig).toList();
      if (xray.isNotEmpty) return xray;
      final singbox = SingboxOutbounds.translate(
        body,
      ).links.where((c) => !_isMetadataConfig(c)).toList();
      if (singbox.isNotEmpty) return singbox;
    }
    if (!CustomClashConfig.looksLikeClash(body)) return const [];
    final nodes = _extractConfigsFromStructuredContent(body);
    if (nodes.isNotEmpty) return nodes;
    return _extractClashConfigs(body);
  }

  static List<String> _extractCustomConfigs(String content) {
    final whole = CustomXrayConfig.extractConfigs(content);
    if (whole.isNotEmpty) {
      return whole.where(_isUsableCustomConfig).toList();
    }

    final out = <String>[];
    for (final raw in LineSplitter.split(content)) {
      final line = raw.trim();
      if (line.isEmpty || _isValidConfig(line)) continue;
      if (CustomXrayConfig.looksLikeJson(line)) {
        out.addAll(CustomXrayConfig.extractConfigs(line));
        continue;
      }
      if (line.length < 40 || !_base64Line.hasMatch(line)) continue;
      final decoded = tryDecodeBase64Flexible(line);
      if (decoded == null) continue;
      out.addAll(CustomXrayConfig.extractConfigs(decoded));
    }
    return out.where(_isUsableCustomConfig).toList();
  }

  static List<String> _extractClashConfigs(String content) {
    final whole = CustomClashConfig.extractConfigs(content);
    return whole.where(_isUsableClashConfig).toList();
  }

  // профиль на proxy-providers без адресов, узлы ядро скачает само
  static bool _isUsableClashConfig(String config) {
    final clash = CustomClashConfig.tryParse(config);
    if (clash == null) return false;
    return clash.address.isNotEmpty || clash.usesProviders;
  }

  // без адреса сервера перед нами заглушка панели (истёкшая подписка, непривязанный HWID)
  static bool _isUsableCustomConfig(String config) {
    if (_isMetadataConfig(config)) return false;
    final custom = CustomXrayConfig.tryParse(config);
    return custom != null && custom.address.isNotEmpty;
  }

  static final _base64Line = RegExp(r'^[A-Za-z0-9+/_=-]+$');

  static List<String> _collectTextVariants(String input) {
    // в релизе даже итеративный обход base64 и regex съедал стек, отсюда лимиты
    const maxVariants = 12;
    const maxQueueSize = 50;

    final queue = <String>[input];
    final seen = <String>{};
    final out = <String>[];

    int iterations = 0;
    const maxIterations = 200;

    while (queue.isNotEmpty &&
        out.length < maxVariants &&
        iterations < maxIterations) {
      iterations++;

      if (queue.length > maxQueueSize) {
        queue.clear();
        break;
      }

      final current = queue.removeAt(0).trim();
      if (current.isEmpty ||
          current.length > _maxVariantLength ||
          !seen.add(current)) {
        continue;
      }
      out.add(current);

      final html = _htmlUnescape(current);
      final js = _jsUnescape(html);
      final decoded = tryDecodeBase64Flexible(current);
      final decodedCompact = tryDecodeBase64Flexible(
        current.replaceAll(RegExp(r'\s+'), ''),
      );
      final uriDecoded = _tryUriDecode(current);

      final nextCandidates = [html, js, decoded, decodedCompact, uriDecoded]
          .whereType<String>()
          .where((s) => s.trim().isNotEmpty && !seen.contains(s.trim()))
          .take(4)
          .toList();

      queue.addAll(nextCandidates);
    }

    return out;
  }

  static String? _tryUriDecode(String input) {
    try {
      final decoded = Uri.decodeFull(input);
      return decoded == input ? null : decoded;
    } on Object {
      return null;
    }
  }

  static String? tryDecodeBase64Flexible(String input) {
    final compact = input
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('-', '+')
        .replaceAll('_', '/');
    if (compact.isEmpty) return null;

    final padded = switch (compact.length % 4) {
      2 => '$compact==',
      3 => '$compact=',
      _ => compact,
    };
    try {
      return const Utf8Decoder().convert(
        base64.decode(base64.normalize(padded)),
      );
    } on Object {
      return null;
    }
  }

  static String? _detectUnsupportedFormat(String content) {
    final text = content.trimLeft();
    final lower = text.toLowerCase();

    if (lower.startsWith('proxies:') ||
        lower.contains('\nproxies:') ||
        lower.startsWith('mixed-port:') ||
        lower.startsWith('proxy-providers:') ||
        lower.contains('\nproxy-providers:')) {
      final problem = CustomClashConfig.describeProblem(text);
      if (problem != null) return 'Clash subscription: $problem';
      return 'Clash subscription returned a config without a server address. '
          'This is usually a provider stub: check subscription status and '
          'HWID binding in the provider panel.';
    }

    if (SingboxOutbounds.looksLike(text)) {
      return SingboxOutbounds.describeProblem(text) ??
          SingboxOutbounds.noServers;
    }

    if (text.startsWith('{') || text.startsWith('[')) {
      try {
        final parsed = jsonDecode(text);
        if (parsed is Map<String, dynamic>) {
          final keys = parsed.keys.map((k) => k.toLowerCase()).toSet();
          if (keys.contains('outbounds') ||
              keys.contains('inbounds') ||
              keys.contains('proxies')) {
            if (CustomXrayConfig.tryParse(text) != null) {
              return 'Subscription returned an Xray config without a server address. '
                  'This is usually a provider stub: check subscription status and '
                  'HWID binding in the provider panel.';
            }
            return 'Unsupported subscription format: JSON config '
                '(only Xray, sing-box and Clash configs are supported)';
          }
        } else if (parsed is List && parsed.isNotEmpty) {
          return 'Unsupported subscription format: JSON array config';
        }
      } on Object {
        // не json, ниже общий текст ошибки
      }
    }
    return null;
  }

  static List<String> _extractConfigsFromStructuredContent(String content) {
    final found = <String>{};

    final trimmed = content.trimLeft();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        final parsed = jsonDecode(content);
        _walkStructured(parsed, found);
      } on Object {
        // не json
      }
    }

    final (:proxies, :groups, :standalone) = _extractYamlLikeProxies(content);
    for (final proxy in proxies) {
      final config = _clashNodeConfig(
        proxy,
        proxies,
        groups: groups,
        standalone: standalone,
      );
      if (config != null) found.add(config);
    }

    return found.toList();
  }

  // файл и буфер раскладываются по узлам так же, как подписка; профиль на proxy-providers остаётся целым
  static List<String> clashNodeConfigs(String content) {
    final clash = CustomClashConfig.tryParse(content);
    if (clash == null || CustomClashConfig.usesProviderNodes(clash.map)) {
      return const [];
    }
    final proxies = clash.proxies;
    final groups = _groupsOf(clash.map);
    return {
      for (final proxy in proxies)
        ?_clashNodeConfig(proxy, proxies, groups: groups, standalone: true),
    }.toList();
  }

  // ссылки у этих типов нет, узел исполняет mihomo; список по adapter/parser.go 1.19.32 без вырезанных сборкой
  static const _mihomoOnlyTypes = {
    'snell',
    'hysteria',
    'wireguard',
    'shadowquic',
    'gost-relay',
    'ssh',
    'sudoku',
    'masque',
    'trusttunnel',
    'openvpn',
    'socks5',
    'http',
  };

  static String? _clashNodeConfig(
    Map<String, dynamic> node,
    List<Map<String, dynamic>> all, {
    List<Map<String, dynamic>> groups = const [],
    required bool standalone,
  }) {
    final uri = _proxyMapToUri(node);
    if (uri != null) {
      if (_isMetadataConfig(uri)) return null;
      return _linkKeepsNode(node, uri)
          ? uri
          : _singleNodeClash(node, all, groups) ?? uri;
    }
    if (!standalone) return null;
    final type = node['type']?.toString().trim().toLowerCase() ?? '';
    if (!_mihomoOnlyTypes.contains(type)) return null;
    if (CustomClashConfig.serverOf(node).address.isEmpty) return null;
    return _singleNodeClash(node, all, groups);
  }

  static List<Map<String, dynamic>> _groupsOf(Map<String, dynamic> map) {
    final raw = map['proxy-groups'];
    return [
      if (raw is List)
        for (final group in raw)
          if (group is Map) group.cast<String, dynamic>(),
    ];
  }

  // skip-cert-verify ссылка не несёт намеренно (_applyTransport), name и udp генератор пишет свои
  static const _nodeKeysLinkMayDrop = {'name', 'skip-cert-verify', 'udp'};

  // ссылка обязана довезти до ядра всё, что нёс узел, а пин, token tuic, ss-opts и dialer-proxy терялись молча;
  // сверяем обратным ходом через генератор mihomo
  static bool _linkKeepsNode(Map<String, dynamic> node, String link) =>
      _keysLinkLoses(node, link).isEmpty;

  @visibleForTesting
  static List<String> keysLinkLoses(Map<String, dynamic> node) {
    final link = _proxyMapToUri(node);
    return link == null ? const ['<no link>'] : _keysLinkLoses(node, link);
  }

  static List<String> _keysLinkLoses(Map<String, dynamic> node, String link) {
    final Map<String, dynamic> back;
    try {
      back = MihomoConfigGen.buildProxies(link).first;
    } on Object {
      return const ['<link refused>'];
    }
    return [
      for (final MapEntry(:key, :value) in node.entries)
        if (!_nodeKeysLinkMayDrop.contains(key) && !_carried(value, back[key]))
          key,
    ];
  }

  // всё заданное в узле есть и в результате, добавленное генератором потерей не считается (флаг постквантового
  // ключа); пусто, false и 0 у mihomo читаются как не задано, а числа в YAML бывают строками
  static bool _carried(Object? want, Object? got) {
    bool unset(Object? v) =>
        v == null ||
        v == false ||
        v == '' ||
        v == 0 ||
        v == '0' ||
        (v is Iterable && v.isEmpty) ||
        (v is Map && v.isEmpty);
    if (unset(want)) return true;
    if (want is Map) {
      if (got is! Map) return false;
      return want.entries.every((e) => _carried(e.value, got[e.key]));
    }
    if (want is List) {
      if (got is! List || got.length != want.length) return false;
      for (var i = 0; i < want.length; i++) {
        if (!_carried(want[i], got[i])) return false;
      }
      return true;
    }
    return want.toString() == got?.toString();
  }

  // так узел исполняет mihomo целиком, как v2rayN, FlClash и Clash Verge исполняют Clash
  static String? _singleNodeClash(
    Map<String, dynamic> node,
    List<Map<String, dynamic>> all,
    List<Map<String, dynamic>> groups,
  ) {
    final name = node['name']?.toString().trim() ?? '';
    if (name.isEmpty) return null;
    final hops = CustomClashConfig.withHops(node, all, groups);
    if (hops == null) return null;
    return jsonEncode({
      'name': name,
      'proxies': hops.proxies,
      if (hops.groups.isNotEmpty) 'proxy-groups': hops.groups,
      'rules': ['MATCH,$name'],
    });
  }

  // итеративно: рекурсия переполняла стек на глубоких json
  static void _walkStructured(Object? node, Set<String> found) {
    const maxTotalNodes = 5000;
    const maxQueueSize = 200;
    const maxDepth = 8;

    final queue = <(Object?, int, bool)>[];
    final seen = <Object>{};

    if (node != null) {
      queue.add((node, 0, false));
    }

    int iterations = 0;
    const maxIterations = 1000;

    while (queue.isNotEmpty &&
        found.length < maxTotalNodes &&
        iterations < maxIterations) {
      iterations++;

      if (queue.length > maxQueueSize) {
        queue.removeRange(
          0,
          (queue.length - maxQueueSize ~/ 2).clamp(1, queue.length),
        );
      }

      final (current, depth, isDirect) = queue.removeAt(0);

      if (current == null || depth > maxDepth) continue;

      if (current is String) {
        if (isDirect) {
          for (final uri in _extractUriLinks(current)) {
            if (!_isMetadataConfig(uri)) found.add(uri);
          }
        } else {
          if (depth <= 2) {
            for (final v in _collectTextVariants(current)) {
              for (final uri in _extractUriLinks(v)) {
                if (!_isMetadataConfig(uri)) found.add(uri);
              }
            }
          }
        }
        continue;
      }

      if (current is List) {
        final itemsToProcess = current.take(100);
        for (final item in itemsToProcess) {
          if (seen.add(item as Object)) {
            queue.add((item, depth + 1, false));
          }
        }
        continue;
      }

      if (current is Map) {
        final map = <String, dynamic>{};
        current.forEach((k, v) {
          map[k.toString()] = v;
        });

        final uri = _proxyMapToUri(map);
        if (uri != null && !_isMetadataConfig(uri)) {
          found.add(uri);
        }

        var entriesAdded = 0;
        for (final entry in map.entries.take(50)) {
          final value = entry.value;
          if (value is String) {
            final isLikelyConfig =
                value.startsWith('vless://') ||
                value.startsWith('vmess://') ||
                value.startsWith('ss://') ||
                value.startsWith('trojan://') ||
                value.startsWith('http://') ||
                value.startsWith('https://');
            if (seen.add(value)) {
              queue.add((value, depth + 1, isLikelyConfig));
              entriesAdded++;
              if (entriesAdded >= 20) break;
            }
          } else if (seen.add(value as Object)) {
            queue.add((value, depth + 1, false));
            entriesAdded++;
            if (entriesAdded >= 20) break;
          }
        }
      }
    }
  }

  // узлы неизвестного типа молча пропадали, и подписка на 20 серверов приезжала как 12
  static Map<String, int> unsupportedClashNodes(String content) {
    final counts = <String, int>{};
    final (:proxies, :groups, :standalone) = _extractYamlLikeProxies(content);
    for (final proxy in proxies) {
      if (_proxyMapToUri(proxy) != null) continue;
      if (_clashNodeConfig(
            proxy,
            proxies,
            groups: groups,
            standalone: standalone,
          ) !=
          null) {
        continue;
      }
      final type = (proxy['type'] ?? proxy['protocol'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final key = type.isEmpty ? 'unknown' : type;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }

  static String? skippedNodesSummary(Map<String, int> counts) {
    if (counts.isEmpty) return null;
    final parts = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return parts.map((e) => '${e.value} of type ${e.key}').join(', ');
  }

  // standalone: узел без ссылки можно отдать mihomo одного. Строчный разбор теряет вложенные карты (amnezia-wg-option),
  // а у профиля на proxy-providers вынутый socks5 заслонил бы узлы провайдера, и профиль целиком уже не собрался бы
  static ({
    List<Map<String, dynamic>> proxies,
    List<Map<String, dynamic>> groups,
    bool standalone,
  })
  _extractYamlLikeProxies(String content) {
    final parsed = CustomClashConfig.tryParse(content);
    if (parsed != null && parsed.proxies.isNotEmpty) {
      return (
        proxies: parsed.proxies,
        groups: _groupsOf(parsed.map),
        standalone: !CustomClashConfig.usesProviderNodes(parsed.map),
      );
    }
    return (
      proxies: _scanYamlLikeProxies(content),
      groups: const [],
      standalone: false,
    );
  }

  static List<Map<String, dynamic>> _scanYamlLikeProxies(String content) {
    final lines = LineSplitter.split(content).toList();
    final proxies = <Map<String, dynamic>>[];
    Map<String, dynamic>? current;
    var inProxiesSection = false;

    for (final raw in lines) {
      final line = raw.replaceAll('\t', '  ');
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      if (trimmed.toLowerCase() == 'proxies:') {
        inProxiesSection = true;
        current = null;
        continue;
      }
      if (!inProxiesSection) continue;
      if (!line.startsWith(' ') && !trimmed.startsWith('- ')) {
        if (current != null && current.isNotEmpty) proxies.add(current);
        current = null;
        inProxiesSection = false;
        continue;
      }
      if (trimmed.startsWith('- ')) {
        if (current != null && current.isNotEmpty) proxies.add(current);
        current = <String, dynamic>{};
        final rest = trimmed.substring(2).trim();
        if (rest.contains(':')) {
          final idx = rest.indexOf(':');
          current[_cleanKey(rest.substring(0, idx))] = _cleanYamlValue(
            rest.substring(idx + 1),
          );
        }
        continue;
      }
      if (current == null || !trimmed.contains(':')) continue;
      final idx = trimmed.indexOf(':');
      final key = _cleanKey(trimmed.substring(0, idx));
      final val = _cleanYamlValue(trimmed.substring(idx + 1));
      current[key] = val;
    }
    if (current != null && current.isNotEmpty) proxies.add(current);
    return proxies;
  }

  static String _cleanKey(String input) => input.trim().toLowerCase();

  static String _cleanYamlValue(String input) {
    final v = input.trim();
    if (v.length >= 2 &&
        ((v.startsWith('"') && v.endsWith('"')) ||
            (v.startsWith("'") && v.endsWith("'")))) {
      return v.substring(1, v.length - 1).trim();
    }
    return v;
  }

  // без вложенных карт ссылка теряет ключ REALITY и имя grpc-сервиса, собирается и молча не подключается
  static Map<String, String> _flattenClashProxy(Map<String, dynamic> raw) {
    final map = <String, String>{};
    String text(Object? v) {
      if (v == null) return '';
      if (v is List) return v.map((e) => e?.toString().trim() ?? '').join(',');
      return v.toString().trim();
    }

    void put(String key, Object? value) {
      final v = text(value);
      if (v.isNotEmpty && (map[key] ?? '').isEmpty) map[key] = v;
    }

    raw.forEach((k, v) {
      if (v is Map || v is List) {
        if (v is List) put(k.toLowerCase(), v);
        return;
      }
      put(k.toLowerCase(), v);
    });

    Map<String, dynamic>? nested(String key) {
      final value = raw[key];
      return value is Map ? value.cast<String, dynamic>() : null;
    }

    final ws = nested('ws-opts');
    if (ws != null) {
      put('path', ws['path']);
      put('ed', ws['max-early-data']);
      put('eh', ws['early-data-header-name']);
      final headers = ws['headers'];
      if (headers is Map) {
        for (final entry in headers.entries) {
          if (entry.key.toString().toLowerCase() == 'host') {
            put('host', entry.value);
          }
        }
      }
    }
    final http = nested('http-opts') ?? nested('h2-opts');
    if (http != null) {
      put('method', http['method']);
      final path = http['path'];
      put('path', path is List && path.isNotEmpty ? path.first : path);
      // у h2-opts host полем, у http-opts только заголовком (HTTPOptions в adapter/outbound/vmess.go)
      var host = http['host'] ?? http['Host'];
      final headers = http['headers'];
      if (host == null && headers is Map) {
        for (final entry in headers.entries) {
          if (entry.key.toString().toLowerCase() == 'host') host = entry.value;
        }
      }
      put('host', host is List && host.isNotEmpty ? host.first : host);
    }
    final grpc = nested('grpc-opts');
    if (grpc != null) put('servicename', grpc['grpc-service-name']);
    final reality = nested('reality-opts');
    if (reality != null) {
      put('pbk', reality['public-key']);
      put('sid', reality['short-id']);
      // spx не пишем: у Clash такого поля нет, раньше сюда уезжал флаг support-x25519mlkem768
    }
    final xhttp = nested('xhttp-opts');
    if (xhttp != null) {
      put('path', xhttp['path']);
      put('host', xhttp['host']);
      put('mode', xhttp['mode']);
    }
    final ech = nested('ech-opts');
    if (ech != null) put('ech', ech['config']);
    final plugin = nested('plugin-opts');
    if (plugin != null) {
      final name = text(raw['plugin']);
      if (name.isNotEmpty) {
        final parts = <String>[
          name == 'obfs' ? 'obfs-local' : name,
          if (name == 'obfs') ...[
            if (text(plugin['mode']).isNotEmpty) 'obfs=${text(plugin['mode'])}',
            if (text(plugin['host']).isNotEmpty)
              'obfs-host=${text(plugin['host'])}',
          ] else ...[
            if (plugin['tls'] == true) 'tls',
            if (text(plugin['mode']).isNotEmpty) 'mode=${text(plugin['mode'])}',
            if (text(plugin['host']).isNotEmpty) 'host=${text(plugin['host'])}',
            if (text(plugin['path']).isNotEmpty) 'path=${text(plugin['path'])}',
          ],
        ];
        // не put: в plugin уже лежит имя, а нужна вся строка
        if (parts.length > 1) map['plugin'] = parts.join(';');
      }
    }

    put('fp', raw['client-fingerprint']);
    put('sni', raw['servername']);
    return map;
  }

  // битый узел (server: 82164024@ca.tronsg.com в публичном списке) ронял Uri, а с ним и всю подписку
  static String? _proxyMapToUri(Map<String, dynamic> raw) {
    try {
      return _proxyMapToUriOrThrow(raw);
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  static String? _proxyMapToUriOrThrow(Map<String, dynamic> raw) {
    final map = _flattenClashProxy(raw);

    String pick(List<String> keys) {
      for (final k in keys) {
        final v = map[k];
        if (v != null && v.isNotEmpty) return v;
      }
      return '';
    }

    final type = pick(['type', 'protocol']).toLowerCase();
    final host = pick(['server', 'address', 'add', 'host']);
    final port = int.tryParse(pick(['port', 'server_port'])) ?? 0;
    final name = pick(['name', 'ps', 'remark', 'remarks']);
    final fragment = name.isNotEmpty ? '#${Uri.encodeComponent(name)}' : '';

    if (type == 'vmess' ||
        (type.isEmpty &&
            map.containsKey('uuid') &&
            map.containsKey('cipher'))) {
      final id = pick(['uuid', 'id']);
      if (host.isEmpty || port <= 0 || id.isEmpty) return null;
      final query = {
        ..._clashTransportQuery(pick),
        ..._clashSecurityQuery(pick),
      };
      if (query['security'] == 'reality') return null;
      // security у vmess бывает шифром (auto, aes-128-gcm), поэтому TLS сперва по tls
      query['security'] = _normalizeTlsValue(pick(['tls', 'security']));
      final header = pick(['header', 'header_type']);
      if (header.isNotEmpty && header != 'none') {
        query.putIfAbsent('headerType', () => header);
      }
      return vmessJsonLink(
        name: name,
        host: host,
        port: port,
        uuid: id,
        alterId: int.tryParse(pick(['alterid', 'alter_id', 'aid'])) ?? 0,
        cipher: pick(['cipher', 'scy']),
        query: query,
      );
    }

    if (type == 'vless') {
      final id = pick(['uuid', 'id']);
      if (host.isEmpty || port <= 0 || id.isEmpty) return null;
      final query = <String, String>{
        ..._clashTransportQuery(pick),
        ..._clashSecurityQuery(pick),
      };
      final uri = Uri(
        scheme: 'vless',
        userInfo: id,
        host: host,
        port: port,
        queryParameters: query.isEmpty ? null : query,
        fragment: name,
      );
      return uri.toString();
    }

    if (type == 'trojan') {
      final password = pick(['password', 'passwd', 'pass']);
      if (host.isEmpty || port <= 0 || password.isEmpty) return null;
      final query = <String, String>{
        ..._clashTransportQuery(pick),
        ..._clashSecurityQuery(pick, defaultSecurity: 'tls'),
      };
      final uri = Uri(
        scheme: 'trojan',
        userInfo: userInfoForUri(password),
        host: host,
        port: port,
        queryParameters: query.isEmpty ? null : query,
        fragment: name,
      );
      return uri.toString();
    }

    if (type == 'ss' || type == 'shadowsocks') {
      final cipher = pick(['cipher', 'method']);
      final password = pick(['password', 'passwd', 'pass']);
      if (host.isEmpty || port <= 0 || cipher.isEmpty || password.isEmpty) {
        return null;
      }
      final userInfo = base64Url
          .encode(utf8.encode('$cipher:$password'))
          .replaceAll('=', '');
      final query = <String, String>{
        if (pick(['plugin']).isNotEmpty) 'plugin': pick(['plugin']),
        if (pick(['udp-over-tcp']).toLowerCase() == 'true') 'uot': '1',
        if (pick(['udp-over-tcp-version']).isNotEmpty)
          'udp-over-tcp-version': pick(['udp-over-tcp-version']),
      };
      final tail = query.isEmpty ? '' : '?${Uri(queryParameters: query).query}';
      return 'ss://$userInfo@$host:$port$tail$fragment';
    }

    if (type == 'ssr' || type == 'shadowsocksr') {
      final cipher = pick(['cipher', 'method']);
      final password = pick(['password', 'passwd', 'pass']);
      final obfs = pick(['obfs']);
      final ssrProtocol = pick(['protocol']);
      if (host.isEmpty ||
          port <= 0 ||
          cipher.isEmpty ||
          password.isEmpty ||
          obfs.isEmpty ||
          ssrProtocol.isEmpty) {
        return null;
      }
      return SsrLink(
        host: host,
        port: port,
        protocol: ssrProtocol,
        method: cipher,
        obfs: obfs,
        password: password,
        obfsParam: pick(['obfs-param', 'obfsparam']),
        protocolParam: pick(['protocol-param', 'protoparam']),
        remarks: name,
      ).encode();
    }

    if (type == 'tuic') {
      final uuid = pick(['uuid']);
      final token = pick(['token']);
      final password = pick(['password']);
      final userInfo = uuid.isNotEmpty
          ? '${Uri.encodeComponent(uuid)}:${Uri.encodeComponent(password)}'
          : Uri.encodeComponent(token);
      if (host.isEmpty || port <= 0 || (uuid.isEmpty && token.isEmpty)) {
        return null;
      }
      final query = <String, String>{
        if (pick(['sni', 'servername']).isNotEmpty)
          'sni': pick(['sni', 'servername']),
        if (pick(['alpn']).isNotEmpty) 'alpn': pick(['alpn']),
        if (pick(['congestion-controller']).isNotEmpty)
          'congestion_control': pick(['congestion-controller']),
        if (pick(['udp-relay-mode']).isNotEmpty)
          'udp_relay_mode': pick(['udp-relay-mode']),
        if (pick(['disable-sni']).toLowerCase() == 'true') 'disable_sni': '1',
      };
      return Uri(
        scheme: 'tuic',
        userInfo: userInfo,
        host: host,
        port: port,
        queryParameters: query.isEmpty ? null : query,
        fragment: name.isEmpty ? null : name,
      ).toString();
    }

    if (type == 'anytls') {
      final password = pick(['password', 'passwd', 'pass']);
      if (host.isEmpty || port <= 0 || password.isEmpty) return null;
      final query = <String, String>{
        if (pick(['sni', 'servername']).isNotEmpty)
          'sni': pick(['sni', 'servername']),
        if (pick(['alpn']).isNotEmpty) 'alpn': pick(['alpn']),
        if (pick(['client-fingerprint']).isNotEmpty)
          'fp': pick(['client-fingerprint']),
        // у anytls пин сертификата зовётся hpkp
        if (pick(['fingerprint']).isNotEmpty) 'hpkp': pick(['fingerprint']),
      };
      return Uri(
        scheme: 'anytls',
        userInfo: userInfoForUri(password),
        host: host,
        port: port,
        queryParameters: query.isEmpty ? null : query,
        fragment: name.isEmpty ? null : name,
      ).toString();
    }

    if (type == 'mieru') {
      final username = pick(['username']);
      final password = pick(['password', 'passwd', 'pass']);
      final transport = pick(['transport']);
      final portRange = pick(['port-range']);
      if (host.isEmpty ||
          username.isEmpty ||
          transport.isEmpty ||
          (port <= 0 && portRange.isEmpty)) {
        return null;
      }
      final query = <String, String>{
        'port': portRange.isNotEmpty ? portRange : '$port',
        'protocol': transport,
        if (pick(['multiplexing']).isNotEmpty)
          'multiplexing': pick(['multiplexing']),
        if (pick(['handshake-mode']).isNotEmpty)
          'handshake-mode': pick(['handshake-mode']),
        if (pick(['traffic-pattern']).isNotEmpty)
          'traffic-pattern': pick(['traffic-pattern']),
      };
      return Uri(
        scheme: 'mierus',
        userInfo:
            '${Uri.encodeComponent(username)}:'
            '${Uri.encodeComponent(password)}',
        host: host,
        queryParameters: query,
        fragment: name.isEmpty ? null : name,
      ).toString();
    }

    // hysteria у Clash всегда первая версия, у второй свой тип
    if (type == 'hysteria') return null;
    if (type == 'hysteria2' || type == 'hy2') {
      final auth = pick(['auth', 'password', 'psk', 'auth_str', 'auth-str']);
      if (host.isEmpty || port <= 0 || auth.isEmpty) return null;
      const scheme = 'hy2';
      // hysteria-аутбаунд xray 26+ принимает только version 2
      final query = <String, String>{'auth': auth, 'version': '2'};
      final sni = pick(['sni', 'servername', 'server_name']);
      if (sni.isNotEmpty) query['sni'] = sni;
      final insecure = pick([
        'insecure',
        'skip-cert-verify',
        'allow_insecure',
      ]).toLowerCase();
      if (insecure == '1' || insecure == 'true') query['insecure'] = '1';
      final obfs = pick(['obfs']);
      if (obfs.isNotEmpty) query['obfs'] = obfs;
      final obfsPass = pick(['obfs-password', 'obfs_password', 'obfspassword']);
      if (obfsPass.isNotEmpty) query['obfs-password'] = obfsPass;
      final alpn = pick(['alpn']);
      if (alpn.isNotEmpty) query['alpn'] = alpn;
      final up = pick(['up', 'upmbps']);
      if (up.isNotEmpty) query['up'] = up;
      final down = pick(['down', 'downmbps']);
      if (down.isNotEmpty) query['down'] = down;
      final pin = pick(['pinSHA256', 'pinsha256', 'fingerprint']);
      if (pin.isNotEmpty) query['pinSHA256'] = pin;
      final ports = pick(['ports']);
      if (ports.isNotEmpty) query['mport'] = ports;
      final hop = pick(['hop-interval']);
      if (hop.isNotEmpty) query['hop-interval'] = hop;
      final uri = Uri(
        scheme: scheme,
        host: host,
        port: port,
        queryParameters: query,
        fragment: name.isNotEmpty ? name : null,
      );
      return uri.toString();
    }

    return null;
  }

  // type у Clash называет протокол узла, в транспорт он не годится
  static Map<String, String> _clashTransportQuery(
    String Function(List<String>) pick,
  ) {
    final query = <String, String>{};
    final network = pick(['network', 'net']);
    if (network.isNotEmpty) query['type'] = network;
    final path = pick(['path']);
    if (path.isNotEmpty) query['path'] = path;
    final wsHost = pick(['host']);
    if (wsHost.isNotEmpty) query['host'] = wsHost;
    final serviceName = pick(['servicename', 'grpc-service-name']);
    if (serviceName.isNotEmpty) query['serviceName'] = serviceName;
    final mode = pick(['mode']);
    if (mode.isNotEmpty) query['mode'] = mode;
    // network: http у Clash задаёт маскировку поверх tcp, в ссылке ей соответствуют tcp и headerType=http
    if (network.toLowerCase() == 'http') {
      query['type'] = 'tcp';
      query['headerType'] = 'http';
      final method = pick(['method']);
      if (method.isNotEmpty) query['method'] = method;
    }
    final ed = pick(['ed', 'max-early-data']);
    if (ed.isNotEmpty) query['ed'] = ed;
    final eh = pick(['eh', 'early-data-header-name']);
    if (eh.isNotEmpty) query['eh'] = eh;
    return query;
  }

  static Map<String, String> _clashSecurityQuery(
    String Function(List<String>) pick, {
    String defaultSecurity = '',
  }) {
    final query = <String, String>{};
    final pbk = pick(['pbk', 'public-key']);
    final security = pick(['security', 'tls']);
    final normalized = security.isNotEmpty
        ? _normalizeTlsValue(security)
        : defaultSecurity;
    if (pbk.isNotEmpty) {
      query['security'] = 'reality';
      query['pbk'] = pbk;
      final sid = pick(['sid', 'short-id']);
      if (sid.isNotEmpty) query['sid'] = sid;
    } else if (normalized.isNotEmpty) {
      query['security'] = normalized;
    }
    final sni = pick(['sni', 'servername']);
    if (sni.isNotEmpty) query['sni'] = sni;
    final fp = pick(['fp', 'client-fingerprint']);
    if (fp.isNotEmpty) query['fp'] = fp;
    final flow = pick(['flow']);
    if (flow.isNotEmpty) query['flow'] = flow;
    final alpn = pick(['alpn']);
    if (alpn.isNotEmpty) query['alpn'] = alpn;
    // fingerprint у Clash хранит пин сертификата, а отпечаток uTLS лежит в client-fingerprint
    final pin = pick(['fingerprint']);
    if (pin.isNotEmpty) query['pcs'] = pin;
    final verify = pick(['name-cert-verify']);
    if (verify.isNotEmpty) query['vcn'] = verify;
    final ech = pick(['ech']);
    if (ech.isNotEmpty) query['ech'] = ech;
    return query;
  }

  static String _normalizeTlsValue(String raw) {
    final v = raw.toLowerCase();
    if (v == '1' || v == 'true' || v == 'tls') return 'tls';
    if (v == 'reality') return 'reality';
    return 'none';
  }

  static List<String>? extractConfigsFromHtml(String html) {
    final candidates = <String>[];

    final blockMatches = RegExp(
      r'<(?:pre|code|textarea)[^>]*>([\s\S]*?)</(?:pre|code|textarea)>',
      caseSensitive: false,
    ).allMatches(html);
    for (final m in blockMatches) {
      final v = m.group(1);
      if (v != null && v.trim().isNotEmpty) candidates.add(v);
    }

    final scriptMatches = RegExp(
      r'<script[^>]*>([\s\S]*?)</script>',
      caseSensitive: false,
    ).allMatches(html);
    for (final m in scriptMatches) {
      final v = m.group(1);
      if (v != null && v.trim().isNotEmpty) candidates.add(v);
    }

    final jsMatches = RegExp(
      r'''(?:payload|subscription|subdata|content|data)\s*[:=]\s*["']([\s\S]*?)["']''',
      caseSensitive: false,
    ).allMatches(html);
    for (final m in jsMatches) {
      final v = m.group(1);
      if (v != null && v.trim().isNotEmpty) candidates.add(v);
    }

    final base64Like = RegExp(
      r'[A-Za-z0-9+/_=\r\n-]{300,}',
      caseSensitive: false,
    ).allMatches(html);
    for (final m in base64Like) {
      final v = m.group(0);
      if (v != null && v.trim().isNotEmpty) candidates.add(v);
    }

    candidates.add(html);

    for (final raw in candidates) {
      final variants = <String>{
        raw,
        _htmlUnescape(raw),
        _jsUnescape(_htmlUnescape(raw)),
      };
      for (final variant in variants) {
        final cleaned = variant.replaceAll(RegExp(r'<[^>]+>'), ' ').trim();
        if (cleaned.isEmpty) continue;

        final directLinks = _extractUriLinks(cleaned);
        if (directLinks.isNotEmpty) return directLinks;

        // без рекурсивного parseBody: в релизе он давал stack overflow
        final configs = _parseBodyNoRecursion(cleaned);
        if (configs.isNotEmpty) return configs;
      }
    }
    return null;
  }

  static List<String> _parseBodyNoRecursion(String content) {
    final original = content.trim();

    final custom = _extractCustomConfigs(original);
    if (custom.isNotEmpty) return custom;

    final singleDecoded = tryDecodeBase64Flexible(original);
    if (singleDecoded != null && singleDecoded.trim().isNotEmpty) {
      final configs = _extractUrisDirectly(singleDecoded);
      if (configs.isNotEmpty) return configs;
      final customDecoded = _extractCustomConfigs(singleDecoded);
      if (customDecoded.isNotEmpty) return customDecoded;
    }

    if (singleDecoded != null) {
      final doubleDecoded = tryDecodeBase64Flexible(singleDecoded);
      if (doubleDecoded != null && doubleDecoded.trim().isNotEmpty) {
        final configs = _extractUrisDirectly(doubleDecoded);
        if (configs.isNotEmpty) return configs;
      }
    }

    final directConfigs = _extractUrisDirectly(original);
    if (directConfigs.isNotEmpty) return directConfigs;

    return const [];
  }

  static List<String> _extractUrisDirectly(String text) {
    final lines = LineSplitter.split(text)
        .map((l) => l.trim())
        .where(
          (l) => l.isNotEmpty && _isValidConfig(l) && !_isMetadataConfig(l),
        )
        .toList();
    return lines;
  }

  static List<String> extractSubscriptionUrlsFromHtml(
    String html, {
    required String baseUrl,
  }) {
    final base = Uri.tryParse(baseUrl);
    if (base == null) return const [];

    final found = <String>{};
    final patterns = <RegExp>[
      RegExp(
        r'''(?:href|src|data-url)\s*=\s*["']([^"']+)["']''',
        caseSensitive: false,
      ),
      RegExp(
        r'''(?:fetch|axios\.get|open)\s*\(\s*["']([^"']+)["']''',
        caseSensitive: false,
      ),
      RegExp(
        r'''(?:window\.)?location(?:\.href)?\s*=\s*["']([^"']+)["']''',
        caseSensitive: false,
      ),
    ];

    for (final re in patterns) {
      for (final m in re.allMatches(html)) {
        final raw = (m.group(1) ?? '').trim();
        if (raw.isEmpty) continue;
        final unescaped = _htmlUnescape(raw).replaceAll(r'\/', '/');
        final resolved = base.resolve(unescaped).toString();
        final lower = resolved.toLowerCase();
        if (lower.endsWith('.js') ||
            lower.endsWith('.css') ||
            lower.endsWith('.png') ||
            lower.endsWith('.jpg') ||
            lower.endsWith('.svg') ||
            lower.contains('/login') ||
            lower.contains('/register')) {
          continue;
        }
        if (lower.contains('/sub') ||
            lower.contains('token=') ||
            lower.contains('subscription') ||
            lower.contains('/api/')) {
          found.add(resolved);
        }
      }
    }

    return found.take(8).toList();
  }

  static String _htmlUnescape(String input) {
    var s = input
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");

    s = s.replaceAllMapped(RegExp(r'&#(x?[0-9A-Fa-f]+);'), (m) {
      final token = m.group(1)!;
      final code = token.startsWith('x') || token.startsWith('X')
          ? int.tryParse(token.substring(1), radix: 16)
          : int.tryParse(token);
      if (code == null) return m.group(0)!;
      return String.fromCharCode(code);
    });
    return s;
  }

  static String _jsUnescape(String input) {
    var s = input
        .replaceAll(r'\/', '/')
        .replaceAll(r'\"', '"')
        .replaceAll(r"\'", "'")
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\t', '\t');

    s = s.replaceAllMapped(RegExp(r'\\u([0-9A-Fa-f]{4})'), (m) {
      final code = int.tryParse(m.group(1)!, radix: 16);
      return code == null ? m.group(0)! : String.fromCharCode(code);
    });
    return s;
  }

  static List<String> _extractUriLinks(String text) {
    // пробел внутри ссылки допустим (имя сервера во fragment), режем по переводам строк.
    // lookbehind по символам схемы: иначе wss://host из html матчился как ss://host
    final matches = RegExp(
      r'''(?<![A-Za-z0-9+.\-])(?:vless|vmess|trojan|ss|ssr|hysteria2?|hy2|tuic|anytls|mierus|socks5h|socks5|socks)://(?:(?!(?:vless|vmess|trojan|ssr|ss|hysteria2?|hy2|tuic|anytls|mierus|socks5h|socks5|socks)://)[^\r\n<>"'])+''',
      caseSensitive: false,
    ).allMatches(text);
    final links = <String>[];
    for (final m in matches) {
      final raw = (m.group(0) ?? '').trim();
      if (raw.isEmpty) continue;
      final normalized = raw
          .replaceAll('&amp;', '&')
          .replaceAll('&#38;', '&')
          .replaceAll('\\/', '/');
      if (_isValidConfig(normalized)) {
        links.addAll(MieruLink.expand(normalized));
      }
    }
    return links.toSet().toList();
  }

  static String parsableUri(String raw) {
    final lower = raw.trimLeft().toLowerCase();
    if (!lower.startsWith('hysteria2://') &&
        !lower.startsWith('hy2://') &&
        !lower.startsWith('hysteria://')) {
      return raw;
    }
    return HysteriaLinkParams.splitPorts(raw).$1;
  }

  static bool _isValidConfig(String s) {
    final lower = s.toLowerCase();
    // hysteria v1 не собирает ни одно ядро, а под общей схемой она выглядит рабочей
    if (HysteriaLinkParams.isV1(s)) return false;
    return lower.startsWith('vless://') ||
        lower.startsWith('vmess://') ||
        lower.startsWith('trojan://') ||
        lower.startsWith('ss://') ||
        lower.startsWith('ssr://') ||
        lower.startsWith('hysteria://') ||
        lower.startsWith('hysteria2://') ||
        lower.startsWith('hy2://') ||
        lower.startsWith('tuic://') ||
        lower.startsWith('anytls://') ||
        lower.startsWith('mierus://') ||
        SocksLink.tryParse(s) != null;
  }

  static bool _isMetadataConfig(String raw) {
    try {
      final uri = Uri.parse(raw);
      final host = uri.host.toLowerCase();
      if ((host == '0.0.0.0' || host == '::' || host == '::1') &&
          uri.port <= 1) {
        return true;
      }
    } on Object {
      // не разобралось, смотрим по имени
    }

    final name = _extractConfigName(raw);
    if (name == null || name.isEmpty) return false;
    final n = name.toLowerCase();

    const markers = <String>[
      'пользователь',
      'осталось дней',
      'серверов доступно',
      'оплата',
      'трафик',
      'до:',
      'remaining',
      'days left',
      'expire',
      'expires',
      'traffic',
      'user:',
    ];
    for (final m in markers) {
      if (n.contains(m)) return true;
    }
    return false;
  }

  static bool _isHwidGateConfig(String raw) {
    final name = _extractConfigName(raw)?.toLowerCase() ?? '';
    if (name.isEmpty) return false;
    return name.contains('hwid') ||
        name.contains('turn on hwid') ||
        name.contains('enable hwid') ||
        name.contains('bind hwid');
  }

  static String? _detectProviderGateMessage(List<String> lines) {
    final names = <String>[];
    var hasNullRouteEndpoint = false;
    for (final line in lines) {
      if (!_isValidConfig(line)) continue;
      try {
        final uri = Uri.parse(line);
        final host = uri.host.toLowerCase();
        if ((host == '0.0.0.0' || host == '::' || host == '::1') &&
            uri.port <= 1) {
          hasNullRouteEndpoint = true;
        }
      } on Object {
        // не разобралось
      }
      final name = (_extractConfigName(line) ?? '').toLowerCase();
      if (name.isNotEmpty) names.add(name);
    }
    if (names.isEmpty) return null;
    final joined = names.join(' | ');

    final trafficMarkers = <String>[
      'traffic limit reached',
      'quota exceeded',
      'out of traffic',
      'no traffic left',
      'лимит трафика',
      'трафик исчерпан',
      'закончился трафик',
      'достигнут лимит трафика',
      'трафик закончился',
    ];
    for (final marker in trafficMarkers) {
      if (joined.contains(marker)) {
        return 'Provider reports traffic limit reached for this subscription. '
            'Renew your plan or wait until quota resets.';
      }
    }

    final expiredMarkers = <String>[
      'subscription expired',
      'expired',
      'account expired',
      'истек',
      'истёк',
      'подписка истекла',
      'подписка истек',
    ];
    for (final marker in expiredMarkers) {
      if (joined.contains(marker)) {
        return 'Provider reports this subscription has expired.';
      }
    }

    final remnawaveMarkers = <String>[
      'remnawave',
      '→ remnawave',
      'service link',
      'service links',
      'null route',
    ];
    final hasRemnawaveMarker = remnawaveMarkers.any(joined.contains);
    final noHostsMarkers = <String>[
      'did you forget to add hosts',
      'no hosts found',
      'check hosts tab',
      'hosts tab',
    ];
    final hasNoHostsMarker = noHostsMarkers.any(joined.contains);
    if (hasNullRouteEndpoint && hasNoHostsMarker) {
      return 'Provider returned service links because no hosts are configured for this subscription. '
          'Open provider panel and add/assign hosts in the Hosts tab.';
    }
    if (hasNullRouteEndpoint && hasRemnawaveMarker) {
      return 'Provider returned service links (0.0.0.0:1) instead of real nodes. '
          'This usually means HWID is required but not bound/approved yet in provider panel.';
    }
    return null;
  }

  static String? _extractConfigName(String raw) {
    try {
      if (CustomXrayConfig.looksLikeJson(raw)) {
        final remarks = CustomXrayConfig.tryParse(raw)?.remarks ?? '';
        return remarks.isEmpty ? null : remarks;
      }

      if (raw.toLowerCase().startsWith('ssr://')) {
        final remarks = SsrLink.tryParse(raw)?.remarks.trim() ?? '';
        if (remarks.isNotEmpty) return remarks;
      }

      if (raw.startsWith('vmess://')) {
        final payload = raw.substring('vmess://'.length).trim();
        final decoded = tryDecodeBase64Flexible(payload);
        if (decoded != null) {
          final j = jsonDecode(decoded);
          if (j is Map<String, dynamic>) {
            final ps = (j['ps'] ?? '').toString().trim();
            if (ps.isNotEmpty) return ps;
          }
        }
      }

      final uri = Uri.parse(parsableUri(raw));
      final fragment = uri.fragment.trim();
      if (fragment.isEmpty) return null;
      return Uri.decodeComponent(fragment).trim();
    } on Object {
      return null;
    }
  }

  static ({int? usedBytes, int? totalBytes, DateTime? expiresAt})
  extractMetaFromBody(String content) {
    final remarks = <String>{};
    final original = content.trim();
    final candidates = <String>{original};

    final singleDecoded = tryDecodeBase64Flexible(original);
    if (singleDecoded != null && singleDecoded.trim().isNotEmpty) {
      candidates.add(singleDecoded);
      final doubleDecoded = tryDecodeBase64Flexible(singleDecoded);
      if (doubleDecoded != null && doubleDecoded.trim().isNotEmpty) {
        candidates.add(doubleDecoded);
      }
    }

    for (final candidate in candidates) {
      for (final line in LineSplitter.split(
        candidate,
      ).map((e) => e.trim()).where((e) => e.isNotEmpty)) {
        if (!_isValidConfig(line)) continue;
        final name = _extractConfigName(line);
        if (name != null && name.isNotEmpty) remarks.add(name);
      }
    }

    int? usedBytes;
    int? totalBytes;
    DateTime? expiresAt;

    for (final remark in remarks) {
      final dateMatch = RegExp(
        r'(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})',
      ).firstMatch(remark);
      if (dateMatch != null && expiresAt == null) {
        final d = int.tryParse(dateMatch.group(1)!);
        final m = int.tryParse(dateMatch.group(2)!);
        var y = int.tryParse(dateMatch.group(3)!);
        if (d != null && m != null && y != null) {
          if (y < 100) y += 2000;
          try {
            expiresAt = DateTime(y, m, d, 23, 59, 59);
          } on Object {
            // дата битая
          }
        }
      }

      final trafficMatch = RegExp(
        r'(\d+(?:[.,]\d+)?)\s*(kb|mb|gb|tb|кб|мб|гб|тб)\s*[/|]\s*(\d+(?:[.,]\d+)?|∞|infinity|unlimited)\s*(kb|mb|gb|tb|кб|мб|гб|тб)?',
        caseSensitive: false,
      ).firstMatch(remark);
      if (trafficMatch != null) {
        usedBytes ??= _toBytes(trafficMatch.group(1), trafficMatch.group(2));
        final totalRaw = (trafficMatch.group(3) ?? '').toLowerCase();
        if (totalRaw == '∞' ||
            totalRaw == 'infinity' ||
            totalRaw == 'unlimited') {
          totalBytes ??= 0;
        } else {
          totalBytes ??= _toBytes(
            trafficMatch.group(3),
            trafficMatch.group(4) ?? trafficMatch.group(2),
          );
        }
      } else {
        final usedOnly = RegExp(
          r'(?:used|usage|трафик|израсходовано)\D*(\d+(?:[.,]\d+)?)\s*(kb|mb|gb|tb|кб|мб|гб|тб)',
          caseSensitive: false,
        ).firstMatch(remark);
        if (usedOnly != null) {
          usedBytes ??= _toBytes(usedOnly.group(1), usedOnly.group(2));
        }
      }
    }

    return (usedBytes: usedBytes, totalBytes: totalBytes, expiresAt: expiresAt);
  }

  static int? _toBytes(String? value, String? unitRaw) {
    if (value == null || unitRaw == null) return null;
    final v = double.tryParse(value.replaceAll(',', '.'));
    if (v == null) return null;
    final unit = unitRaw.toLowerCase();
    final multiplier = switch (unit) {
      'kb' || 'кб' => 1024.0,
      'mb' || 'мб' => 1024.0 * 1024.0,
      'gb' || 'гб' => 1024.0 * 1024.0 * 1024.0,
      'tb' || 'тб' => 1024.0 * 1024.0 * 1024.0 * 1024.0,
      _ => 0.0,
    };
    if (multiplier == 0.0) return null;
    return (v * multiplier).round();
  }
}
