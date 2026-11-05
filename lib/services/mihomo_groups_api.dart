import 'dart:convert';
import 'dart:io';

import 'connections_service.dart';

typedef MihomoGroupState = ({
  String type,
  String? now,
  List<String> all,
  String? fixed,
});

// API ядра на петле: локальный инбаунд тут не нужен, туннель петлю не трогает
class MihomoGroupsApi {
  static Future<Map<String, MihomoGroupState>?> fetch() async {
    final body = await _call('GET', '/proxies');
    if (body == null) return null;
    final json = jsonDecode(body);
    final proxies = json is Map ? json['proxies'] : null;
    if (proxies is! Map) return null;
    return {
      for (final MapEntry(:key, :value) in proxies.entries)
        if (value is Map && value['all'] is List)
          key.toString(): (
            type: value['type']?.toString().toLowerCase() ?? '',
            now: value['now']?.toString(),
            all: [for (final m in value['all'] as List) m.toString()],
            fixed: switch (value['fixed']?.toString()) {
              final f? when f.isNotEmpty => f,
              _ => null,
            },
          ),
    };
  }

  // узлы proxy-providers в /proxies не попадают (tunnel.Proxies), их пинги лежат в /providers/proxies
  static Future<Map<String, int?>> delays() async {
    final out = <String, int?>{};
    void take(Object? proxy) {
      if (proxy is! Map) return;
      final name = proxy['name']?.toString();
      if (name == null || name.isEmpty) return;
      out[name] = lastDelay(proxy);
    }

    Object? field(String? body, String key) {
      final json = body == null ? null : jsonDecode(body);
      return json is Map ? json[key] : null;
    }

    final own = field(await _call('GET', '/proxies'), 'proxies');
    if (own is Map) own.values.forEach(take);
    final providers =
        field(await _call('GET', '/providers/proxies'), 'providers');
    if (providers is Map) {
      for (final provider in providers.values) {
        final proxies = provider is Map ? provider['proxies'] : null;
        if (proxies is List) proxies.forEach(take);
      }
    }
    return out;
  }

  // неудачная проверка пишется в history с delay 0 (adapter.URLTest)
  static int? lastDelay(Map<dynamic, dynamic> proxy) {
    if (proxy['alive'] == false) return null;
    final history = proxy['history'];
    if (history is! List || history.isEmpty) return null;
    final last = history.last;
    final delay = last is Map ? last['delay'] : null;
    return delay is num && delay > 0 ? delay.toInt() : null;
  }

  // у url-test и fallback PUT закрепляет узел (URLTest.Set), у select просто выбирает
  static Future<bool> select(String group, String member) async =>
      await _call(
        'PUT',
        '/proxies/${Uri.encodeComponent(group)}',
        body: jsonEncode({'name': member}),
      ) !=
      null;

  static Future<bool> unfix(String group) async =>
      await _call('DELETE', '/proxies/${Uri.encodeComponent(group)}') != null;

  static Future<String?> _call(String method, String path, {String? body}) async {
    final port = ConnectionsService.activeClashPort();
    if (port == null) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      // parse, а не Uri.http: имя группы уже в процентах, а ядро снимает их с параметра (getEscapeParam)
      final req = await client
          .openUrl(method, Uri.parse('http://127.0.0.1:$port$path'))
          .timeout(const Duration(seconds: 3));
      final secret = ConnectionsService.activeClashSecret();
      if (secret.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(body);
      }
      final resp = await req.close().timeout(const Duration(seconds: 3));
      final text = await resp.transform(utf8.decoder).join();
      return resp.statusCode >= 200 && resp.statusCode < 300 ? text : null;
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
