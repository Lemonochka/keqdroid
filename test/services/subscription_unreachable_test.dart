import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/subscription_service.dart';

import '../helpers/test_storage.dart';

/// Хост подписки недоступен — ответа нет вовсе.
///
/// Так бывает при живом VPN, когда из выходного узла до хоста подписки не
/// достучаться (лог 25.09.2026: основной запрос и два запасных по 15 с, и
/// только после переподключения ответ). Запасной клиент нужен серверам,
/// которые ответили, но не тому клиенту; до молчащего хоста он не доходит так
/// же, а каждая его попытка стоит ещё 15 секунд.
class _NoAnswerAdapter implements HttpClientAdapter {
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionTimeout,
      message: 'connection timed out',
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'без ответа — только основной запрос и один повтор',
    () async {
      final adapter = _NoAnswerAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final service = SubscriptionService(
        await buildStorageService(),
        dio: dio,
      );

      // TEST-NET: запасной клиент, если бы он пошёл сюда, ждал бы свои 15 с на
      // каждую из двух попыток.
      final sw = Stopwatch()..start();
      await expectLater(
        service.fetchRaw('https://203.0.113.7/sub/token'),
        throwsA(isA<Exception>()),
      );
      sw.stop();

      expect(adapter.calls, 2);
      expect(
        sw.elapsed,
        lessThan(const Duration(seconds: 10)),
        reason: 'повтор ждёт 2 с; всё сверх этого — лишние попытки',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
