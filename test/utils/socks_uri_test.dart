import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/socks_uri.dart';

void main() {
  group('socks-ссылка', () {
    test('base64(user:pass)@host:port, как отдаёт v2rayN', () {
      // dXNlcjpwYXNz = user:pass
      final link = SocksLink.tryParse('socks://dXNlcjpwYXNz@1.2.3.4:1080#My%20Proxy')!;
      expect(link.host, '1.2.3.4');
      expect(link.port, 1080);
      expect(link.username, 'user');
      expect(link.password, 'pass');
      expect(link.name, 'My Proxy');
    });

    test('логин и пароль открытым текстом раскодируются', () {
      final link = SocksLink.tryParse('socks5://us%40er:p%3Ass@proxy.example:1080')!;
      expect(link.username, 'us@er');
      expect(link.password, 'p:ss');
    });

    test('старый вид: base64 всей части до имени', () {
      // dXNlcjpwYXNzQDEuMi4zLjQ6MTA4MA = user:pass@1.2.3.4:1080
      final link = SocksLink.tryParse('socks://dXNlcjpwYXNzQDEuMi4zLjQ6MTA4MA#old')!;
      expect(link.host, '1.2.3.4');
      expect(link.port, 1080);
      expect(link.username, 'user');
      expect(link.password, 'pass');
    });

    test('без логина, socks5h, IPv6 в скобках, хвостовой /', () {
      final plain = SocksLink.tryParse('socks5h://b.example:1080/#two')!;
      expect(plain.host, 'b.example');
      expect(plain.username, isEmpty);
      final v6 = SocksLink.tryParse('socks://u:p@[2001:db8::1]:1080')!;
      expect(v6.host, '2001:db8::1');
      expect(v6.port, 1080);
    });

    test('без порта, с нулевым портом и чужая схема — не ссылка', () {
      expect(SocksLink.tryParse('socks://u:p@host.example'), isNull);
      expect(SocksLink.tryParse('socks://u:p@host.example:0'), isNull);
      expect(SocksLink.tryParse('socks://u:p@:1080'), isNull);
      expect(SocksLink.tryParse('ss://u:p@host.example:1080'), isNull);
      expect(SocksLink.isSocks('SOCKS5://u:p@h:1'), isTrue);
    });
  });
}
