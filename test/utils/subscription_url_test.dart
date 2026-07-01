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
}
