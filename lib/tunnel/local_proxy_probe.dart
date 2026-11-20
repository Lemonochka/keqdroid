import 'dart:async';
import 'dart:io';

import '../utils/local_vpn_proxy.dart';

final _probeUrl = Uri.parse(
  'http://connectivitycheck.gstatic.com/generate_204',
);

// в TUN у локального входа пароль сессии: без него ядро отвечало 407, и предупреждение
// «ничего не загрузится» было ложным при каждом подключении
Future<({int? status, Object? error})> probeLocalHttpProxy(
  int httpPort, {
  Uri? url,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final client = HttpClient();
  try {
    configureHttpClientForLocalVpnProxy(client, () => httpPort);
    final request = await client.getUrl(url ?? _probeUrl).timeout(timeout);
    final response = await request.close().timeout(timeout);
    await response.drain<void>();
    return (status: response.statusCode, error: null);
  } catch (e) {
    return (status: null, error: e);
  } finally {
    client.close(force: true);
  }
}

bool probeWentThrough(({int? status, Object? error}) result) =>
    result.status == 204 || result.status == 200;
