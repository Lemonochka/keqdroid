import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/services/storage_service.dart';
import 'package:keqdroid/services/subscription_service.dart';
import 'package:keqdroid/utils/clash_template.dart';
import 'package:mocktail/mocktail.dart';

class _MockStorageService extends Mock implements StorageService {}

void main() {
  late _MockStorageService storage;
  late Map<String, String?> templates;
  late List<ServerItem> saved;

  setUpAll(() {
    registerFallbackValue(const Subscription(id: '', name: '', url: ''));
    registerFallbackValue(<ServerItem>[]);
  });

  setUp(() {
    templates = {};
    saved = [];
    storage = _MockStorageService();
    when(() => storage.getSettings()).thenAnswer((_) async => const AppSettings());
    when(() => storage.getHwid()).thenReturn(null);
    when(() => storage.setHwid(any())).thenAnswer((_) async {});
    when(() => storage.getServers()).thenAnswer((_) async => const []);
    when(() => storage.getActiveServerId()).thenReturn(null);
    when(() => storage.replaceServersBySubscription(any(), any()))
        .thenAnswer((inv) async {
      saved = inv.positionalArguments[1] as List<ServerItem>;
    });
    when(() => storage.upsertSubscription(any())).thenAnswer((_) async {});
    when(() => storage.setClashTemplate(any(), any())).thenAnswer((inv) async {
      templates[inv.positionalArguments[0] as String] =
          inv.positionalArguments[1] as String?;
    });
  });

  const sub = Subscription(id: 's1', name: 'Шаблон', url: 'https://example.com/sub');

  Future<UpdateResult> update(String body) => SubscriptionService(
        storage,
        dio: Dio()..httpClientAdapter = _Adapter(body),
      ).updateSubscription(sub);

  test('шаблон с группами хранится рядом, серверы те же узлы', () async {
    final body = File('test/fixtures/subscription_payloads/clash-template-groups.txt')
        .readAsStringSync();
    final result = await update(body);
    expect(result.success, isTrue);
    expect(saved, hasLength(3));
    final template = ClashTemplate.fromBody(templates['s1']!)!;
    expect([for (final g in template.groups) g.name], ['Недоступные сайты', 'YouTube']);
    expect(template.nodeFor(saved[1]), '🇫🇮 Finland');
  });

  test('подписка без групп стирает прежний шаблон', () async {
    templates['s1'] = 'stale';
    final result = await update(
      'trojan://p@203.0.113.5:443?security=tls&sni=a.example.com#A\n',
    );
    expect(result.success, isTrue);
    expect(templates.containsKey('s1'), isTrue);
    expect(templates['s1'], isNull);
  });
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.body);

  final String body;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString(
        body,
        200,
        headers: {
          'content-type': ['text/plain; charset=utf-8'],
        },
      );
}
