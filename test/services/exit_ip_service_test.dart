import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/server_flag.dart';
import 'package:keqdroid/services/exit_ip_service.dart';

/// Выход подключения: адрес и страна из трассировки Cloudflare, и только
/// через локальный инбаунд ядра — прямой запрос показал бы адрес без VPN.
void main() {
  const trace =
      'fl=12f34\n'
      'h=one.one.one.one\n'
      'ip=45.131.212.234\n'
      'ts=1760000000.123\n'
      'visit_scheme=https\n'
      'loc=NL\n'
      'tls=TLSv1.3\n';

  group('разбор трассировки', () {
    test('адрес и страна', () {
      final exit = ExitIpService.parseTrace(trace)!;
      expect(exit.ip, '45.131.212.234');
      expect(exit.countryCode, 'NL');
      expect(exit.flag, const FlagArt('nl'));
    });

    test('IPv6 тоже адрес', () {
      final exit = ExitIpService.parseTrace('ip=2a01:4f8:c0c:1::1\nloc=de\n')!;
      expect(exit.ip, '2a01:4f8:c0c:1::1');
      expect(exit.countryCode, 'DE');
    });

    test('неизвестная страна и Tor — без флага, адрес остаётся', () {
      for (final loc in ['XX', 'T1', '']) {
        final exit = ExitIpService.parseTrace('ip=1.2.3.4\nloc=$loc\n')!;
        expect(exit.countryCode, isNull, reason: loc);
        expect(exit.flag, isNull, reason: loc);
      }
    });

    test('без адреса или с мусором вместо него — ничего', () {
      expect(ExitIpService.parseTrace('loc=NL\n'), isNull);
      expect(ExitIpService.parseTrace('ip=not-an-ip\nloc=NL\n'), isNull);
      expect(ExitIpService.parseTrace('<html>blocked</html>'), isNull);
    });
  });

  group('запрос', () {
    test('идёт через локальный прокси, а не напрямую', () async {
      // Ответчик-«прокси»: запрос с абсолютным адресом приходит ему, а не
      // хосту из адреса, — так и выглядит выход через HTTP-инбаунд ядра.
      final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => proxy.close(force: true));
      final hosts = <String?>[];
      proxy.listen((request) {
        hosts.add(request.headers.host);
        request.response
          ..write(trace)
          ..close();
      });

      final exit = await ExitIpService.lookup(
        proxyPort: proxy.port,
        traceUrl: Uri.parse('http://trace.example/cdn-cgi/trace'),
      );

      expect(hosts, ['trace.example']);
      expect(exit?.ip, '45.131.212.234');
      expect(exit?.countryCode, 'NL');
    });

    test('инбаунд не отвечает — тихо null, без исключения', () async {
      final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = closed.port;
      await closed.close();

      final exit = await ExitIpService.lookup(
        proxyPort: port,
        timeout: const Duration(seconds: 2),
        traceUrl: Uri.parse('http://trace.example/cdn-cgi/trace'),
      );
      expect(exit, isNull);
    });
  });
}
