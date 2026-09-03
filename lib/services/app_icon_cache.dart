/// Кэш иконок процессов для списка раздельного туннелирования.
///
/// На Windows иконки не приходят вместе со списком: каждая строка при
/// появлении на экране просила свою через канал платформы, а нативная сторона
/// доставала её из exe (GDI+, кодирование PNG, base64) ПРЯМО на потоке
/// платформы. При быстрой прокрутке это десятки таких вызовов подряд, и поток,
/// который обязан разбирать ввод и кадры, стоял в них — отсюда и рывки.
///
/// Здесь три вещи, которых не было:
///
///  * **кэш** — иконка одного exe достаётся ОДИН раз за жизнь приложения;
///    вернувшись к уже виденной строке, список не платит ничего;
///  * **очередь с ограничением** — в полёте не больше [maxConcurrent] запросов,
///    остальные ждут, а не заваливают канал;
///  * **отмена ненужного** — строка, улетевшая с экрана до того, как до неё
///    дошла очередь, свой запрос забирает. При прокрутке через весь список
///    работа делается только для тех строк, на которых действительно
///    остановились.
///
/// Очередь разбирается с конца (LIFO): самый свежий запрос — это то, что
/// сейчас перед глазами, а начало очереди к тому времени уже уехало вверх.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

class AppIconCache {
  AppIconCache(this._fetch, {this.maxConcurrent = 2, this.maxEntries = 512});

  /// Нативная выемка иконки: путь к exe → base64 PNG (или null/пусто).
  final Future<String?> Function(String path) _fetch;

  final int maxConcurrent;

  /// Потолок кэша. 512 строк по нескольку десятков килобайт — единицы мегабайт,
  /// и это дешевле, чем доставать те же иконки заново на каждой прокрутке.
  final int maxEntries;

  /// Готовые иконки. `null` — «иконки нет», такой ответ тоже кэшируем: без
  /// этого exe без иконки дёргался бы снова на каждом появлении строки.
  ///
  /// Map в Dart держит порядок вставки, поэтому вытеснять можно с начала.
  final _cache = <String, Uint8List?>{};

  /// Пути, ожидающие очереди (последний — ближайший к исполнению).
  final _queue = <String>[];

  /// Пути, по которым нативная сторона уже работает. Без этого второй строке
  /// с тем же exe (а такие бывают — один процесс в списке дважды) достался бы
  /// второй вызов: из очереди путь к тому моменту уже убран.
  final _inFlight = <String>{};

  /// Сколько строк ждут иконку по каждому пути: строка ушла с экрана —
  /// счётчик уменьшается, дошёл до нуля и запрос ещё не начат — выбрасываем.
  final _wanted = <String, int>{};

  final _waiters = <String, List<Completer<Uint8List?>>>{};

  int _active = 0;

  bool has(String path) => _cache.containsKey(path);

  /// Готовая иконка или `null` — и когда её нет, и когда ещё не загружали.
  /// Различать эти случаи нужно через [has].
  Uint8List? peek(String path) => _cache[path];

  /// Запрашивает иконку. Вызвавший обязан позвать [release] по этому же пути,
  /// когда строка уходит с экрана.
  Future<Uint8List?> request(String path) {
    if (path.isEmpty) return Future.value(null);
    _wanted.update(path, (n) => n + 1, ifAbsent: () => 1);
    if (_cache.containsKey(path)) return Future.value(_cache[path]);

    final completer = Completer<Uint8List?>();
    _waiters.putIfAbsent(path, () => []).add(completer);
    if (!_inFlight.contains(path) && !_queue.contains(path)) _queue.add(path);
    _pump();
    return completer.future;
  }

  /// Строка больше не ждёт иконку.
  void release(String path) {
    final left = (_wanted[path] ?? 0) - 1;
    if (left > 0) {
      _wanted[path] = left;
      return;
    }
    _wanted.remove(path);
    // Начатый запрос не отменяем — нативная сторона уже работает, и результат
    // всё равно попадёт в кэш; выбрасываем только то, что ещё не начиналось.
    if (_queue.remove(path)) {
      // Ожидающих закрываем сразу: иначе на каждой выброшенной строке
      // оставался бы висеть `Completer`, который уже некому завершить.
      _complete(path, null, cache: false);
    }
  }

  void _pump() {
    while (_active < maxConcurrent && _queue.isNotEmpty) {
      final path = _queue.removeLast();
      if ((_wanted[path] ?? 0) == 0) {
        _complete(path, null, cache: false);
        continue;
      }
      _active++;
      _inFlight.add(path);
      unawaited(_run(path));
    }
  }

  Future<void> _run(String path) async {
    Uint8List? bytes;
    try {
      final encoded = await _fetch(path);
      if (encoded != null && encoded.isNotEmpty) {
        bytes = base64Decode(encoded);
      }
    } catch (_) {
      // Нет иконки — не повод шуметь: строка просто останется с буквой.
      bytes = null;
    } finally {
      _active--;
      _inFlight.remove(path);
    }
    _complete(path, bytes);
    _pump();
  }

  void _complete(String path, Uint8List? bytes, {bool cache = true}) {
    if (cache) {
      _cache[path] = bytes;
      if (_cache.length > maxEntries) _cache.remove(_cache.keys.first);
    }
    final waiters = _waiters.remove(path);
    if (waiters == null) return;
    for (final completer in waiters) {
      if (!completer.isCompleted) completer.complete(bytes);
    }
  }
}
