import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/subscription_deep_link.dart';

void main() {
  group('subscriptionUrlFromDeepLink', () {
    test('вытаскивает подписку из ссылки, как её собирает панель', () {
      expect(
        subscriptionUrlFromDeepLink(
          'keqdroid://install-config?url=https://panel.example.com/sub/abc123',
        ),
        'https://panel.example.com/sub/abc123',
      );
    });

    test('вторая схема бренда работает так же', () {
      expect(
        subscriptionUrlFromDeepLink(
          'keqdis://install-config?url=https://panel.example.com/sub/abc',
        ),
        'https://panel.example.com/sub/abc',
      );
    });

    test('хост не важен: панели пишут туда что придётся', () {
      for (final host in const ['install-config', 'add', 'subscribe', '']) {
        expect(
          subscriptionUrlFromDeepLink(
            'keqdroid://$host?url=https://panel.example.com/sub',
          ),
          'https://panel.example.com/sub',
          reason: 'хост "$host"',
        );
      }
    });

    test('percent-кодированный адрес разворачивается', () {
      expect(
        subscriptionUrlFromDeepLink(
          'keqdroid://install-config?url=https%3A%2F%2Fp.example.com%2Fsub%3Ftoken%3D1',
        ),
        'https://p.example.com/sub?token=1',
      );
    });

    test('незакодированный query подписки не обрезается', () {
      // Панель вполне может не закодировать вложенный URL: всё после первого `?`
      // становится нашим query, но параметр `url` доносит строку целиком.
      expect(
        subscriptionUrlFromDeepLink(
          'keqdroid://install-config?url=https://p.example.com/sub?token=1',
        ),
        'https://p.example.com/sub?token=1',
      );
    });

    test('серверная ссылка остаётся серверной', () {
      // Иначе vless:// уехал бы в добавление подписки вместо импорта сервера.
      expect(subscriptionUrlFromDeepLink('vless://uuid@host:443?type=tcp'), isNull);
      expect(subscriptionUrlFromDeepLink('https://panel.example.com/sub'), isNull);
    });

    test('мусор вместо адреса отбрасывается', () {
      expect(subscriptionUrlFromDeepLink('keqdroid://install-config'), isNull);
      expect(subscriptionUrlFromDeepLink('keqdroid://install-config?url='), isNull);
      expect(
        subscriptionUrlFromDeepLink('keqdroid://install-config?url=not-a-url'),
        isNull,
      );
      // ftp/file и прочее в подписку не пускаем.
      expect(
        subscriptionUrlFromDeepLink('keqdroid://install-config?url=ftp://x.example.com/s'),
        isNull,
      );
    });
  });
}
