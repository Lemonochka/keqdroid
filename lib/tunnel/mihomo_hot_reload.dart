import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/app_logger.dart';

// PUT /configs?force=true (hub/route/configs.go): payload разбирается как файл, ApplyConfig не пересоздаёт TUN
// при том же tun и вход при том же адресе
Future<bool> putMihomoConfig({
  required int port,
  required String secret,
  required String config,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final put = await client
        .openUrl('PUT', Uri.parse('http://127.0.0.1:$port/configs?force=true'))
        .timeout(const Duration(seconds: 3));
    put.headers.contentType = ContentType.json;
    if (secret.isNotEmpty) {
      put.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
    }
    put.add(utf8.encode(jsonEncode({'payload': config})));
    // разбор правил и провайдеров на большом конфиге занимает секунды
    final response = await put.close().timeout(const Duration(seconds: 15));
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 5));
    if (response.statusCode ~/ 100 != 2) {
      AppLogger.instance.warn(
        'mihomo reload refused: HTTP ${response.statusCode} '
        '${body.length > 300 ? body.substring(0, 300) : body}',
      );
      return false;
    }
  } catch (e) {
    AppLogger.instance.warn('mihomo reload failed', error: e);
    client.close(force: true);
    return false;
  }

  // открытые соединения ушли бы дожидаться конца на прежнем сервере
  try {
    final close = await client
        .openUrl('DELETE', Uri.parse('http://127.0.0.1:$port/connections'))
        .timeout(const Duration(seconds: 3));
    if (secret.isNotEmpty) {
      close.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
    }
    final response = await close.close().timeout(const Duration(seconds: 3));
    await response.drain<void>();
  } catch (e) {
    AppLogger.instance.warn(
      'mihomo reload: old connections stay open',
      error: e,
    );
  } finally {
    client.close(force: true);
  }
  return true;
}
