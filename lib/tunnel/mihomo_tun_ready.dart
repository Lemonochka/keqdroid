import 'dart:convert';
import 'dart:io';

// mihomo открывает API только после попытки TUN (hub.ApplyConfig), и tun.enable там true лишь у адаптера,
// который он поднял сам. адаптер по имени мог остаться от прошлой сессии: так «подключено» висело без туннеля
enum MihomoTunState { pending, up, failed }

MihomoTunState mihomoTunState({required String coreOutput, Object? configs}) {
  // после неё ядро живёт дальше без TUN (listener.ReCreateTun), выход ждать бессмысленно
  if (coreOutput.contains('Start TUN listening error')) {
    return MihomoTunState.failed;
  }
  if (coreOutput.contains('Tun adapter listening at')) return MihomoTunState.up;
  if (configs is! Map) return MihomoTunState.pending;
  final tun = configs['tun'];
  return tun is Map && tun['enable'] == true
      ? MihomoTunState.up
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
