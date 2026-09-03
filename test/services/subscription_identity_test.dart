import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/services/storage_service.dart';
import 'package:keqdroid/services/subscription_service.dart';
import 'package:keqdroid/utils/identity_presets.dart';
import 'package:mocktail/mocktail.dart';

class _MockStorageService extends Mock implements StorageService {}

/// Записывает заголовки каждого запроса и всегда отдаёт один и тот же ответ.
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({required this.body, required this.contentType});

  final String body;
  final String contentType;
  final requests = <Map<String, String>>[];

  String? header(String name, {int at = 0}) => requests[at][name.toLowerCase()];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    // Регистр имён заголовков dio нормализует по-своему — сравниваем по
    // нижнему, как это делает и сам HTTP.
    requests.add({
      for (final e in options.headers.entries)
        e.key.toLowerCase(): '${e.value}',
    });
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        'content-type': [contentType],
      },
    );
  }
}

const _node =
    'vless://22222222-2222-2222-2222-222222222222@1.2.3.4:443?security=reality&type=tcp#Node';

void main() {
  late _MockStorageService storage;

  setUpAll(() {
    registerFallbackValue(const Subscription(id: '', name: '', url: ''));
  });

  setUp(() {
    storage = _MockStorageService();
    when(() => storage.getSettings()).thenAnswer((_) async => const AppSettings());
    when(() => storage.getHwid()).thenReturn('devicehwid0000');
    when(() => storage.setHwid(any())).thenAnswer((_) async {});
  });

  _RecordingAdapter plainAdapter() => _RecordingAdapter(
        body: base64.encode(utf8.encode(_node)),
        contentType: 'text/plain; charset=utf-8',
      );

  SubscriptionService serviceWith(_RecordingAdapter adapter) {
    final dio = Dio(BaseOptions(headers: {
      'User-Agent': SubscriptionService.browserUserAgent,
    }));
    dio.httpClientAdapter = adapter;
    return SubscriptionService(storage, dio: dio);
  }

  group('subscription fetch identity', () {
    test('overrides hwid, user agent and device headers', () async {
      final adapter = plainAdapter();
      final service = serviceWith(adapter);

      await service.fetchRaw(
        'https://example.com/sub',
        identity: const SubscriptionFetchIdentity(
          enabled: true,
          hwid: 'CAFEBABE1234',
          userAgent: 'Happ/3.20.4',
          deviceOs: 'iOS',
          deviceModel: 'iPhone 15 Pro',
          osVersion: '17.6',
        ),
      );

      expect(adapter.requests, hasLength(1));
      // HWID приводится к нижнему регистру: панели сверяют его как строку.
      expect(adapter.header('x-hwid'), 'cafebabe1234');
      expect(adapter.header('User-Agent'), 'Happ/3.20.4');
      expect(adapter.header('x-device-os'), 'iOS');
      expect(adapter.header('x-device-model'), 'iPhone 15 Pro');
      expect(adapter.header('x-ver-os'), '17.6');
    });

    test('не-ASCII в полях устройства чистится до ASCII', () async {
      // dart:io кидает FormatException на кириллицу в значении заголовка и
      // роняет ВЕСЬ запрос ещё до сети. На русской Windows это прилетало само
      // из Platform.operatingSystemVersion («"Майкрософт Windows 11 Pro" 10.0
      // (Build 26100)»), и любое обновление подписки падало «Ошибкой сети».
      final adapter = plainAdapter();
      final service = serviceWith(adapter);

      await service.fetchRaw(
        'https://example.com/sub',
        identity: const SubscriptionFetchIdentity(
          enabled: true,
          userAgent: 'Хапп',
          deviceOs: 'Виндовс',
          deviceModel: 'ПК',
          osVersion: '"Майкрософт Windows 11 Pro" 10.0 (Build 26100)',
        ),
      );

      final ascii = matches(RegExp(r'^[\x20-\x7E]+$'));
      // ASCII-часть значения сохраняется (версия сборки ещё пригодится
      // панели), выброшена только кириллица
      expect(adapter.header('x-ver-os'), '" Windows 11 Pro" 10.0 (Build 26100)');
      // от значения не осталось ни буквы, ни цифры → значение устройства
      expect(adapter.header('x-device-os'), ascii);
      expect(adapter.header('x-device-model'), ascii);
      expect(adapter.header('User-Agent'), ascii);
      expect(adapter.header('User-Agent'), isNot(contains('Хапп')));
    });

    test('leaves unset fields on the real device values', () async {
      final adapter = plainAdapter();
      final service = serviceWith(adapter);

      await service.fetchRaw(
        'https://example.com/sub',
        identity: const SubscriptionFetchIdentity(
          enabled: true,
          userAgent: 'Happ/3.20.4',
        ),
      );

      expect(adapter.header('x-hwid'), 'devicehwid0000');
      expect(adapter.header('x-device-os'), isNotEmpty);
      expect(adapter.header('x-device-model'), isNotEmpty);
    });

    test('disabled identity changes nothing even with fields filled', () async {
      final adapter = plainAdapter();
      final service = serviceWith(adapter);

      await service.fetchRaw(
        'https://example.com/sub',
        identity: const SubscriptionFetchIdentity(
          hwid: 'CAFEBABE1234',
          userAgent: 'Happ/3.20.4',
        ),
      );

      expect(adapter.header('x-hwid'), 'devicehwid0000');
      expect(adapter.header('User-Agent'), isNot('Happ/3.20.4'));
    });

    test('custom hwid never becomes the device hwid', () async {
      // Иначе подставной HWID утёк бы во все остальные подписки — и в те, что
      // уже привязаны по настоящему.
      final adapter = plainAdapter();
      final service = serviceWith(adapter);

      await service.fetchRaw(
        'https://example.com/sub',
        identity: const SubscriptionFetchIdentity(
          enabled: true,
          hwid: 'CAFEBABE1234',
        ),
      );

      verifyNever(() => storage.setHwid(any()));
    });

    test('hwid stays unsent while sharing is off in settings', () async {
      when(() => storage.getSettings())
          .thenAnswer((_) async => const AppSettings(shareDeviceHwid: false));
      final adapter = plainAdapter();
      final service = serviceWith(adapter);

      await service.fetchRaw(
        'https://example.com/sub',
        identity: const SubscriptionFetchIdentity(
          enabled: true,
          hwid: 'CAFEBABE1234',
        ),
      );

      expect(adapter.header('x-hwid'), isNull);
    });
  });

  group('pinned user agent', () {
    // Панель отдаёт подписку html-страницей: без закреплённого UA это ровно
    // тот случай, ради которого и существует перебор запасных.
    _RecordingAdapter htmlAdapter() => _RecordingAdapter(
          body: '<html><body><pre>$_node</pre></body></html>',
          contentType: 'text/html; charset=utf-8',
        );

    test('is not rotated away when the panel answers with html', () async {
      final adapter = htmlAdapter();
      final service = serviceWith(adapter);

      final result = await service.fetchRaw(
        'https://example.com/sub',
        identity: const SubscriptionFetchIdentity(
          enabled: true,
          userAgent: 'Happ/3.20.4',
        ),
      );

      expect(result.configs, hasLength(1));
      // Ровно один запрос: подмена личности не должна молча схлопываться в
      // наш обычный клиентский UA.
      expect(adapter.requests, hasLength(1));
      expect(adapter.header('User-Agent'), 'Happ/3.20.4');
    });

    test('without it the fallback list is still iterated', () async {
      final adapter = htmlAdapter();
      final service = serviceWith(adapter);

      await service.fetchRaw('https://example.com/sub');

      expect(adapter.requests.length, greaterThan(1));
    });

    test('does not overwrite the saved working UA of the subscription',
        () async {
      final adapter = plainAdapter();
      final service = serviceWith(adapter);
      when(() => storage.getServers()).thenAnswer((_) async => []);
      when(() => storage.getActiveServerId()).thenReturn(null);
      when(() => storage.replaceServersBySubscription(any(), any()))
          .thenAnswer((_) async {});
      when(() => storage.upsertSubscription(any())).thenAnswer((_) async {});

      final result = await service.updateSubscription(
        const Subscription(
          id: 's1',
          name: 'S',
          url: 'https://example.com/sub',
          userAgent: 'NekoBox/1.3.9',
          fetchIdentity: SubscriptionFetchIdentity(
            enabled: true,
            userAgent: 'Happ/3.20.4',
          ),
        ),
      );

      expect(result.success, isTrue);
      // Закреплённый UA — выбор пользовательницы, а не «UA, который тут
      // работает»: выключив подмену, она обязана вернуться к прежнему.
      expect(result.subscription.userAgent, 'NekoBox/1.3.9');
    });
  });

  group('user agent catalogue', () {
    test('the automatic rotation stays a short subset of the catalogue', () {
      // Перебор делает по http-запросу на вариант: свалить в него весь каталог
      // значит превратить неудачную загрузку в полминуты ожидания. Ручной
      // выбор в подписке для того и существует, чтобы каталог был широким.
      expect(SubscriptionService.clientUserAgents.length, lessThan(12));
      expect(
        ClientUaPresets.android.length +
            ClientUaPresets.ios.length +
            ClientUaPresets.desktop.length,
        greaterThan(20),
      );
    });

    test('no duplicates inside the catalogue', () {
      const all = [
        ...ClientUaPresets.android,
        ...ClientUaPresets.ios,
        ...ClientUaPresets.desktop,
        ...ClientUaPresets.cores,
      ];

      expect(all.toSet().length, all.length);
    });
  });

  group('Subscription identity persistence', () {
    test('survives a json round-trip', () {
      const sub = Subscription(
        id: 's1',
        name: 'S',
        url: 'https://example.com/sub',
        fetchIdentity: SubscriptionFetchIdentity(
          enabled: true,
          hwid: 'cafebabe',
          userAgent: 'Happ/3.20.4',
          deviceOs: 'iOS',
          deviceModel: 'iPhone 15 Pro',
          osVersion: '17.6',
        ),
      );

      final restored = Subscription.fromJson(jsonDecode(jsonEncode(sub.toJson())));

      expect(restored.fetchIdentity, sub.fetchIdentity);
    });

    test('empty identity adds nothing to stored json', () {
      const sub = Subscription(id: 's1', name: 'S', url: 'https://a');

      expect(sub.toJson().containsKey('fetchIdentity'), isFalse);
      expect(
        Subscription.fromJson(sub.toJson()).fetchIdentity,
        SubscriptionFetchIdentity.empty,
      );
    });

    test('an update with provider headers keeps the identity', () {
      // withProfileHeaders собирает Subscription руками — забытое поле там
      // молча обнулялось бы на каждом обновлении подписки.
      const sub = Subscription(
        id: 's1',
        name: 'S',
        url: 'https://a',
        fetchIdentity: SubscriptionFetchIdentity(
          enabled: true,
          userAgent: 'Happ/3.20.4',
        ),
      );

      final updated = sub.withProfileHeaders(
        title: 'Panel',
        announce: null,
        supportUrl: null,
        webPageUrl: null,
      );

      expect(updated.fetchIdentity, sub.fetchIdentity);
    });
  });
}
