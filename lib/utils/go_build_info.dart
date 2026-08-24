import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Версии, зашитые в Go-бинарь — то же, что печатает `go version -m`.
///
/// Зачем: все ядра приложения — Go-бинари, и своей команды `version` у них
/// может не быть вовсе (keqrnel трактует первый аргумент как путь к конфигу и
/// падает на `keqrnel version` с «read config: open version»). Зато компоновщик
/// Go кладёт в каждый бинарь блок build info: версия тулчейна и версии ВСЕХ
/// модулей, включая вкомпилированные движки. Так «какое ядро и какой версии»
/// читается прямо из файла, не запуская процесс, — на Android это ещё и
/// единственный дешёвый способ (fork ядра ради строчки версии там ни к чему).
class GoBuildInfo {
  const GoBuildInfo({
    required this.goVersion,
    required this.modulePath,
    required this.moduleVersion,
    required this.deps,
    this.settings = const {},
  });

  /// Версия тулчейна, например `go1.26.0`.
  final String goVersion;

  /// Путь модуля самой программы, например `keqrnel`.
  final String? modulePath;

  /// Версия самой программы. У собранной из рабочего дерева — `(devel)`:
  /// keqrnel собирается именно так, поэтому на него не рассчитываем.
  final String? moduleVersion;

  /// Версии зависимостей: полный путь модуля → версия.
  final Map<String, String> deps;

  /// Настройки сборки (`build`-строки `go version -m`): `-tags`, `GOOS`,
  /// `CGO_ENABLED` и прочее. Пустая карта — бинарь собран Go без них.
  final Map<String, String> settings;

  /// Теги сборки из `-tags`. Пусто — тегов не было ЛИБО настроек в бинаре нет
  /// вовсе; отличать эти случаи должен вызывающий (см. [hasBuildSettings]).
  Set<String> get buildTags {
    final raw = settings['-tags'];
    if (raw == null || raw.trim().isEmpty) return const {};
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  /// Есть ли в бинаре блок настроек сборки. Без него «тега нет» означает лишь
  /// «неизвестно», и решать по нему нельзя.
  bool get hasBuildSettings => settings.isNotEmpty;

  /// Версия зависимости, чей путь оканчивается на [suffix]:
  /// `depVersion('xtls/xray-core')` → `v1.260327.1-…`. Null — нет такой.
  String? depVersion(String suffix) {
    for (final entry in deps.entries) {
      if (entry.key == suffix || entry.key.endsWith('/$suffix')) {
        return entry.value;
      }
    }
    return null;
  }

  /// `\xff Go buildinf:` — метка начала блока.
  static const magic = <int>[
    0xff, 0x20, 0x47, 0x6f, 0x20, 0x62, 0x75, 0x69, //
    0x6c, 0x64, 0x69, 0x6e, 0x66, 0x3a,
  ];

  /// Версия и модули лежат в самом заголовке, а не по указателям (Go 1.18+).
  static const _flagVersionInline = 0x2;

  /// Заголовок фиксированной длины: метка, размер указателя, флаги и два слота
  /// под указатели. В inline-варианте слоты нулевые, но НЕ исчезают — строки
  /// начинаются только после них.
  static const _headerLength = 32;

  /// Блок модулей обрамлён двумя 16-байтовыми маркерами — их Go вставляет,
  /// чтобы блок можно было найти и в бинаре без build info.
  static const _frameLength = 16;

  /// Разбор блока, начинающегося с [magic] в начале [bytes].
  ///
  /// Null — не наш блок, старый (не inline) формат или обрезанные данные:
  /// панель просто покажет ядро без версии, это не ошибка.
  static GoBuildInfo? parse(Uint8List bytes) {
    if (bytes.length < _headerLength) return null;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return null;
    }
    final flags = bytes[magic.length + 1];
    if (flags & _flagVersionInline == 0) {
      // Go младше 1.18: строки лежат по указателям, а их разбор требует
      // разбирать ещё и секции PE/ELF. Наши ядра собраны новее.
      return null;
    }

    final version = _readBytes(bytes, _headerLength);
    if (version == null) return null;

    final modinfo = _readBytes(bytes, version.end);
    if (modinfo == null) return null;

    return _fromModInfo(
      utf8.decode(version.value, allowMalformed: true),
      _stripFrame(modinfo.value),
    );
  }

  /// Читает build info из файла [file]. Null — файла нет, он не Go-бинарь или
  /// прочитать не вышло.
  static Future<GoBuildInfo?> fromFile(File file) async {
    RandomAccessFile? handle;
    try {
      handle = await file.open();
      final length = await handle.length();
      final start = await _findMagic(handle, length);
      if (start == null) return null;
      await handle.setPosition(start);
      // Блок модулей у keqrnel — несколько килобайт; мегабайта хватает
      // с запасом, а читать весь 60-мегабайтный файл незачем.
      final window = await handle.read(
        (length - start).clamp(0, 1 << 20).toInt(),
      );
      return parse(window);
    } catch (_) {
      return null;
    } finally {
      await handle?.close();
    }
  }

  /// Позиция метки в файле. Ищем чтением кусками с перекрытием: бинарь ядра
  /// весит десятки мегабайт, и втягивать его в память целиком (тем более на
  /// телефоне) ради четырнадцати байт не нужно.
  static Future<int?> _findMagic(RandomAccessFile handle, int length) async {
    const chunkSize = 1 << 20;
    final overlap = magic.length - 1;
    var position = 0;
    while (position < length) {
      await handle.setPosition(position);
      final chunk = await handle.read(chunkSize);
      if (chunk.isEmpty) return null;
      final found = _indexOfMagic(chunk);
      if (found >= 0) return position + found;
      if (chunk.length < chunkSize) return null;
      position += chunkSize - overlap;
    }
    return null;
  }

  static int _indexOfMagic(Uint8List haystack) {
    final limit = haystack.length - magic.length;
    outer:
    for (var i = 0; i <= limit; i++) {
      if (haystack[i] != magic[0]) continue;
      for (var j = 1; j < magic.length; j++) {
        if (haystack[i + j] != magic[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  static GoBuildInfo _fromModInfo(String goVersion, String modinfo) {
    String? modulePath;
    String? moduleVersion;
    final deps = <String, String>{};
    final settings = <String, String>{};
    for (final line in const LineSplitter().convert(modinfo)) {
      final parts = line.split('\t');
      // `build`-строка короче остальных: ключ и значение, без хеша.
      if (parts.length == 2 && parts[0] == 'build') {
        final eq = parts[1].indexOf('=');
        if (eq > 0) {
          settings[parts[1].substring(0, eq)] = parts[1].substring(eq + 1);
        }
        continue;
      }
      if (parts.length < 3) continue;
      switch (parts[0]) {
        case 'mod':
          modulePath = parts[1];
          moduleVersion = parts[2];
        case 'dep':
          deps[parts[1]] = parts[2];
        // `=>` (replace) панели не нужен.
      }
    }
    return GoBuildInfo(
      goVersion: goVersion,
      modulePath: modulePath,
      moduleVersion: moduleVersion,
      deps: Map.unmodifiable(deps),
      settings: Map.unmodifiable(settings),
    );
  }

  /// Снимает маркеры и декодирует. Режем по БАЙТАМ до декодирования: маркеры
  /// не являются валидным UTF-8, и после декодирования с allowMalformed их
  /// длина в символах уже не равна шестнадцати — срез уехал бы в текст.
  /// Проверка на `\n` перед хвостовым маркером — как в самом Go.
  static String _stripFrame(Uint8List modinfo) {
    if (modinfo.length < 2 * _frameLength + 1) return '';
    if (modinfo[modinfo.length - _frameLength - 1] != 0x0a) return '';
    return utf8.decode(
      modinfo.sublist(_frameLength, modinfo.length - _frameLength),
      allowMalformed: true,
    );
  }

  /// Байты с длиной-uvarint впереди.
  static _Slice? _readBytes(Uint8List bytes, int offset) {
    final length = _readUvarint(bytes, offset);
    if (length == null) return null;
    final start = length.end;
    final end = start + length.value;
    if (end > bytes.length) return null;
    return _Slice(bytes.sublist(start, end), end);
  }

  static _Uvarint? _readUvarint(Uint8List bytes, int offset) {
    var value = 0;
    var shift = 0;
    var index = offset;
    while (index < bytes.length) {
      final byte = bytes[index++];
      value |= (byte & 0x7f) << shift;
      if (byte & 0x80 == 0) return _Uvarint(value, index);
      shift += 7;
      if (shift > 35) return null;
    }
    return null;
  }
}

class _Slice {
  const _Slice(this.value, this.end);
  final Uint8List value;
  final int end;
}

class _Uvarint {
  const _Uvarint(this.value, this.end);
  final int value;
  final int end;
}
