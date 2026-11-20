import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/subscription_service.dart';

import '../helpers/test_storage.dart';

/// Соединение сломалось, не дойдя до ответа.
///
/// Так выглядел сбой у проверки обновлений (28.09.2026): рукопожатие с сервером
/// проходит, а начало ответа приезжает испорченным, и повтор сразу же
/// проходит. Dio отдаёт такое как `unknown` с исключением dart:io внутри, и
/// повтор подписки, настроенный на таймауты и отказ соединения, его не видел.
void main() {
  test(
    'испорченное начало ответа — один повтор, и подписка обновляется',
    () async {
      final adapter = _ScriptedAdapter([_brokenTls, _payload()]);
      final service = SubscriptionService(
        await buildStorageService(),
        dio: Dio()..httpClientAdapter = adapter,
      );

      final result = await service.fetchRaw('https://sub.example.com/token');

      expect(adapter.calls, 2);
      expect(result.configs, hasLength(1));
    },
  );

  test('сломалось и при повторе — ошибка, запросов ровно два', () async {
    final adapter = _ScriptedAdapter([_brokenTls, _brokenTls]);
    final service = SubscriptionService(
      await buildStorageService(),
      dio: Dio()..httpClientAdapter = adapter,
    );

    await expectLater(
      service.fetchRaw('https://sub.example.com/token'),
      throwsA(isA<Exception>()),
    );
    expect(adapter.calls, 2);
  });

  test(
    'ошибка не сети (заголовок, который dart:io отверг) не повторяется',
    () async {
      // Ровно так dart:io отвечает на кириллицу в значении заголовка: запрос не
      // уходит вовсе, и второй раз он не уйдёт так же.
      final adapter = _ScriptedAdapter([
        const FormatException('Invalid HTTP header field value'),
      ]);
      final service = SubscriptionService(
        await buildStorageService(),
        dio: Dio()..httpClientAdapter = adapter,
      );

      await expectLater(
        service.fetchRaw('https://sub.example.com/token'),
        throwsA(isA<Exception>()),
      );
      expect(adapter.calls, 1);
    },
  );
}

final _brokenTls = HttpException(
  '\n\tWRONG_VERSION_NUMBER(tls_record.cc:127) error 268435703',
  uri: Uri.parse('https://sub.example.com/token'),
);

ResponseBody _payload() => ResponseBody.fromString(
  base64.encode(
    utf8.encode(
      'vless://22222222-2222-2222-2222-222222222222@1.2.3.4:443'
      '?security=reality&type=tcp#Node',
    ),
  ),
  200,
  headers: {
    'content-type': ['text/plain; charset=utf-8'],
  },
);

/// Каждый вызов — следующий шаг сценария: исключение dart:io или ответ.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.script);

  final List<Object> script;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final step = script[calls++];
    if (step is ResponseBody) return step;
    throw step;
  }

  @override
  void close({bool force = false}) {}
}
