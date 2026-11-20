import 'dart:convert';

// json, а не ссылка AEAD: в ней нет aid. REALITY у vmess не соберёт ни одно ядро, такой узел отбрасывают до вызова
String vmessJsonLink({
  required String name,
  required String host,
  required int port,
  required String uuid,
  required int alterId,
  required String cipher,
  required Map<String, String> query,
}) {
  // HTTP/2 в json v2rayN называется h2, в ссылке http
  final net = switch (query['type']) {
    null || '' => 'tcp',
    'http' => 'h2',
    final String type => type,
  };
  // имя gRPC-сервиса и ранние данные v2rayN кладёт в path; ранние данные с другим заголовком не переносим:
  // сервер примет соединение и без них, а посланные не туда съели бы первый пакет
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
