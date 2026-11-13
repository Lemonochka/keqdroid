import 'dart:convert';
import 'dart:typed_data';

class ZipEntry {
  ZipEntry({
    required this.versionMadeBy,
    required this.versionNeeded,
    required this.flags,
    required this.method,
    required this.modTime,
    required this.modDate,
    required this.crc32,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.nameBytes,
    required this.centralExtra,
    required this.comment,
    required this.internalAttrs,
    required this.externalAttrs,
    required this.localHeaderOffset,
  });

  final int versionMadeBy;
  final int versionNeeded;
  final int flags;
  final int method;
  final int modTime;
  final int modDate;
  final int crc32;
  final int compressedSize;
  final int uncompressedSize;
  // имя байтами: обратно пишется как было, с обратными косыми из Compress-Archive
  final Uint8List nameBytes;
  final Uint8List centralExtra;
  final Uint8List comment;
  final int internalAttrs;
  final int externalAttrs;
  final int localHeaderOffset;

  String get name => utf8.decode(nameBytes, allowMalformed: true);
  bool get isEncrypted => flags & 0x01 != 0;
  bool get hasDataDescriptor => flags & 0x08 != 0;

  // одинаковые метод, CRC и оба размера: те же сжатые байты у одного и того же упаковщика
  String get contentKey =>
      '$method:$crc32:$compressedSize:$uncompressedSize';
}

class ZipEnd {
  const ZipEnd({
    required this.centralDirectoryOffset,
    required this.centralDirectorySize,
    required this.entryCount,
    required this.comment,
  });

  final int centralDirectoryOffset;
  final int centralDirectorySize;
  final int entryCount;
  final Uint8List comment;
}

abstract final class ZipLayout {
  static const localHeaderSize = 30;
  static const _localSig = 0x04034b50;
  static const _centralSig = 0x02014b50;
  static const _endSig = 0x06054b50;

  // zip64 не нужен: и APK, и архив Windows меньше 4 ГБ
  static ZipEnd? findEnd(Uint8List tail) {
    final data = ByteData.sublistView(tail);
    for (var i = tail.length - 22; i >= 0; i--) {
      if (data.getUint32(i, Endian.little) != _endSig) continue;
      final commentLength = data.getUint16(i + 20, Endian.little);
      if (i + 22 + commentLength != tail.length) continue;
      final count = data.getUint16(i + 10, Endian.little);
      final size = data.getUint32(i + 12, Endian.little);
      final offset = data.getUint32(i + 16, Endian.little);
      if (count == 0xFFFF || size == 0xFFFFFFFF || offset == 0xFFFFFFFF) {
        return null;
      }
      return ZipEnd(
        centralDirectoryOffset: offset,
        centralDirectorySize: size,
        entryCount: count,
        comment: Uint8List.fromList(tail.sublist(i + 22)),
      );
    }
    return null;
  }

  static List<ZipEntry> parseCentralDirectory(Uint8List cd, int entryCount) {
    final data = ByteData.sublistView(cd);
    final entries = <ZipEntry>[];
    var p = 0;
    for (var n = 0; n < entryCount; n++) {
      if (p + 46 > cd.length || data.getUint32(p, Endian.little) != _centralSig) {
        throw const FormatException('broken zip central directory');
      }
      final nameLength = data.getUint16(p + 28, Endian.little);
      final extraLength = data.getUint16(p + 30, Endian.little);
      final commentLength = data.getUint16(p + 32, Endian.little);
      final end = p + 46 + nameLength + extraLength + commentLength;
      if (end > cd.length) {
        throw const FormatException('broken zip central directory');
      }
      final entry = ZipEntry(
        versionMadeBy: data.getUint16(p + 4, Endian.little),
        versionNeeded: data.getUint16(p + 6, Endian.little),
        flags: data.getUint16(p + 8, Endian.little),
        method: data.getUint16(p + 10, Endian.little),
        modTime: data.getUint16(p + 12, Endian.little),
        modDate: data.getUint16(p + 14, Endian.little),
        crc32: data.getUint32(p + 16, Endian.little),
        compressedSize: data.getUint32(p + 20, Endian.little),
        uncompressedSize: data.getUint32(p + 24, Endian.little),
        internalAttrs: data.getUint16(p + 36, Endian.little),
        externalAttrs: data.getUint32(p + 38, Endian.little),
        localHeaderOffset: data.getUint32(p + 42, Endian.little),
        nameBytes: Uint8List.fromList(cd.sublist(p + 46, p + 46 + nameLength)),
        centralExtra: Uint8List.fromList(
          cd.sublist(p + 46 + nameLength, p + 46 + nameLength + extraLength),
        ),
        comment: Uint8List.fromList(
          cd.sublist(p + 46 + nameLength + extraLength, end),
        ),
      );
      if (entry.compressedSize == 0xFFFFFFFF ||
          entry.uncompressedSize == 0xFFFFFFFF ||
          entry.localHeaderOffset == 0xFFFFFFFF) {
        throw const FormatException('zip64 entries are not supported');
      }
      entries.add(entry);
      p = end;
    }
    return entries;
  }

  static int? localHeaderLength(Uint8List header) {
    if (header.length < localHeaderSize) return null;
    final data = ByteData.sublistView(header);
    if (data.getUint32(0, Endian.little) != _localSig) return null;
    return localHeaderSize +
        data.getUint16(26, Endian.little) +
        data.getUint16(28, Endian.little);
  }

  static Uint8List localExtra(Uint8List header) {
    final data = ByteData.sublistView(header);
    final nameLength = data.getUint16(26, Endian.little);
    final extraLength = data.getUint16(28, Endian.little);
    final start = localHeaderSize + nameLength;
    return Uint8List.fromList(header.sublist(start, start + extraLength));
  }

  static final _crcTable = List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    return c;
  });

  static int crc32(List<int> bytes) {
    var crc = 0xFFFFFFFF;
    for (final b in bytes) {
      crc = _crcTable[(crc ^ b) & 0xFF] ^ (crc >> 8);
    }
    return crc ^ 0xFFFFFFFF;
  }
}

class ZipWriter {
  final _out = BytesBuilder(copy: false);
  final _central = BytesBuilder();
  var _count = 0;

  int get offset => _out.length;

  // alignTo: выравнивание данных несжатой записи полем 0xD935, как у AGP
  void add(
    ZipEntry template, {
    required int method,
    required Uint8List data,
    Uint8List? localExtra,
    int alignTo = 0,
  }) {
    final headerOffset = _out.length;
    final name = template.nameBytes;
    var extra = localExtra ?? Uint8List(0);
    if (alignTo > 0) {
      final base = headerOffset + ZipLayout.localHeaderSize + name.length + 6;
      final pad = (alignTo - base % alignTo) % alignTo;
      extra = Uint8List(6 + pad);
      ByteData.sublistView(extra)
        ..setUint16(0, 0xD935, Endian.little)
        ..setUint16(2, 2 + pad, Endian.little)
        ..setUint16(4, alignTo, Endian.little);
    }
    final flags = template.flags & ~0x08;

    final local = ByteData(ZipLayout.localHeaderSize)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, template.versionNeeded, Endian.little)
      ..setUint16(6, flags, Endian.little)
      ..setUint16(8, method, Endian.little)
      ..setUint16(10, template.modTime, Endian.little)
      ..setUint16(12, template.modDate, Endian.little)
      ..setUint32(14, template.crc32, Endian.little)
      ..setUint32(18, data.length, Endian.little)
      ..setUint32(22, template.uncompressedSize, Endian.little)
      ..setUint16(26, name.length, Endian.little)
      ..setUint16(28, extra.length, Endian.little);
    _out
      ..add(local.buffer.asUint8List())
      ..add(name)
      ..add(extra)
      ..add(data);

    final central = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, template.versionMadeBy, Endian.little)
      ..setUint16(6, template.versionNeeded, Endian.little)
      ..setUint16(8, flags, Endian.little)
      ..setUint16(10, method, Endian.little)
      ..setUint16(12, template.modTime, Endian.little)
      ..setUint16(14, template.modDate, Endian.little)
      ..setUint32(16, template.crc32, Endian.little)
      ..setUint32(20, data.length, Endian.little)
      ..setUint32(24, template.uncompressedSize, Endian.little)
      ..setUint16(28, name.length, Endian.little)
      ..setUint16(30, template.centralExtra.length, Endian.little)
      ..setUint16(32, template.comment.length, Endian.little)
      ..setUint16(34, 0, Endian.little)
      ..setUint16(36, template.internalAttrs, Endian.little)
      ..setUint32(38, template.externalAttrs, Endian.little)
      ..setUint32(42, headerOffset, Endian.little);
    _central
      ..add(central.buffer.asUint8List())
      ..add(name)
      ..add(template.centralExtra)
      ..add(template.comment);
    _count++;
  }

  Uint8List finish({Uint8List? comment}) {
    final cdOffset = _out.length;
    final cd = _central.takeBytes();
    final note = comment ?? Uint8List(0);
    final end = ByteData(22)
      ..setUint32(0, 0x06054b50, Endian.little)
      ..setUint16(8, _count, Endian.little)
      ..setUint16(10, _count, Endian.little)
      ..setUint32(12, cd.length, Endian.little)
      ..setUint32(16, cdOffset, Endian.little)
      ..setUint16(20, note.length, Endian.little);
    _out
      ..add(cd)
      ..add(end.buffer.asUint8List())
      ..add(note);
    return _out.takeBytes();
  }
}
