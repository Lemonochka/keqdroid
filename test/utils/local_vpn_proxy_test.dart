import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/local_vpn_proxy.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

/// Прокси-заглушка: отвечает на запрос с абсолютным URI (так HttpClient ходит
/// к http-адресам через прокси) и записывает первую строку запроса.
///
/// С [requireAuth] ведёт себя как локальный инбаунд с включённой
/// аутентификацией: без `Proxy-Authorization` отвечает 407.
class _RecordingProxy {
  _RecordingProxy({this.requireAuth = false});

  final bool requireAuth;
  late final HttpServer _server;
  final requestLines = <String>[];
  final authHeaders = <String?>[];

  int get port => _server.port;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((req) async {
      requestLines.add('${req.method} ${req.requestedUri}');
      final auth = req.headers.value(HttpHeaders.proxyAuthorizationHeader);
      authHeaders.add(auth);
      if (requireAuth && auth == null) {
        req.response
          ..statusCode = HttpStatus.proxyAuthenticationRequired
          ..headers.set(HttpHeaders.proxyAuthenticateHeader, 'Basic realm=""');
        await req.response.close();
        return;
      }
      req.response
        ..headers.contentType = ContentType.text
        ..write('proxied');
      await req.response.close();
    });
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  group('localProxyDirective', () {
    test('null port means direct', () {
      expect(localProxyDirective(null), 'DIRECT');
    });

    test('port becomes an HTTP proxy directive (SOCKS dart:io не понимает)', () {
      expect(localProxyDirective(2081), 'PROXY 127.0.0.1:2081');
    });
  });

  group('configureHttpClientForLocalVpnProxy', () {
    late _RecordingProxy proxy;
    // Порт, который заведомо никто не слушает: прямой запрос обязан
    // упереться в отказ соединения, а не уйти в сеть.
    late int deadPort;
    late String url;

    setUp(() async {
      proxy = _RecordingProxy();
      await proxy.start();
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      deadPort = probe.port;
      await probe.close();
      url = 'http://127.0.0.1:$deadPort/sub';
    });

    tearDown(() => proxy.stop());

    Future<String> fetch(HttpClient client) async {
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close();
      return resp.transform(utf8.decoder).join();
    }

    test('resolver с портом уводит запрос в прокси', () async {
      final client = HttpClient();
      configureHttpClientForLocalVpnProxy(client, () => proxy.port);
      addTearDown(() => client.close(force: true));

      expect(await fetch(client), 'proxied');
      expect(proxy.requestLines, ['GET $url']);
    });

    test('resolver с null оставляет запрос прямым', () async {
      final client = HttpClient();
      configureHttpClientForLocalVpnProxy(client, () => null);
      addTearDown(() => client.close(force: true));

      await expectLater(fetch(client), throwsA(isA<SocketException>()));
      expect(proxy.requestLines, isEmpty);
    });

    test('решение принимается на каждый запрос, а не при сборке клиента',
        () async {
      // Ровно тот случай, ради которого резолвер и появился: сервис подписок
      // живёт всё время работы приложения, а VPN за это время включают.
      int? port;
      final client = HttpClient();
      configureHttpClientForLocalVpnProxy(client, () => port);
      addTearDown(() => client.close(force: true));

      await expectLater(fetch(client), throwsA(isA<SocketException>()));
      expect(proxy.requestLines, isEmpty);

      port = proxy.port; // «подключили VPN»
      expect(await fetch(client), 'proxied');
      expect(proxy.requestLines, ['GET $url']);
    });
  });

  group('прокси с аутентификацией', () {
    // Креды регистрируются внутри findProxy, а не при создании клиента:
    // на Android после пересоздания изолята они приезжают из нативного
    // сервиса позже. Проверяем, что «позже» всё равно срабатывает — на этом
    // же пути живёт проверка обновлений.
    test('запрос доходит с Proxy-Authorization', () async {
      final proxy = _RecordingProxy(requireAuth: true);
      await proxy.start();
      addTearDown(proxy.stop);

      final client = HttpClient();
      configureHttpClientForLocalVpnProxy(
        client,
        () => proxy.port,
        username: 'keq',
        password: 's3cret',
      );
      addTearDown(() => client.close(force: true));

      final req = await client.getUrl(Uri.parse('http://example.test/sub'));
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();

      expect(body, 'proxied');
      expect(resp.statusCode, 200);
      // первый запрос ушёл без креда, 407 → повтор уже с ним
      expect(
        proxy.authHeaders.last,
        'Basic ${base64.encode(utf8.encode('keq:s3cret'))}',
      );
    });

    test('креды из синглтона, появившиеся после сборки клиента, применяются',
        () async {
      // Ровно случай Android: VpnService пережил пересоздание Flutter-движка,
      // свежий изолят видит connected, а креды подтягиваются из нативного
      // сервиса асинхронно — уже после того, как клиент собран.
      final proxy = _RecordingProxy(requireAuth: true);
      await proxy.start();
      addTearDown(proxy.stop);

      addTearDown(() => Socks5Credentials().init('', ''));

      final client = HttpClient();
      configureHttpClientForLocalVpnProxy(client, () => proxy.port);
      addTearDown(() => client.close(force: true));

      // «приехали» из нативного сервиса уже после сборки клиента
      Socks5Credentials().init('late', 'creds');

      final req = await client.getUrl(Uri.parse('http://example.test/sub'));
      final resp = await req.close();

      expect(await resp.transform(utf8.decoder).join(), 'proxied');
      expect(
        proxy.authHeaders.last,
        'Basic ${base64.encode(utf8.encode('late:creds'))}',
      );
    });
  });

  group('resolveLocalProxyForBackground', () {
    test('нет записанного порта сессии → напрямую, без пробы', () async {
      // VPN выключен. Проба тут была бы вредна: на 2081 может слушать другой
      // VPN-клиент, и подписка с токеном ушла бы через него.
      expect(await resolveLocalProxyForBackground(null), isNull);
    });

    test('порт записан и слушается → резолвер на него', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close());

      final resolver = await resolveLocalProxyForBackground(server.port);
      expect(resolver, isNotNull);
      expect(resolver!(), server.port);
    });

    test('порт записан, но ядро умерло → напрямую', () async {
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();

      expect(await resolveLocalProxyForBackground(port), isNull);
    });
  });

  group('localHttpProxyIsListening', () {
    test('true, когда порт слушают', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close());
      expect(await localHttpProxyIsListening(server.port), isTrue);
    });

    test('false, когда ядро не запущено', () async {
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();
      expect(await localHttpProxyIsListening(port), isFalse);
    });
  });
}
