import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/services/rule_list_service.dart';

// Списки по ссылкам: скачивание, кэш на диске и что из него уходит ядру.
// Подключение сети не ждёт, поэтому всё, что ядро получает, берётся из кэша,
// а неудачное обновление не должно отнимать скачанное раньше.
void main() {
  late Directory root;
  late HttpServer server;
  final bodies = <String, String>{};
  final codes = <String, int>{};
  final hosts = <String?>[];

  setUp(() async {
    root = await Directory.systemTemp.createTemp('rule_lists_test');
    bodies.clear();
    codes.clear();
    hosts.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      hosts.add(request.headers.host);
      final path = request.uri.path;
      request.response.statusCode = codes[path] ?? HttpStatus.ok;
      request.response
        ..write(bodies[path] ?? '')
        ..close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await root.delete(recursive: true);
  });

  String url(String path) => 'http://127.0.0.1:${server.port}$path';

  RuleListService service({int? maxBytes}) => RuleListService(
    root: () async => root,
    allowPlainHttp: true,
    maxBytes: maxBytes ?? RuleListService.defaultMaxBytes,
  );

  test('скачанный список разбирается и переживает перезапуск', () async {
    bodies['/ads.txt'] = '! comment\n||ads.example^\n0.0.0.0 track.example\n';
    final result = await service().refresh(url('/ads.txt'));
    expect(result.failure, isNull);
    expect(result.domains, 2);
    expect(result.loaded, isTrue);

    // Новый экземпляр, как после перезапуска приложения.
    final again = await service().status(url('/ads.txt'));
    expect(again.domains, 2);
    expect(again.updatedAt, isNotNull);
  });

  test(
    'ядру уходят домены по полям, повторы между списками схлопнуты',
    () async {
      bodies['/a.txt'] = 'a.example\nshared.example\n';
      bodies['/b.txt'] = '||shared.example^\n||b.example^\n';
      bodies['/d.txt'] = 'direct.example\n';
      final s = service();
      await s.refresh(url('/a.txt'));
      await s.refresh(url('/b.txt'));
      await s.refresh(url('/d.txt'));

      final lists = await s.domainsFor(
        AppSettings(
          blockedRules: 'x.example, ${url('/a.txt')}\n${url('/b.txt')}',
          directRules: url('/d.txt'),
          proxyRules: 'youtube.com',
        ),
      );
      expect(
        lists.blocked,
        unorderedEquals(['a.example', 'shared.example', 'b.example']),
      );
      expect(lists.direct, ['direct.example']);
      expect(lists.proxy, isEmpty);
    },
  );

  test('ещё не скачанный список подключение не задерживает', () async {
    final lists = await service().domainsFor(
      AppSettings(blockedRules: url('/never.txt')),
    );
    expect(lists.isEmpty, isTrue);
    expect(hosts, isEmpty, reason: 'domainsFor в сеть не ходит');
  });

  test('неудача не отнимает скачанное раньше', () async {
    bodies['/ads.txt'] = 'ads.example\n';
    final s = service();
    await s.refresh(url('/ads.txt'));

    codes['/ads.txt'] = HttpStatus.notFound;
    final failed = await s.refresh(url('/ads.txt'));
    expect(failed.failure, RuleListFailure.http);
    expect(failed.httpStatus, 404);
    expect(failed.domains, 1);
    expect(failed.loaded, isTrue);

    final lists = await s.domainsFor(
      AppSettings(blockedRules: url('/ads.txt')),
    );
    expect(lists.blocked, ['ads.example']);
  });

  test('страница вместо списка — «доменов нет», а не пустой блок', () async {
    bodies['/page'] = '<html><body>Not a list</body></html>';
    final result = await service().refresh(url('/page'));
    expect(result.failure, RuleListFailure.empty);
    expect(result.loaded, isFalse);
  });

  test('слишком большой ответ обрывается', () async {
    bodies['/big.txt'] = List.filled(5000, 'ads.example').join('\n');
    final result = await service(maxBytes: 1024).refresh(url('/big.txt'));
    expect(result.failure, RuleListFailure.tooLarge);
    expect(result.loaded, isFalse);
  });

  test('без https не скачивается вовсе', () async {
    final strict = RuleListService(root: () async => root);
    final result = await strict.refresh(url('/ads.txt'));
    expect(result.failure, RuleListFailure.insecure);
    expect(hosts, isEmpty);
  });

  test('хост не отвечает — сетевая ошибка, без исключения', () async {
    final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = closed.port;
    await closed.close();
    final result = await service().refresh('http://127.0.0.1:$port/ads.txt');
    expect(result.failure, RuleListFailure.network);
  });

  test('при поднятом туннеле запрос идёт через локальный инбаунд', () async {
    final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => proxy.close(force: true));
    final viaProxy = <String?>[];
    proxy.listen((request) {
      viaProxy.add(request.headers.host);
      request.response
        ..write('ads.example\n')
        ..close();
    });

    final s = RuleListService(
      root: () async => root,
      allowPlainHttp: true,
      localProxyPort: () => proxy.port,
    );
    final result = await s.refresh('http://lists.example/ads.txt');
    expect(viaProxy, ['lists.example']);
    expect(result.domains, 1);
  });

  test('чистка оставляет только списки, на которые есть ссылки', () async {
    bodies['/keep.txt'] = 'keep.example\n';
    bodies['/drop.txt'] = 'drop.example\n';
    final s = service();
    await s.refresh(url('/keep.txt'));
    await s.refresh(url('/drop.txt'));

    await s.prune({url('/keep.txt')});

    expect((await s.status(url('/keep.txt'))).loaded, isTrue);
    expect((await s.status(url('/drop.txt'))).loaded, isFalse);
    final names = root
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .toList();
    expect(names, hasLength(2), reason: 'список и его описание: $names');
  });
}
