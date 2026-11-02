import 'dart:convert';
import 'dart:io';

import 'connections_service.dart';

typedef MihomoGroupState = ({String type, String? now, List<String> all});

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
          ),
    };
  }

  static Future<bool> select(String group, String member) async =>
      await _call(
        'PUT',
        '/proxies/${Uri.encodeComponent(group)}',
        body: jsonEncode({'name': member}),
      ) !=
      null;

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
