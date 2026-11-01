import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/subscription_url.dart';

void main() {
  group('normalizeSubscriptionUrl', () {
    test('trims surrounding whitespace', () {
      expect(
        normalizeSubscriptionUrl('  https://example.com/sub  '),
        'https://example.com/sub',
      );
    });

    test('lowercases scheme and host but not path', () {
      expect(
        normalizeSubscriptionUrl('HTTPS://Example.COM/Path/SUB'),
        'https://example.com/Path/SUB',
      );
    });

    test('drops a single trailing slash from the path', () {
      expect(
        normalizeSubscriptionUrl('https://example.com/sub/'),
        'https://example.com/sub',
      );
    });

    test('keeps a lone root slash (does not strip to empty)', () {
      // path == '/' (length 1) must stay so the URL stays well-formed
      expect(
        normalizeSubscriptionUrl('https://example.com/'),
        'https://example.com/',
      );
    });

    test('preserves query string', () {
      expect(
        normalizeSubscriptionUrl('https://Example.com/sub?token=ABC'),
        'https://example.com/sub?token=ABC',
      );
    });

    test('two URLs differing only by case/trailing slash normalize equal', () {
      expect(
        normalizeSubscriptionUrl('  HTTPS://Host.Example.com/sub/  '),
        normalizeSubscriptionUrl('https://host.example.com/sub'),
      );
    });

    test('percent-encodes (does not throw on) a space in the host', () {
      // Uri.parse is lenient with spaces — it encodes rather than throwing,
      // so we still go through the normal normalization path.
      expect(
        normalizeSubscriptionUrl('  http://Example.com/a b  '),
        'http://example.com/a%20b',
      );
    });

    test('truly unparseable input falls back to the trimmed string', () {
      // a non-numeric port makes Uri.parse throw → catch returns trimmed input
      expect(
        normalizeSubscriptionUrl('  http://example.com:notaport/sub  '),
        'http://example.com:notaport/sub',
      );
    });
  });

  group('movedSubscriptionUrl', () {
    const current = 'https://old.example:2096/sub/abc?fmt=v2ray';

    test('new-url заменяет адрес целиком', () {
      expect(
        movedSubscriptionUrl(current, newUrl: 'https://new.example/s/xyz'),
        'https://new.example/s/xyz',
      );
    });

    test('new-domain меняет только хост, остальное как было', () {
      expect(
        movedSubscriptionUrl(current, newDomain: 'mirror.example'),
        'https://mirror.example:2096/sub/abc?fmt=v2ray',
      );
      expect(
        movedSubscriptionUrl(current, newDomain: 'mirror.example:8443'),
        'https://mirror.example:8443/sub/abc?fmt=v2ray',
      );
      expect(
        movedSubscriptionUrl(current, newDomain: 'https://mirror.example/x'),
        'https://mirror.example:2096/sub/abc?fmt=v2ray',
      );
    });

    test('new-url сильнее new-domain', () {
      expect(
        movedSubscriptionUrl(
          current,
          newUrl: 'https://a.example/s',
          newDomain: 'b.example',
        ),
        'https://a.example/s',
      );
    });

    test('с https на http, на тот же адрес и на мусор не переезжаем', () {
      expect(movedSubscriptionUrl(current, newUrl: 'http://new.example/s'), isNull);
      expect(movedSubscriptionUrl(current, newUrl: 'https://OLD.example:2096/sub/abc?fmt=v2ray'), isNull);
      expect(movedSubscriptionUrl(current, newUrl: 'vless://x@y:1'), isNull);
      expect(movedSubscriptionUrl(current, newDomain: 'not a domain'), isNull);
      expect(movedSubscriptionUrl(current, newDomain: 'localhost'), isNull);
      expect(movedSubscriptionUrl(current), isNull);
    });
  });
}
