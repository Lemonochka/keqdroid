import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/app_icon_cache.dart';

/// Однопиксельный PNG в base64 — содержимое неважно, важен сам факт байтов.
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

/// Выемка иконок под контролем теста: каждый вызов виден и завершается вручную.
class _FakeFetch {
  final calls = <String>[];
  final _pending = <String, Completer<String?>>{};

  Future<String?> call(String path) {
    calls.add(path);
    return (_pending[path] ??= Completer<String?>()).future;
  }

  void complete(String path, String? value) => _pending.remove(path)!.complete(value);
  bool isPending(String path) => _pending.containsKey(path);
}

void main() {
  test('иконка достаётся один раз, дальше отдаётся из кэша', () async {
    final fetch = _FakeFetch();
    final cache = AppIconCache(fetch.call);

    final first = cache.request('a.exe');
    fetch.complete('a.exe', _png);
    expect(await first, isNotNull);

    expect(cache.has('a.exe'), isTrue);
    expect(await cache.request('a.exe'), isNotNull);
    expect(fetch.calls, ['a.exe']);
  });

  test('«иконки нет» тоже запоминается', () async {
    final fetch = _FakeFetch();
    final cache = AppIconCache(fetch.call);

    final first = cache.request('none.exe');
    fetch.complete('none.exe', '');
    expect(await first, isNull);

    // Без запоминания отрицательного ответа exe без иконки дёргался бы заново
    // на каждом появлении строки.
    expect(cache.has('none.exe'), isTrue);
    await cache.request('none.exe');
    expect(fetch.calls, ['none.exe']);
  });

  test('в полёте не больше maxConcurrent запросов', () async {
    final fetch = _FakeFetch();
    final cache = AppIconCache(fetch.call, maxConcurrent: 2);

    for (final path in ['a', 'b', 'c', 'd']) {
      unawaited(cache.request(path));
    }

    // Первые два ушли в работу сразу, остальные ждут — канал не заваливается.
    expect(fetch.calls, ['a', 'b']);

    fetch.complete('a', _png);
    await Future<void>.delayed(Duration.zero);

    // Очередь разбирается с конца: свежий запрос — это то, что сейчас перед
    // глазами, а «c» к этому моменту уже уехало вверх.
    expect(fetch.calls, ['a', 'b', 'd']);
  });

  test('улетевшая с экрана строка забирает свой запрос', () async {
    final fetch = _FakeFetch();
    final cache = AppIconCache(fetch.call, maxConcurrent: 1);

    unawaited(cache.request('visible'));
    final dropped = cache.request('scrolled-away');
    // Первый запрос уже в работе, второй ждёт очереди — и не дожидается.
    cache.release('scrolled-away');

    fetch.complete('visible', _png);
    await Future<void>.delayed(Duration.zero);

    expect(fetch.calls, ['visible']);
    expect(cache.has('scrolled-away'), isFalse);
    // Ожидание брошенной строки закрывается сразу, а не висит навсегда.
    expect(await dropped.timeout(const Duration(seconds: 1)), isNull);
  });

  test('уже начатый запрос доводится до конца и попадает в кэш', () async {
    final fetch = _FakeFetch();
    final cache = AppIconCache(fetch.call, maxConcurrent: 1);

    unawaited(cache.request('started'));
    cache.release('started');
    expect(fetch.isPending('started'), isTrue);

    fetch.complete('started', _png);
    await Future<void>.delayed(Duration.zero);

    // Работа всё равно сделана — глупо выбрасывать результат.
    expect(cache.has('started'), isTrue);
    expect(cache.peek('started'), base64Decode(_png));
  });

  test('две строки одного exe дают один вызов', () async {
    final fetch = _FakeFetch();
    final cache = AppIconCache(fetch.call);

    final a = cache.request('same.exe');
    final b = cache.request('same.exe');
    fetch.complete('same.exe', _png);

    expect(await a, isNotNull);
    expect(await b, isNotNull);
    expect(fetch.calls, ['same.exe']);
  });

  test('кэш не растёт бесконечно', () async {
    final fetch = _FakeFetch();
    final cache = AppIconCache(fetch.call, maxEntries: 2);

    for (final path in ['a', 'b', 'c']) {
      final future = cache.request(path);
      fetch.complete(path, _png);
      await future;
    }

    expect(cache.has('a'), isFalse);
    expect(cache.has('b'), isTrue);
    expect(cache.has('c'), isTrue);
  });
}
