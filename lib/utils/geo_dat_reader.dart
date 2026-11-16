import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

class GeoDatReader {
  GeoDatReader._();

  static const _headerWindow = 96;
  static const _entryTag = 0x0a;
  static const _maxCodeLength = 64;

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
    } catch (_) {} finally {
      await raf?.close();
    }
    return out;
  }

  static Future<Set<String>> codes(File file) async =>
      {for (final r in await records(file)) r.code};

  static Future<Uint8List?> entryBody(File file, String code) async {
    final wanted = code.trim().toLowerCase();
    if (wanted.isEmpty) return null;
    final record = (await records(file))
        .cast<GeoDatRecord?>()
        .firstWhere((r) => r!.code == wanted, orElse: () => null);
    if (record == null) return null;
    return bodyAt(file, record);
  }

  static Future<Uint8List?> bodyAt(File file, GeoDatRecord record) async {
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

  static Future<List<GeoDomain>> domains(File file, String code) async {
    final body = await entryBody(file, code);
    if (body == null) return const [];
    return parseDomains(body);
  }

  static Future<List<String>> cidrs(File file, String code) async {
    final body = await entryBody(file, code);
    if (body == null) return const [];
    return parseCidrs(body);
  }

  static List<GeoDomain> parseDomains(Uint8List body) {
    final out = <GeoDomain>[];
    for (final field in _fields(body)) {
      if (field.number != 2 || field.bytes == null) continue;
      final domain = _parseDomain(field.bytes!);
      if (domain != null) out.add(domain);
    }
    return out;
  }

  static List<String> parseCidrs(Uint8List body) {
    final out = <String>[];
    for (final field in _fields(body)) {
      if (field.number != 2 || field.bytes == null) continue;
      final cidr = _parseCidr(field.bytes!);
      if (cidr != null) out.add(cidr);
    }
    return out;
  }

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
    // prefix = 0 законный (0.0.0.0/0), поэтому не пришло это -1
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
          return;
      }
    }
  }

  static String? _readCountryCode(Uint8List header, int offset) {
    if (offset >= header.length || header[offset] != _entryTag) return null;
    final len = readVarint(header, offset + 1);
    if (len == null || len.value <= 0 || len.value > _maxCodeLength) return null;
    final start = offset + 1 + len.size;
    final end = start + len.value;
    if (end > header.length) return null;
    return String.fromCharCodes(header, start, end).toLowerCase();
  }

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

class GeoDatRecord {
  const GeoDatRecord({
    required this.code,
    required this.bodyStart,
    required this.bodyLength,
  });

  final String code;
  final int bodyStart;
  final int bodyLength;
}

enum GeoDomainType {
  plain,
  regex,

  domain,

  full;

  static GeoDomainType fromWire(int wire) => switch (wire) {
        1 => GeoDomainType.regex,
        2 => GeoDomainType.domain,
        3 => GeoDomainType.full,
        _ => GeoDomainType.plain,
      };
}

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
