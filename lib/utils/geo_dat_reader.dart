import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Чтение geo-баз в формате v2fly (`geoip.dat` / `geosite.dat`).
///
/// Формат — protobuf v2fly:
/// `GeoIPList { repeated GeoIP entry = 1 }` / `GeoSiteList { repeated GeoSite
/// entry = 1 }`. У записи первое поле — `string country_code = 1`, второе —
/// `repeated CIDR cidr = 2` (geoip) либо `repeated Domain domain = 2` (geosite).
///
/// Разбор тела записи (домены/CIDR) нужен `tool/geo_merge.dart`: он переносит
/// отдельные коды из чужих баз в нашу и печатает, что именно перенёс.
class GeoDatReader {
  GeoDatReader._();

  /// Заголовка (тег + два varint'а + сам код) с запасом хватает: самый длинный
  /// код в базах — порядка 30 символов.
  static const _headerWindow = 96;
  static const _entryTag = 0x0a;
  static const _maxCodeLength = 64;

  /// Записи верхнего уровня: код и границы тела. Тело не читаем — geoip.dat
  /// весит ~23 МБ, целиком в память его тянуть незачем.
  ///
  /// Пустой список — файла нет либо он не похож на v2fly-protobuf (битую базу
  /// разбор не должен ронять: вызывающий просто останется без индекса).
  static Future<List<GeoDatRecord>> records(File file) async {
    final out = <GeoDatRecord>[];
    RandomAccessFile? raf;
    try {
      if (!await file.exists()) return out;
      raf = await file.open();
      final length = await raf.length();
      var pos = 0;
      while (pos < length) {
        final window = math.min(_headerWindow, length - pos);
        await raf.setPosition(pos);
        final header = await raf.read(window);
        if (header.length < 2) break;
        // Верхний уровень — только `repeated entry = 1` (тег 0x0a).
        if (header[0] != _entryTag) break;

        final entryLen = readVarint(header, 1);
        if (entryLen == null || entryLen.value <= 0) break;
        final bodyStart = pos + 1 + entryLen.size;
        final nextPos = bodyStart + entryLen.value;
        if (nextPos <= pos) break; // защита от зацикливания на битом файле

        final code = _readCountryCode(header, 1 + entryLen.size);
        if (code != null) {
          out.add(
            GeoDatRecord(
              code: code,
              bodyStart: bodyStart,
              bodyLength: entryLen.value,
            ),
          );
        }
        pos = nextPos;
      }
    } catch (_) {
      // Битый/недоступный файл: отдаём то, что успели разобрать.
    } finally {
      await raf?.close();
    }
    return out;
  }

  /// Коды верхнего уровня в нижнем регистре (в файлах они заглавные, в
  /// правилах — как придётся).
  static Future<Set<String>> codes(File file) async =>
      {for (final r in await records(file)) r.code};

  /// Тело записи с кодом [code] или null, если такой записи нет.
  static Future<Uint8List?> entryBody(File file, String code) async {
    final wanted = code.trim().toLowerCase();
    if (wanted.isEmpty) return null;
    final record = (await records(file))
        .cast<GeoDatRecord?>()
        .firstWhere((r) => r!.code == wanted, orElse: () => null);
    if (record == null) return null;
    RandomAccessFile? raf;
    try {
      raf = await file.open();
      await raf.setPosition(record.bodyStart);
      final body = await raf.read(record.bodyLength);
      return body.length == record.bodyLength ? body : null;
    } catch (_) {
      return null;
    } finally {
      await raf?.close();
    }
  }

  /// Домены записи geosite.dat. Пустой список — записи нет или тело битое.
  static Future<List<GeoDomain>> domains(File file, String code) async {
    final body = await entryBody(file, code);
    if (body == null) return const [];
    return parseDomains(body);
  }

  /// CIDR'ы записи geoip.dat в текстовом виде (`1.2.3.0/24`, `2001:db8::/32`).
  static Future<List<String>> cidrs(File file, String code) async {
    final body = await entryBody(file, code);
    if (body == null) return const [];
    return parseCidrs(body);
  }

  /// `repeated Domain domain = 2` из тела GeoSite.
  static List<GeoDomain> parseDomains(Uint8List body) {
    final out = <GeoDomain>[];
    for (final field in _fields(body)) {
      if (field.number != 2 || field.bytes == null) continue;
      final domain = _parseDomain(field.bytes!);
      if (domain != null) out.add(domain);
    }
    return out;
  }

  /// `repeated CIDR cidr = 2` из тела GeoIP.
  static List<String> parseCidrs(Uint8List body) {
    final out = <String>[];
    for (final field in _fields(body)) {
      if (field.number != 2 || field.bytes == null) continue;
      final cidr = _parseCidr(field.bytes!);
      if (cidr != null) out.add(cidr);
    }
    return out;
  }

  /// `Domain { Type type = 1; string value = 2; }` — атрибуты (поле 3) не нужны:
  /// правила приложения ссылаются на код целиком, без `@attr`-фильтров.
  static GeoDomain? _parseDomain(Uint8List bytes) {
    var type = GeoDomainType.plain;
    String? value;
    for (final field in _fields(bytes)) {
      if (field.number == 1 && field.varint != null) {
        type = GeoDomainType.fromWire(field.varint!);
      } else if (field.number == 2 && field.bytes != null) {
        value = _utf8(field.bytes!);
      }
    }
    if (value == null || value.isEmpty) return null;
    return GeoDomain(type: type, value: value);
  }

  /// `CIDR { bytes ip = 1; uint32 prefix = 2; }`. ip — 4 или 16 байт.
  static String? _parseCidr(Uint8List bytes) {
    Uint8List? ip;
    var prefix = -1;
    for (final field in _fields(bytes)) {
      if (field.number == 1 && field.bytes != null) {
        ip = field.bytes;
      } else if (field.number == 2 && field.varint != null) {
        prefix = field.varint!;
      }
    }
    if (ip == null || (ip.length != 4 && ip.length != 16)) return null;
    // prefix = 0 легитимен (0.0.0.0/0), поэтому отличаем «не пришло» (-1).
    final bits = prefix < 0 ? ip.length * 8 : prefix;
    if (bits > ip.length * 8) return null;
    try {
      return '${InternetAddress.fromRawAddress(ip).address}/$bits';
    } catch (_) {
      return null;
    }
  }

  static String _utf8(Uint8List bytes) {
    try {
      return String.fromCharCodes(bytes);
    } catch (_) {
      return '';
    }
  }

  /// Поля protobuf-сообщения: только те wire-типы, что встречаются в geo-базах
  /// (varint и length-delimited). Всё остальное обрывает разбор — молча, чтобы
  /// чужой .dat не ронял приложение.
  static Iterable<_ProtoField> _fields(Uint8List bytes) sync* {
    var pos = 0;
    while (pos < bytes.length) {
      final key = readVarint(bytes, pos);
      if (key == null) return;
      pos += key.size;
      final number = key.value >> 3;
      final wire = key.value & 0x7;
      switch (wire) {
        case 0:
          final v = readVarint(bytes, pos);
          if (v == null) return;
          pos += v.size;
          yield _ProtoField(number: number, varint: v.value);
        case 2:
          final len = readVarint(bytes, pos);
          if (len == null) return;
          pos += len.size;
          final end = pos + len.value;
          if (len.value < 0 || end > bytes.length) return;
          yield _ProtoField(
            number: number,
            bytes: Uint8List.sublistView(bytes, pos, end),
          );
          pos = end;
        default:
          return; // fixed32/fixed64/группы в geo-базах не встречаются
      }
    }
  }

  /// `string country_code = 1` в начале записи. null — если первое поле другое
  /// (у v2fly оно всегда country_code, но чужой .dat ломать нас не должен).
  static String? _readCountryCode(Uint8List header, int offset) {
    if (offset >= header.length || header[offset] != _entryTag) return null;
    final len = readVarint(header, offset + 1);
    if (len == null || len.value <= 0 || len.value > _maxCodeLength) return null;
    final start = offset + 1 + len.size;
    final end = start + len.value;
    if (end > header.length) return null;
    return String.fromCharCodes(header, start, end).toLowerCase();
  }

  /// protobuf varint; [size] — сколько байт занял.
  static ({int value, int size})? readVarint(Uint8List bytes, int offset) {
    var value = 0;
    var shift = 0;
    var i = offset;
    while (i < bytes.length && shift <= 56) {
      final byte = bytes[i];
      value |= (byte & 0x7f) << shift;
      i++;
      if (byte & 0x80 == 0) return (value: value, size: i - offset);
      shift += 7;
    }
    return null;
  }
}

/// Запись верхнего уровня .dat: код и границы её тела в файле.
class GeoDatRecord {
  const GeoDatRecord({
    required this.code,
    required this.bodyStart,
    required this.bodyLength,
  });

  /// Код в нижнем регистре.
  final String code;
  final int bodyStart;
  final int bodyLength;
}

/// Тип домена из geosite.dat (`Domain.Type` в proto v2fly).
enum GeoDomainType {
  /// Подстрока — у v2fly почти не используется, для sing-box переводим в regex.
  plain,
  regex,

  /// Корневой домен: сам домен и все поддомены (`domain_suffix` в sing-box).
  domain,

  /// Точное совпадение (`domain` в sing-box).
  full;

  static GeoDomainType fromWire(int wire) => switch (wire) {
        1 => GeoDomainType.regex,
        2 => GeoDomainType.domain,
        3 => GeoDomainType.full,
        _ => GeoDomainType.plain,
      };
}

/// Один домен записи geosite.
class GeoDomain {
  const GeoDomain({required this.type, required this.value});

  final GeoDomainType type;
  final String value;
}

class _ProtoField {
  const _ProtoField({required this.number, this.varint, this.bytes});

  final int number;
  final int? varint;
  final Uint8List? bytes;
}
