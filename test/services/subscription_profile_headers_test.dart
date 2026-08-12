import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/services/subscription_service.dart';

/// Косметические заголовки подписки по XTLS Subscription Standards:
/// `profile-title` и `announce` приходят с префиксом `base64:`, ссылки — как
/// есть, интервал — целым числом часов.
Headers _headers(Map<String, String> values) {
  final h = Headers();
  values.forEach(h.set);
  return h;
}

String _b64(String s) => base64.encode(utf8.encode(s));

void main() {
  group('разбор заголовков', () {
    test('base64-префикс раскодируется', () {
      final p = SubscriptionService.parseProfileHeadersForTest(
        _headers({
          'profile-title': 'base64:${_b64('Тихий Интернет')}',
          'announce': 'base64:${_b64('Плановые работы в ночь на среду')}',
        }),
      );
      expect(p.title, 'Тихий Интернет');
      expect(p.announce, 'Плановые работы в ночь на среду');
    });

    test('обычный текст без префикса не портится', () {
      // «Announce» — валидный base64 по алфавиту, но раскодируется в мусор:
      // именно поэтому декодирование проверяет результат, а не только форму.
      final p = SubscriptionService.parseProfileHeadersForTest(
        _headers({'profile-title': 'Announce', 'announce': 'Всё работает'}),
      );
      expect(p.title, 'Announce');
      expect(p.announce, 'Всё работает');
    });

    test('голый base64 без префикса всё же раскодируется', () {
      final p = SubscriptionService.parseProfileHeadersForTest(
        _headers({'profile-title': _b64('My VPN Service')}),
      );
      expect(p.title, 'My VPN Service');
    });

    test('ссылки берутся только http(s)', () {
      final p = SubscriptionService.parseProfileHeadersForTest(
        _headers({
          'support-url': 'https://t.me/example',
          'profile-web-page-url': 'javascript:alert(1)',
        }),
      );
      expect(p.supportUrl, 'https://t.me/example');
      expect(p.webPageUrl, isNull, reason: 'не-http схему открывать нельзя');
    });

    test('интервал: только положительный', () {
      expect(
        SubscriptionService.parseProfileHeadersForTest(
          _headers({'profile-update-interval': '6'}),
        ).updateIntervalHours,
        6,
      );
      expect(
        SubscriptionService.parseProfileHeadersForTest(
          _headers({'profile-update-interval': '0'}),
        ).updateIntervalHours,
        isNull,
      );
    });

    test('пустые заголовки дают пустой профиль', () {
      expect(
        SubscriptionService.parseProfileHeadersForTest(_headers({})).isEmpty,
        isTrue,
      );
    });
  });

  group('название от провайдера', () {
    Subscription sub({required bool nameIsAuto, String name = 'sub.example.com'}) =>
        Subscription(
          id: 'x',
          name: name,
          url: 'https://sub.example.com/abc',
          nameIsAuto: nameIsAuto,
        );

    test('авто-имя заменяется названием сервиса', () {
      final s = sub(nameIsAuto: true).withProfileHeaders(
        title: 'Тихий Интернет',
        announce: null,
        supportUrl: null,
        webPageUrl: null,
      );
      expect(s.name, 'Тихий Интернет');
      expect(s.providerTitle, 'Тихий Интернет');
      // подпись не дублирует заголовок карточки
      expect(s.providerSubtitle, isNull);
    });

    test('имя, введённое руками, не перетирается', () {
      final s = sub(nameIsAuto: false, name: 'Моя подписка').withProfileHeaders(
        title: 'Тихий Интернет',
        announce: null,
        supportUrl: null,
        webPageUrl: null,
      );
      expect(s.name, 'Моя подписка');
      // но чей это сервис — карточка всё равно может показать
      expect(s.providerSubtitle, 'Тихий Интернет');
    });

    test('снятое объявление действительно исчезает', () {
      final withAnnounce = sub(nameIsAuto: true).withProfileHeaders(
        title: null,
        announce: 'Работы',
        supportUrl: null,
        webPageUrl: null,
      );
      expect(withAnnounce.announce, 'Работы');

      final cleared = withAnnounce.withProfileHeaders(
        title: null,
        announce: null,
        supportUrl: null,
        webPageUrl: null,
      );
      expect(
        cleared.announce,
        isNull,
        reason: 'copyWith трактует null как «не трогать» — здесь так нельзя',
      );
    });

    test('интервал от панели применяется только когда передан', () {
      final base = sub(nameIsAuto: true);
      expect(base.updateIntervalHours, 12);
      final applied = base.withProfileHeaders(
        title: null,
        announce: null,
        supportUrl: null,
        webPageUrl: null,
        updateIntervalHours: 6,
      );
      expect(applied.updateIntervalHours, 6);
      final kept = applied.withProfileHeaders(
        title: null,
        announce: null,
        supportUrl: null,
        webPageUrl: null,
      );
      expect(kept.updateIntervalHours, 6);
    });
  });

  group('сброс имени на автоматическое', () {
    // Логику воспроизводим ровно ту, что в SubscriptionsNotifier.editMeta:
    // проверять стоит именно её, а не то, что поле очистилось.
    Subscription reset(Subscription s) {
      final autoName = s.providerTitle?.trim().isNotEmpty == true
          ? s.providerTitle!.trim()
          : (Uri.tryParse(s.url)?.host ?? s.name);
      return s.copyWith(name: autoName, nameIsAuto: true);
    }

    test('пустое поле возвращает название провайдера', () {
      final s = Subscription(
        id: 'x',
        name: 'Моя подписка',
        url: 'https://sub.example.com/abc',
        providerTitle: 'Тихий Интернет',
      );
      final after = reset(s);
      expect(after.name, 'Тихий Интернет');
      expect(after.nameIsAuto, isTrue);
    });

    test('без названия провайдера остаётся хост', () {
      final s = Subscription(
        id: 'x',
        name: 'Моя подписка',
        url: 'https://sub.example.com/abc',
      );
      expect(reset(s).name, 'sub.example.com');
    });

    test('после сброса название провайдера снова подхватывается', () {
      final s = reset(
        Subscription(
          id: 'x',
          name: 'Моя подписка',
          url: 'https://sub.example.com/abc',
        ),
      ).withProfileHeaders(
        title: 'Тихий Интернет',
        announce: null,
        supportUrl: null,
        webPageUrl: null,
      );
      expect(s.name, 'Тихий Интернет');
    });
  });

  group('миграция сохранённых подписок', () {
    test('имя, совпадающее с хостом, считается автоматическим', () {
      final s = Subscription.fromJson({
        'id': 'x',
        'name': 'sub.example.com',
        'url': 'https://sub.example.com/abc',
      });
      expect(s.nameIsAuto, isTrue);
    });

    test('своё имя автоматическим не считается', () {
      final s = Subscription.fromJson({
        'id': 'x',
        'name': 'Моя подписка',
        'url': 'https://sub.example.com/abc',
      });
      expect(s.nameIsAuto, isFalse);
    });

    test('флаг переживает round-trip', () {
      final s = Subscription.fromJson({
        'id': 'x',
        'name': 'Моя подписка',
        'url': 'https://sub.example.com/abc',
        'nameIsAuto': true,
      });
      expect(s.nameIsAuto, isTrue);
      expect(Subscription.fromJson(s.toJson()).nameIsAuto, isTrue);
    });
  });
}
