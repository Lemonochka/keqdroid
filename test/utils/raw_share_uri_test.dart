import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/raw_share_uri.dart';

void main() {
  group('RawShareUri.parse', () {
    test('splits vless link into raw components', () {
      final uri = RawShareUri.parse(
        'vless://2289a6ad-c4b9-42b3-903e-082d77f4b0d2@1.2.3.4:25565'
        '?encryption=none&type=tcp&security=reality&sni=gp.x5.ru&fp=chrome'
        '#🇷🇺 Белый интернет #1 | Все операторы',
      )!;
      expect(uri.scheme, 'vless');
      expect(uri.userInfo, '2289a6ad-c4b9-42b3-903e-082d77f4b0d2');
      expect(uri.host, '1.2.3.4');
      expect(uri.port, '25565');
      expect(uri.hasFragment, isTrue);
      // фрагмент сырой, включая внутренний '#'
      expect(uri.fragment, '🇷🇺 Белый интернет #1 | Все операторы');
      expect(uri.takeParam('security'), 'reality');
      expect(uri.takeParam('sni'), 'gp.x5.ru');
    });

    test('keeps IPv6 host with brackets', () {
      final uri = RawShareUri.parse('trojan://pass@[2001:db8::1]:443?sni=x#n')!;
      expect(uri.host, '[2001:db8::1]');
      expect(uri.port, '443');
      expect(uri.userInfo, 'pass');
    });

    test('userInfo stays raw (no percent-decoding)', () {
      final uri = RawShareUri.parse('trojan://p%40ss@h.com:443#n')!;
      expect(uri.userInfo, 'p%40ss');
    });

    test('returns null for non-uri input', () {
      expect(RawShareUri.parse('[Interface]\nPrivateKey = x'), isNull);
    });
  });

  group('RawShareUri round-trip', () {
    test('untouched unknown params and fragment survive byte-exact', () {
      const link =
          'vless://uuid-1@ya.ru:443?security=tls&sni=a.com&weird=%2Fkeep%20me'
          '&flag#Имя %23 сервера';
      final uri = RawShareUri.parse(link)!;
      // забираем managed-параметры, как это делает редактор
      final sni = uri.takeParam('sni');
      final security = uri.takeParam('security');
      final rebuilt = uri.build(managedParams: [
        MapEntry('security', security),
        MapEntry('sni', sni),
      ]);
      // неизвестные токены (weird, flag) — сырыми; fragment не тронут
      expect(rebuilt, contains('weird=%2Fkeep%20me'));
      expect(rebuilt, contains('flag'));
      expect(rebuilt, endsWith('#Имя %23 сервера'));
      expect(rebuilt, contains('security=tls'));
      expect(rebuilt, contains('sni=a.com'));
    });

    test('takeParam removes every occurrence of the key', () {
      final uri =
          RawShareUri.parse('vless://u@h.com:1?sni=a&sni=b&other=1#n')!;
      expect(uri.takeParam('sni'), 'a');
      expect(uri.hasParam('sni'), isFalse);
      expect(uri.hasParam('other'), isTrue);
    });

    test('empty managed values are omitted from the query', () {
      final uri = RawShareUri.parse('vless://u@h.com:1#n')!;
      final rebuilt = uri.build(managedParams: const [
        MapEntry('sni', ''),
        MapEntry('security', 'none'),
      ]);
      expect(rebuilt, 'vless://u@h.com:1?security=none#n');
    });

    test('link without fragment gains no #', () {
      final uri = RawShareUri.parse('hy2://auth@h.com:443?sni=x')!;
      final sni = uri.takeParam('sni');
      expect(
        uri.build(managedParams: [MapEntry('sni', sni)]),
        'hy2://auth@h.com:443?sni=x',
      );
    });

    test('mutating host/port/userInfo lands in the rebuilt link', () {
      final uri = RawShareUri.parse('vless://old@a.com:443?x=1#name')!;
      uri
        ..userInfo = 'new-uuid'
        ..host = 'b.org'
        ..port = '8443';
      expect(
        uri.build(managedParams: const []),
        'vless://new-uuid@b.org:8443?x=1#name',
      );
    });

    test('managed values are query-encoded on rebuild', () {
      final uri = RawShareUri.parse('vless://u@h.com:1#n')!;
      final rebuilt = uri.build(managedParams: const [
        MapEntry('spx', '/path with space'),
      ]);
      expect(rebuilt, 'vless://u@h.com:1?spx=%2Fpath+with+space#n');
      // и парсится обратно в то же значение
      final again = RawShareUri.parse(rebuilt)!;
      expect(again.takeParam('spx'), '/path with space');
    });
  });
}
