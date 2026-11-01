import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/utils/clipboard_import.dart';
import 'package:keqdroid/utils/import_payload.dart';

const _vless = 'vless://uuid@de.example.com:443?security=tls&type=tcp#DE';
const _trojan = 'trojan://pass@nl.example.com:8443?sni=nl.example.com#NL';

/// Вставка с учётом того, куда ушла каждая часть.
class _Sink {
  final subscriptions = <String>[];
  final servers = <String>[];
  final routingLinks = <String>[];
  Object? failSubscription;

  Future<PastedLinksResult> paste(String raw) => importPastedLinks(
        raw,
        addSubscription: (url) async {
          if (failSubscription != null) throw failSubscription!;
          subscriptions.add(url);
        },
        addServer: (config) async => servers.add(config),
        addRoutingProfile: (link) async {
          routingLinks.add(link);
          return 'Профиль';
        },
      );
}

const _routing = 'happ://routing/onadd/eyJOYW1lIjoiUlUifQ==';

void main() {
  group('subscriptionUrlFromPastedLine', () {
    test('http и https — подписка, как есть', () {
      expect(subscriptionUrlFromPastedLine('https://sub.example/api/token'),
          'https://sub.example/api/token');
      expect(subscriptionUrlFromPastedLine('  http://sub.example:2096/s/x  '),
          'http://sub.example:2096/s/x');
      expect(subscriptionUrlFromPastedLine('HTTPS://Sub.Example/x'),
          'HTTPS://Sub.Example/x');
    });

    test('кнопка панели отдаёт вложенный адрес', () {
      expect(
        subscriptionUrlFromPastedLine(
          'keqdroid://install-config?url=https%3A%2F%2Fsub.example%2Fs%2Fx',
        ),
        'https://sub.example/s/x',
      );
    });

    test('серверы и мусор — не подписка', () {
      expect(subscriptionUrlFromPastedLine(_vless), isNull);
      expect(subscriptionUrlFromPastedLine(_trojan), isNull);
      expect(subscriptionUrlFromPastedLine('sub.example/s/x'), isNull);
      expect(subscriptionUrlFromPastedLine('https://'), isNull);
      expect(subscriptionUrlFromPastedLine('{"outbounds": []}'), isNull);
    });
  });

  group('importPastedLinks', () {
    test('ссылка подписки добавляется подпиской, а не сервером', () async {
      final sink = _Sink();
      final result = await sink.paste('https://sub.example/api/token');

      expect(sink.subscriptions, ['https://sub.example/api/token']);
      expect(sink.servers, isEmpty);
      expect(result.subscriptionHosts, ['sub.example']);
      expect(result.serversTotal, 0);
      expect(result.firstError, isNull);
    });

    test('ссылки серверов по-прежнему добавляются серверами', () async {
      final sink = _Sink();
      final result = await sink.paste('$_vless\n$_trojan');

      expect(sink.subscriptions, isEmpty);
      expect(sink.servers, [_vless, _trojan]);
      expect(result.serversAdded, 2);
      expect(result.serversTotal, 2);
    });

    test('вперемешку — каждая строка на своё место', () async {
      final sink = _Sink();
      final result = await sink.paste(
        'https://a.example/s/1\n$_vless\n\nhttp://b.example/s/2',
      );

      expect(sink.subscriptions,
          ['https://a.example/s/1', 'http://b.example/s/2']);
      expect(sink.servers, [_vless]);
      expect(result.added, 3);
    });

    test('упавшая подписка не мешает серверам', () async {
      final sink = _Sink()..failSubscription = Exception('already added');
      final result = await sink.paste('https://sub.example/s\n$_vless');

      expect(sink.servers, [_vless]);
      expect(result.subscriptionHosts, isEmpty);
      expect(result.serversAdded, 1);
      expect(result.firstError, isA<Exception>());
    });
  });

  group('ссылка на профиль маршрутизации', () {
    test('уходит в профили, а не в серверы', () async {
      final sink = _Sink();
      final result = await sink.paste('$_routing\n$_vless');
      expect(sink.routingLinks, [_routing]);
      expect(sink.servers, [_vless]);
      expect(result.routingProfiles, ['Профиль']);
      expect(result.added, 2);
    });

    test('без обработчика профилей идёт по-старому', () async {
      final servers = <String>[];
      final result = await importPastedLinks(
        _routing,
        addSubscription: (_) async {},
        addServer: (config) async => servers.add(config),
      );
      expect(servers, [_routing]);
      expect(result.routingProfiles, isEmpty);
    });

    test('сводка называет профиль', () async {
      final l10n = lookupAppLocalizations(const Locale('ru'));
      final result = await _Sink().paste(_routing);
      expect(
        pastedLinksSummary(l10n, result),
        'Профиль маршрутизации добавлен: Профиль',
      );
    });
  });

  group('pastedLinksSummary', () {
    final l10n = lookupAppLocalizations(const Locale('ru'));

    test('про подписку не говорит «добавлено серверов»', () async {
      final result = await _Sink().paste('https://sub.example/s');
      expect(pastedLinksSummary(l10n, result), 'Подписка добавлена: sub.example');
    });

    test('подписка и серверы — две строки', () async {
      final result = await _Sink().paste('https://sub.example/s\n$_vless');
      expect(
        pastedLinksSummary(l10n, result),
        'Подписка добавлена: sub.example\nДобавлено серверов: 1 из 1',
      );
    });

    test('ничего не добавилось — сказать, кроме ошибки, нечего', () async {
      final sink = _Sink()..failSubscription = Exception('already added');
      final result = await sink.paste('https://sub.example/s');
      expect(pastedLinksSummary(l10n, result), isNull);
    });
  });
}
