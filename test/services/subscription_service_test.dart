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

