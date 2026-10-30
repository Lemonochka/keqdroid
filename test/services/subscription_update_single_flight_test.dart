import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/services/storage_service.dart';
import 'package:keqdroid/services/subscription_service.dart';
import 'package:mocktail/mocktail.dart';

class _MockStorageService extends Mock implements StorageService {}

// 29.10.2026 в её журнале: окно из трея будило сразу автообновление провайдера и
// DesktopBackgroundService, и каждую просроченную подписку качали дважды одновременно
void main() {
  late _MockStorageService storage;

  setUpAll(() {
    registerFallbackValue(const Subscription(id: '', name: '', url: ''));
    registerFallbackValue(<ServerItem>[]);
  });

  setUp(() {
    storage = _MockStorageService();
    when(() => storage.getSettings()).thenAnswer((_) async => const AppSettings());
    when(() => storage.getHwid()).thenReturn(null);
    when(() => storage.setHwid(any())).thenAnswer((_) async {});
    when(() => storage.getServers()).thenAnswer((_) async => const []);
    when(() => storage.getActiveServerId()).thenReturn(null);
    when(() => storage.replaceServersBySubscription(any(), any()))
        .thenAnswer((_) async {});
    when(() => storage.upsertSubscription(any())).thenAnswer((_) async {});
  });

  const body = 'vless://11111111-1111-1111-1111-111111111111@1.1.1.1:443'
      '?security=reality&type=tcp#Alpha';
  const sub = Subscription(id: 's1', name: 'S', url: 'https://example.com/sub');

  SubscriptionService service(_CountingAdapter adapter) =>
      SubscriptionService(storage, dio: Dio()..httpClientAdapter = adapter);

  test('два одновременных обновления одной подписки идут одним запросом', () async {
    final adapter = _CountingAdapter(body);
    final results = await Future.wait([
      service(adapter).updateSubscription(sub),
      service(adapter).updateSubscription(sub),
    ]);
    expect(adapter.requests, 1);
    expect(results.map((r) => r.success), [true, true]);
  });

  test('следующее обновление после завершения качает заново', () async {
    final adapter = _CountingAdapter(body);
    await service(adapter).updateSubscription(sub);
    await service(adapter).updateSubscription(sub);
    expect(adapter.requests, 2);
  });

  test('сменённая ссылка не ждёт запрос по старой', () async {
    final adapter = _CountingAdapter(body);
    await Future.wait([
      service(adapter).updateSubscription(sub),
      service(adapter).updateSubscription(sub.copyWith(url: 'https://example.org/sub')),
    ]);
    expect(adapter.requests, 2);
  });

  test('ошибка первого не залипает для следующего', () async {
    final failing = _CountingAdapter('<html>502 Bad Gateway</html>', status: 502);
    final first = await service(failing).updateSubscription(sub);
    expect(first.success, isFalse);
    final ok = _CountingAdapter(body);
    final second = await service(ok).updateSubscription(sub);
    expect(second.success, isTrue);
    expect(ok.requests, 1);
  });
}

class _CountingAdapter implements HttpClientAdapter {
  _CountingAdapter(this.body, {this.status = 200});

  final String body;
  final int status;
  int requests = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        'content-type': ['text/plain; charset=utf-8'],
      },
    );
  }
}
