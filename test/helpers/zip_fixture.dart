import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:keqdroid/utils/zip_layout.dart';

class FixtureEntry {
  FixtureEntry(
    this.name,
    this.content, {
    this.method = 8,
    this.level = 6,
    this.modTime = 0x6000,
    this.externalAttrs = 0x20,
  });

  final String name;
  final Uint8List content;
  final int method;
  final int level;
  final int modTime;
  final int externalAttrs;
}

Uint8List deflateRaw(List<int> content, {int level = 6}) =>
    Uint8List.fromList(ZLibEncoder(raw: true, level: level).convert(content));

Uint8List inflateRaw(List<int> data) =>
    Uint8List.fromList(ZLibDecoder(raw: true).convert(data));

Uint8List randomBytes(int length, int seed) {
  final random = Random(seed);
  return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
}

Uint8List textBytes(int length, int seed) {
  final random = Random(seed);
  const words = ['proxy ', 'route ', 'server ', 'dns ', 'tunnel ', 'rule '];
  final out = BytesBuilder();
  while (out.length < length) {
    out.add(words[random.nextInt(words.length)].codeUnits);
  }
  return Uint8List.sublistView(out.takeBytes(), 0, length);
}

ZipEntry fixtureTemplate(FixtureEntry e, {required int compressedSize}) =>
    ZipEntry(
      versionMadeBy: 20,
      versionNeeded: 20,
      flags: 0,
      method: e.method,
      modTime: e.modTime,
      modDate: 0x5B6D,
      crc32: ZipLayout.crc32(e.content),
      compressedSize: compressedSize,
      uncompressedSize: e.content.length,
      nameBytes: Uint8List.fromList(utf8.encode(e.name)),
      centralExtra: Uint8List(0),
      comment: Uint8List(0),
      internalAttrs: 0,
      externalAttrs: e.externalAttrs,
      localHeaderOffset: 0,
    );

// beforeDirectory ложится между данными и оглавлением, как блок подписи APK
Uint8List buildZip(List<FixtureEntry> entries, {Uint8List? beforeDirectory}) {
  final writer = ZipWriter();
  for (final e in entries) {
    final data =
        e.method == 8 ? deflateRaw(e.content, level: e.level) : e.content;
    writer.add(
      fixtureTemplate(e, compressedSize: data.length),
      method: e.method,
      data: data,
    );
  }
  final zip = writer.finish();
  if (beforeDirectory == null) return zip;

  final end = ZipLayout.findEnd(
    Uint8List.sublistView(zip, max(0, zip.length - 65557)),
  )!;
  final cd = end.centralDirectoryOffset;
  final out = BytesBuilder()
    ..add(Uint8List.sublistView(zip, 0, cd))
    ..add(beforeDirectory)
    ..add(Uint8List.sublistView(zip, cd));
  final bytes = out.takeBytes();
  ByteData.sublistView(bytes).setUint32(
    bytes.length - 22 + 16,
    cd + beforeDirectory.length,
    Endian.little,
  );
  return bytes;
}

List<ZipEntry> readEntries(Uint8List zip) {
  final end = ZipLayout.findEnd(
    Uint8List.sublistView(zip, max(0, zip.length - 65557)),
  )!;
  return ZipLayout.parseCentralDirectory(
    Uint8List.sublistView(
      zip,
      end.centralDirectoryOffset,
      end.centralDirectoryOffset + end.centralDirectorySize,
    ),
    end.entryCount,
  );
}

int dataOffset(Uint8List zip, ZipEntry e) =>
    e.localHeaderOffset +
    ZipLayout.localHeaderLength(Uint8List.sublistView(zip, e.localHeaderOffset))!;

Uint8List contentOf(Uint8List zip, ZipEntry e) {
  final start = dataOffset(zip, e);
  final data = Uint8List.sublistView(zip, start, start + e.compressedSize);
  return e.method == 8 ? inflateRaw(data) : Uint8List.fromList(data);
}
