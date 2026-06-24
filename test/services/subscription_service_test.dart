import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/services/storage_service.dart';
import 'package:keqdroid/services/subscription_service.dart';
import 'package:mocktail/mocktail.dart';

class _MockStorageService extends Mock implements StorageService {}

void main() {
  late _MockStorageService storage;
  late SubscriptionService service;

  setUp(() {
    storage = _MockStorageService();
    service = SubscriptionService(storage);
  });

  group('SubscriptionService.isSafeUrl', () {
    test('allows public https url', () {
      expect(SubscriptionService.isSafeUrl('https://example.com/sub'), isTrue);
    });

    test('blocks localhost and metadata urls', () {
      expect(SubscriptionService.isSafeUrl('http://localhost:8080/test'), isFalse);
      expect(SubscriptionService.isSafeUrl('http://169.254.169.254/latest'), isFalse);
    });
  });

  group('SubscriptionService.getDueForUpdate', () {
    test('uses default interval when updateIntervalHours is 0', () async {
      final now = DateTime.now();
      when(() => storage.getSubscriptions()).thenAnswer((_) async => [
            Subscription(
              id: '1',
              name: 'A',
              url: 'https://a',
              autoUpdate: true,
              updateIntervalHours: 0,
              lastUpdatedAt: now.subtract(const Duration(hours: 2)),
            ),
          ]);

      final due =
          await service.getDueForUpdate(defaultInterval: const Duration(hours: 1));
      expect(due.length, 1);
    });

    test('skips autoUpdate=false and fresh updates', () async {
      final now = DateTime.now();
      when(() => storage.getSubscriptions()).thenAnswer((_) async => [
            Subscription(
              id: '1',
              name: 'A',
              url: 'https://a',
              autoUpdate: false,
              lastUpdatedAt: now.subtract(const Duration(hours: 5)),
            ),
            Subscription(
              id: '2',
              name: 'B',
              url: 'https://b',
              autoUpdate: true,
              updateIntervalHours: 12,
              lastUpdatedAt: now.subtract(const Duration(hours: 1)),
            ),
          ]);

      final due = await service.getDueForUpdate();
      expect(due, isEmpty);
    });
  });

  group('SubscriptionService.updateAll', () {
    test('returns results only for autoUpdate subscriptions', () async {
      when(() => storage.getSubscriptions()).thenAnswer((_) async => [
            Subscription(id: '1', name: 'A', url: 'http://localhost/a', autoUpdate: true),
            Subscription(id: '2', name: 'B', url: 'http://localhost/b', autoUpdate: false),
          ]);
      when(() => storage.getSettings()).thenAnswer((_) async => const AppSettings());
      when(() => storage.getHwid()).thenReturn(null);
      when(() => storage.getServers()).thenAnswer((_) async => <ServerItem>[]);
      when(() => storage.getActiveServerId()).thenReturn(null);

      final results = await service.updateAll();
      expect(results.length, 1);
    });
  });

  group('SubscriptionService provider-gate handling', () {
    test('returns traffic-limit message for metadata-only payload', () async {
      final dio = Dio();
      final payload = base64.encode(
        utf8.encode(
          'vless://11111111-1111-1111-1111-111111111111@0.0.0.0:1?security=&type=tcp#Traffic%20limit%20reached',
        ),
      );
      dio.httpClientAdapter = _FakeAdapter(
        statusCode: 200,
        body: payload,
        headers: {'content-type': ['text/plain; charset=utf-8']},
      );
      service = SubscriptionService(storage, dio: dio);

      when(() => storage.getSettings()).thenAnswer((_) async => const AppSettings());
      when(() => storage.getHwid()).thenReturn(null);
      when(() => storage.setHwid(any())).thenAnswer((_) async {});
      when(() => storage.getServers()).thenAnswer((_) async => <ServerItem>[]);
      when(() => storage.getActiveServerId()).thenReturn(null);

      expect(
        service.updateSubscription(
          const Subscription(id: 's1', name: 'S', url: 'https://example.com/sub'),
        ),
        completion(
          isA<UpdateResult>().having(
            (r) => r.error ?? '',
            'error',
            contains('traffic limit reached'),
          ),
        ),
      );
    });
  });

  group('SubscriptionService._parseBody name extraction', () {
    test('keeps fragment names that contain spaces (and an inner #)', () {
      // Regression: a plain subscription where the #name has raw spaces, an emoji
      // flag and a second '#'. The old extractor regex stopped at the first space,
      // truncating the name to just the flag emoji, which cleanDisplayName then
      // stripped to an empty string. The full name must survive to displayName.
      const body =
          'vless://2289a6ad-c4b9-42b3-903e-082d77f4b0d2@176.108.245.184:25565'
          '?encryption=none&type=tcp&security=reality&sni=gp.x5.ru&fp=chrome'
          '#🇷🇺 Белый интернет #1 | Все операторы';

      final configs = SubscriptionService.parseBodyForTest(body);
      expect(configs.length, 1);

      final server = ServerItem.fromRaw(configs.first);
      expect(server.displayName, '🇷🇺 Белый интернет #1 | Все операторы');
      // cleanName drops the flag emoji but must NOT be empty.
      expect(server.cleanName, 'Белый интернет #1 | Все операторы');
      expect(server.countryCode, 'RU');
    });

    test('splits two URIs that share one line instead of merging them', () {
      const body =
          'vless://aaaaaaaa-1111-2222-3333-444444444444@1.2.3.4:443?type=tcp#name one '
          'vmess://bbbbbbbb-1111-2222-3333-444444444444@5.6.7.8:80#name two';

      final configs = SubscriptionService.parseBodyForTest(body);
      expect(configs.length, 2);
      final names = configs.map((c) => ServerItem.fromRaw(c).displayName).toSet();
      expect(names, containsAll(<String>['name one', 'name two']));
    });
  });
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({
    required this.statusCode,
    required this.body,
    this.headers = const <String, List<String>>{},
  });

  final int statusCode;
  final String body;
  final Map<String, List<String>> headers;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: headers,
    );
  }
}

