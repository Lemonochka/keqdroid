import 'dart:convert';

import 'proxy_chain.dart';

final _scheme = RegExp(r'^([a-z][a-z0-9+.-]*)://', caseSensitive: false);

// всё, кроме имени: у barry-far/V2ray-Config 15.11.2026 копий под тегами каналов 3582 из 9489,
// и ещё 352 адреса с тем же UUID, но другим SNI или путём, а такие уже разные серверы
String sameServerKeyOf(String config) {
  final s = config.trim();
  if (s.startsWith('{')) return _withoutTopLevel(s, 'remarks') ?? s;
  final scheme = _scheme.firstMatch(s)?[1]!.toLowerCase();
  if (scheme == null || scheme == ProxyChainConfig.scheme) return s;
  final hash = s.indexOf('#');
  final body = hash < 0 ? s : s.substring(0, hash);
  if (scheme == 'vmess') return _vmessWithoutName(body) ?? body;
  return body;
}

// копия с большим rank (выбранная или помеченная человеком) встаёт на место первой
List<String> withoutNameCopies(
  List<String> configs, {
  int Function(String config)? rank,
}) {
  final keys = [for (final c in configs) sameServerKeyOf(c)];
  final best = <String, String>{};
  for (var i = 0; i < configs.length; i++) {
    final current = best[keys[i]];
    if (current == null ||
        (rank != null && rank(configs[i]) > rank(current))) {
      best[keys[i]] = configs[i];
    }
  }
  final seen = <String>{};
  return [
    for (var i = 0; i < configs.length; i++)
      if (seen.add(keys[i])) best[keys[i]]!,
  ];
}

String? _withoutTopLevel(String json, String field) {
  try {
    final decoded = jsonDecode(json);
    if (decoded is Map<String, dynamic> && decoded.containsKey(field)) {
      return jsonEncode({...decoded}..remove(field));
    }
  } on FormatException {
    return null;
  }
  return null;
}

String? _vmessWithoutName(String link) {
  try {
    final payload = link
        .substring('vmess://'.length)
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('-', '+')
        .replaceAll('_', '/');
    final decoded =
        jsonDecode(utf8.decode(base64.decode(base64.normalize(payload))));
    if (decoded is Map<String, dynamic>) {
      return 'vmess://${jsonEncode({...decoded}..remove('ps'))}';
    }
  } on FormatException {
    return null;
  }
  return null;
}
