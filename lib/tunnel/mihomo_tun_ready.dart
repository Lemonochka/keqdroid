import 'dart:convert';
import 'dart:io';

// API mihomo открывает раньше TUN (hub.ApplyConfig: applyRoute, потом executor), и пока адаптер создаётся,
// tun в /configs пустой: enable false без device. замер в ВМ 29.10.2026: 135 мс пусто, 499 мс enable true
enum MihomoTunState { pending, up, failed }

MihomoTunState mihomoTunState({required String coreOutput, Object? configs}) {
  // после неё ядро живёт дальше без TUN (listener.ReCreateTun), выход ждать бессмысленно
  if (coreOutput.contains('Start TUN listening error')) {
    return MihomoTunState.failed;
  }
  if (coreOutput.contains('Tun adapter listening at')) return MihomoTunState.up;
  final tun = configs is Map ? configs['tun'] : null;
  if (tun is! Map) return MihomoTunState.pending;
  if (tun['enable'] == true) return MihomoTunState.up;
  // device появляется, только когда попытка закончилась (LastTunConf пишется на выходе из ReCreateTun)
  return (tun['device']?.toString() ?? '').isEmpty
      ? MihomoTunState.pending
      : MihomoTunState.failed;
}

Future<Object?> fetchMihomoConfigs(
  int port,
  String secret, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final client = HttpClient()
    ..connectionTimeout = timeout
    ..findProxy = (_) => 'DIRECT';
  try {
    final request =
        await client.get('127.0.0.1', port, '/configs').timeout(timeout);
    if (secret.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
    }
    final response = await request.close().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      return null;
    }
    return jsonDecode(
      await response.transform(utf8.decoder).join().timeout(timeout),
    );
  } on Object {
    return null;
  } finally {
    client.close(force: true);
  }
}
