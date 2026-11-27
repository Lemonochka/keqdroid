import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/core/exceptions.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/services/storage_service.dart';
import 'package:keqdroid/services/subscription_service.dart';
import 'package:mocktail/mocktail.dart';

const _limit = 10 * 1024 * 1024;
const _url = 'https://example.com/sub';
const _node =
    'vless://22222222-2222-2222-2222-222222222222@1.2.3.4:443?security=reality&type=tcp#Node';
const _pinnedIdentity = SubscriptionFetchIdentity(
  enabled: true,
  userAgent: 'Happ/4.1.0',
);

final _oversized = 'x' * (_limit + 1);

class _MockStorageService extends Mock implements StorageService {}

void main() {
  late _MockStorageService storage;

  setUp(() {
    storage = _MockStorageService();
    when(
      () => storage.getSettings(),
    ).thenAnswer((_) async => const AppSettings(shareDeviceHwid: false));
  });

  SubscriptionService service(
    HttpClientAdapter adapter, {
    HttpClient Function()? httpClientFactory,
  }) => SubscriptionService(
    storage,
    dio: Dio()..httpClientAdapter = adapter,
    httpClientFactory: httpClientFactory,
  );

  Matcher tooLarge() => isA<SubscriptionFetchException>().having(
    (e) => e.message,
    'message',
    'Response too large (>10MB)',
  );

  group('response size limit', () {
    test('applies to the primary response', () async {
      final subject = service(_ScriptedAdapter([_Reply(200, _oversized)]));

      await expectLater(subject.fetchRaw(_url), throwsA(tooLarge()));
    });

    test('applies to a subscription inside an HTTP error', () async {
      final subject = service(_ScriptedAdapter([_Reply(502, _oversized)]));

      await expectLater(
        subject.fetchRaw(_url, identity: _pinnedIdentity),
        throwsA(tooLarge()),
      );
    });

    test('applies after User-Agent rotation from an HTTP error', () async {
      final subject = service(
        _ScriptedAdapter([
          _Reply(502, 'not a subscription'),
          _Reply(200, _oversized),
        ]),
      );

      await expectLater(subject.fetchRaw(_url), throwsA(tooLarge()));
    });

    test('applies after User-Agent rotation from an HTML page', () async {
      final subject = service(
        _ScriptedAdapter([
          _Reply(200, '<html>subscription</html>', 'text/html'),
          _Reply(200, _oversized),
        ]),
      );

      await expectLater(subject.fetchRaw(_url), throwsA(tooLarge()));
    });

    test('stops a chunked HttpClient response at the byte limit', () async {
      final chunk = List<int>.filled(5 * 1024 * 1024, 120);
      final httpClient = _FakeHttpClient(
        _FakeHttpClientResponse([chunk, chunk, chunk]),
      );
      final subject = service(
        _ScriptedAdapter([_Reply(502, 'not a subscription')]),
        httpClientFactory: () => httpClient,
      );

      await expectLater(
        subject.fetchRaw(_url, identity: _pinnedIdentity),
        throwsA(tooLarge()),
      );
      expect(httpClient.closed, isTrue);
    });

    test('applies the limit after gzip decompression', () async {
      final compressed = gzip.encode(utf8.encode(_oversized));
      expect(compressed.length, lessThan(_limit));
      final subject = service(
        _ScriptedAdapter([_Reply(502, 'not a subscription')]),
        httpClientFactory: () => _FakeHttpClient(
          _FakeHttpClientResponse(
            [compressed],
            headers: {'content-encoding': 'gzip'},
          ),
        ),
      );

      await expectLater(
        subject.fetchRaw(_url, identity: _pinnedIdentity),
        throwsA(tooLarge()),
      );
    });
  });

  group('fallback behavior', () {
    test(
      'an invalid HTTP error body still continues to User-Agent fallback',
      () async {
        final adapter = _ScriptedAdapter([
          _Reply(502, 'not a subscription'),
          _Reply(200, _node),
        ]);
        final result = await service(adapter).fetchRaw(_url);

        expect(result.configs, [_node]);
        expect(adapter.calls, 2);
      },
    );

    test('keeps a Clash template from an HTTP error response', () async {
      final result = await service(
        _ScriptedAdapter([_Reply(502, _clashBody)]),
      ).fetchRaw(_url, identity: _pinnedIdentity);

      expect(result.configs, hasLength(3));
      expect(result.clashTemplate, isNotNull);
    });

    test('keeps a Clash template after User-Agent rotation', () async {
      final result = await service(
        _ScriptedAdapter([
          _Reply(502, 'not a subscription'),
          _Reply(200, _clashBody),
        ]),
      ).fetchRaw(_url);

      expect(result.configs, hasLength(3));
      expect(result.clashTemplate, isNotNull);
    });

    test('keeps a Clash template from HttpClient fallback', () async {
      final bytes = utf8.encode(_clashBody);
      final result = await service(
        _ScriptedAdapter([_Reply(502, 'not a subscription')]),
        httpClientFactory: () => _FakeHttpClient(
          _FakeHttpClientResponse([bytes.sublist(0, 100), bytes.sublist(100)]),
        ),
      ).fetchRaw(_url, identity: _pinnedIdentity);

      expect(result.configs, hasLength(3));
      expect(result.clashTemplate, isNotNull);
    });

    test('decodes a valid gzip response in HttpClient fallback', () async {
      final result = await service(
        _ScriptedAdapter([_Reply(502, 'not a subscription')]),
        httpClientFactory: () => _FakeHttpClient(
          _FakeHttpClientResponse(
            [gzip.encode(utf8.encode(_node))],
            headers: {'content-encoding': 'gzip'},
          ),
        ),
      ).fetchRaw(_url, identity: _pinnedIdentity);

      expect(result.configs, [_node]);
    });
  });
}

final _clashBody = File(
  'test/fixtures/subscription_payloads/clash-template-groups.txt',
).readAsStringSync();

class _Reply {
  const _Reply(
    this.statusCode,
    this.body, [
    this.contentType = 'text/plain; charset=utf-8',
  ]);

  final int statusCode;
  final String body;
  final String contentType;
}

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.replies);

  final List<_Reply> replies;
  var calls = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final index = calls++;
    if (index >= replies.length) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'unexpected request',
      );
    }
    final reply = replies[index];
    return ResponseBody.fromString(
      reply.body,
      reply.statusCode,
      headers: {
        'content-type': [reply.contentType],
      },
    );
  }
}

class _FakeHttpClient extends Fake implements HttpClient {
  _FakeHttpClient(this.response);

  final _FakeHttpClientResponse response;
  var closed = false;

  @override
  set connectionTimeout(Duration? value) {}

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _FakeHttpClientRequest(response);

  @override
  void close({bool force = false}) {
    closed = true;
  }
}

class _FakeHttpClientRequest extends Fake implements HttpClientRequest {
  _FakeHttpClientRequest(this.response);

  final _FakeHttpClientResponse response;

  @override
  final HttpHeaders headers = _FakeHttpHeaders({});

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  Future<HttpClientResponse> close() async => response;
}

class _FakeHttpClientResponse extends Fake implements HttpClientResponse {
  _FakeHttpClientResponse(this.chunks, {Map<String, String> headers = const {}})
    : headers = _FakeHttpHeaders({
        'content-type': ['text/plain; charset=utf-8'],
        for (final entry in headers.entries) entry.key: [entry.value],
      });

  final List<List<int>> chunks;

  @override
  final HttpHeaders headers;

  @override
  int get statusCode => 200;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.fromIterable(chunks).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}

class _FakeHttpHeaders extends Fake implements HttpHeaders {
  _FakeHttpHeaders(this.values);

  final Map<String, List<String>> values;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name] = ['$value'];
  }

  @override
  void forEach(void Function(String name, List<String> values) action) {
    values.forEach(action);
  }

  @override
  ContentType? get contentType {
    final value = values[HttpHeaders.contentTypeHeader]?.firstOrNull;
    return value == null ? null : ContentType.parse(value);
  }
}
