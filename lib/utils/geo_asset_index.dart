import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Список кодов, которые реально лежат в geoip.dat / geosite.dat.
///
/// Зачем: списки маршрутизации — свободный текст, и `geosite:sberbank`
/// (нет в базе v2fly) выглядит для пользователя ровно так же, как
/// `geosite:yandex` (есть). Xray же на неизвестном коде НЕ игнорирует правило,
/// а падает на разборе конфига целиком — SOCKS-инбаунд не поднимается, и
/// подключение умирает с безымянным «SOCKS5 port 2080 not ready». Индекс
/// позволяет выкинуть такие токены до старта ядра.
///
/// Формат обоих файлов — protobuf v2fly:
/// `GeoIPList { repeated GeoIP entry = 1 }` / `GeoSiteList { repeated GeoSite
/// entry = 1 }`, где у записи первое поле — `string country_code = 1`.
/// Разбираем только заголовок каждой записи, тело (домены/CIDR) пропускаем
/// через seek: geoip.dat весит ~23 МБ, целиком в память его тянуть незачем.
class GeoAssetIndex {
  const GeoAssetIndex({
    required this.geoipCodes,
    required this.geositeCodes,
  });

  /// Пустой индекс: базы не найдены/не прочитались. Валидация при нём
  /// отключается — лучше отдать конфиг ядру как есть, чем выкинуть рабочее
  /// правило по итогам неудачного чтения.
  static const empty = GeoAssetIndex(geoipCodes: {}, geositeCodes: {});

  /// Коды в нижнем регистре (в файлах они заглавные, в правилах — как придётся).
  final Set<String> geoipCodes;
  final Set<String> geositeCodes;

  bool get isEmpty => geoipCodes.isEmpty && geositeCodes.isEmpty;

  /// Читает обе базы из каталога [dir] (там, где их ищет само ядро через
  /// `XRAY_LOCATION_ASSET`). Отсутствующий файл — пустое множество, не ошибка.
  static Future<GeoAssetIndex> fromDirectory(String dir) async {
    final geoip = await readCodes(File('$dir${Platform.pathSeparator}geoip.dat'));
    final geosite =
        await readCodes(File('$dir${Platform.pathSeparator}geosite.dat'));
    return GeoAssetIndex(geoipCodes: geoip, geositeCodes: geosite);
  }

  /// Коды верхнего уровня из одного .dat. Пустое множество, если файла нет
  /// или он не похож на v2fly-protobuf.
  static Future<Set<String>> readCodes(File file) async {
    final codes = <String>{};
    RandomAccessFile? raf;
    try {
      if (!await file.exists()) return codes;
      raf = await file.open();
      final length = await raf.length();
      var pos = 0;
      while (pos < length) {
        // Заголовка (тег + два varint'а + сам код) с запасом хватает: самый
        // длинный код в базах — порядка 30 символов.
        final window = math.min(_headerWindow, length - pos);
        await raf.setPosition(pos);
        final header = await raf.read(window);
        if (header.length < 2) break;
        // Верхний уровень — только `repeated entry = 1` (тег 0x0a).
        if (header[0] != _entryTag) break;

        final entryLen = _readVarint(header, 1);
        if (entryLen == null || entryLen.value <= 0) break;
        final bodyStart = pos + 1 + entryLen.size;
        final nextPos = bodyStart + entryLen.value;
        if (nextPos <= pos) break; // защита от зацикливания на битом файле

        final code = _readCountryCode(header, 1 + entryLen.size);
        if (code != null) codes.add(code);

        pos = nextPos;
      }
    } catch (_) {
      // Битый/недоступный файл: пустой индекс, валидация просто не применится.
    } finally {
      await raf?.close();
    }
    return codes;
  }

  static const _entryTag = 0x0a;
  static const _headerWindow = 96;
  static const _maxCodeLength = 64;

  /// `string country_code = 1` в начале записи. null — если первое поле другое
  /// (у v2fly оно всегда country_code, но чужой .dat ломать нас не должен).
  static String? _readCountryCode(Uint8List header, int offset) {
    if (offset >= header.length || header[offset] != _entryTag) return null;
    final len = _readVarint(header, offset + 1);
    if (len == null || len.value <= 0 || len.value > _maxCodeLength) return null;
    final start = offset + 1 + len.size;
    final end = start + len.value;
    if (end > header.length) return null;
    return String.fromCharCodes(header, start, end).toLowerCase();
  }

  /// protobuf varint; [size] — сколько байт занял.
  static ({int value, int size})? _readVarint(Uint8List bytes, int offset) {
    var value = 0;
    var shift = 0;
    var i = offset;
    while (i < bytes.length && shift <= 28) {
      final byte = bytes[i];
      value |= (byte & 0x7f) << shift;
      i++;
      if (byte & 0x80 == 0) return (value: value, size: i - offset);
      shift += 7;
    }
    return null;
  }
}
