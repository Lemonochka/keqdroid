import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/tunnel/local_proxy_probe.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

// Локальный вход ядра в режиме TUN: без пароля сессии отвечает 407, с ним
// пропускает проверочный запрос.
Future<HttpServer> _sessionProxy(String user, String pass) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final expected = 'Basic ${base64.encode(utf8.encode('$user:$pass'))}';
  server.listen((req) async {
    final auth = req.headers.value(HttpHeaders.proxyAuthorizationHeader);
    if (auth != expected) {
      req.response
        ..statusCode = HttpStatus.proxyAuthenticationRequired
        ..headers.set(
          HttpHeaders.proxyAuthenticateHeader,
          'Basic realm="proxy"',
        );
    } else {
      req.response.statusCode = HttpStatus.noContent;
    }
    await req.response.close();
  });
  return server;
}

void main() {
  final probeUrl = Uri.parse('http://probe.test/generate_204');

  tearDown(() => Socks5Credentials().init('', ''));

  test('проверка после подключения идёт с паролем сессии и проходит', () async {
    final proxy = await _sessionProxy('keq', 's3cret');
    addTearDown(() => proxy.close(force: true));
    Socks5Credentials().init('keq', 's3cret');

    final result = await probeLocalHttpProxy(proxy.port, url: probeUrl);

    expect(result.status, HttpStatus.noContent);
    expect(probeWentThrough(result), isTrue);
  });

  test('чужой пароль даёт 407, и проверка считается непрошедшей', () async {
    final proxy = await _sessionProxy('keq', 's3cret');
    addTearDown(() => proxy.close(force: true));
    Socks5Credentials().init('keq', 'old');

    final result = await probeLocalHttpProxy(proxy.port, url: probeUrl);

    expect(result.status, HttpStatus.proxyAuthenticationRequired);
    expect(probeWentThrough(result), isFalse);
  });
}
