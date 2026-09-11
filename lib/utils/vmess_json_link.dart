import 'dart:convert';

/// VMess-ссылка v2rayN (base64-json) из параметров в том виде, в каком их
/// несёт ссылка vless: транспорт и TLS запросом.
///
/// Нужна переводам чужих форматов, Clash и sing-box: параметры узла там
/// удобно собирать один раз запросом ссылки, а у vmess-json имена свои. Форма
/// json, а не ссылка AEAD, потому что у неё есть `aid`.
///
/// REALITY у vmess не соберёт ни одно ядро — такой узел вызывающий
/// отбрасывает сам, до этой функции.
String vmessJsonLink({
  required String name,
  required String host,
  required int port,
  required String uuid,
  required int alterId,
  required String cipher,
  required Map<String, String> query,
}) {
  // HTTP/2 json v2rayN зовёт `h2`, ссылка — `http`.
  final net = switch (query['type']) {
    null || '' => 'tcp',
    'http' => 'h2',
    final String type => type,
  };
  // Своих полей для имени gRPC-сервиса и ранних данных у json нет: v2rayN
  // кладёт то и другое в `path`, так их и читают генераторы. Ранние данные из
  // пути оба ядра шлют в Sec-WebSocket-Protocol, а назвать другой заголовок
  // json нечем, — при нём их не переносим: сервер примет соединение и без них,
  // а посланные не туда потеряли бы первый пакет.
  var path = query['path'] ?? '';
  final ed = query['ed'];
  final eh = (query['eh'] ?? '').toLowerCase();
  if (net == 'grpc') {
    path = query['serviceName'] ?? '';
  } else if (ed != null && (eh.isEmpty || eh == 'sec-websocket-protocol')) {
    if (path.isEmpty) path = '/';
    path = '$path${path.contains('?') ? '&' : '?'}ed=$ed';
  }
  final json = <String, String>{
    'v': '2',
    'ps': name,
    'add': host,
    'port': '$port',
    'id': uuid,
    'aid': '$alterId',
    'scy': cipher.isEmpty ? 'auto' : cipher,
    'net': net,
    'type': query['headerType'] ?? 'none',
    'host': query['host'] ?? '',
    'path': path,
    'tls': query['security'] == 'tls' ? 'tls' : '',
    for (final key in const ['sni', 'alpn', 'fp', 'ech', 'pcs', 'vcn'])
      if ((query[key] ?? '').isNotEmpty) key: query[key]!,
  };
  return 'vmess://${base64.encode(utf8.encode(jsonEncode(json)))}';
}
