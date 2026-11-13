import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/zip_layout.dart';

import '../helpers/zip_fixture.dart';

void main() {
  test('CRC32 совпадает с эталонным значением', () {
    expect(ZipLayout.crc32(ascii.encode('123456789')), 0xCBF43926);
    expect(ZipLayout.crc32(const []), 0);
  });

  test('записанный zip читается обратно: имена байтами, даты, атрибуты', () {
    final entries = [
      FixtureEntry(r'data\app.so', textBytes(5000, 1), modTime: 0x1234),
      FixtureEntry('icon.png', randomBytes(300, 2), method: 0),
      FixtureEntry('пусто.txt', Uint8List(0), externalAttrs: 0x81A40000),
    ];
    final zip = buildZip(entries);
    final read = readEntries(zip);

    expect(read, hasLength(3));
    for (var i = 0; i < entries.length; i++) {
      expect(read[i].nameBytes, utf8.encode(entries[i].name));
      expect(read[i].method, entries[i].method);
      expect(read[i].modTime, entries[i].modTime);
      expect(read[i].externalAttrs, entries[i].externalAttrs);
      expect(contentOf(zip, read[i]), entries[i].content);
    }
    expect(read[0].name, r'data\app.so');
  });

  test('данные несжатой записи начинаются с границы выравнивания', () {
    final writer = ZipWriter();
    for (final (name, align) in [('a.bin', 4), ('lib/x.so', 16384)]) {
      final e = FixtureEntry(name, randomBytes(1000, align), method: 0);
      writer.add(
        fixtureTemplate(e, compressedSize: e.content.length),
        method: 0,
        data: e.content,
        alignTo: align,
      );
    }
    final zip = writer.finish();
    final read = readEntries(zip);
    expect(dataOffset(zip, read[0]) % 4, 0);
    expect(dataOffset(zip, read[1]) % 16384, 0);
  });

  test('конец архива находится и с комментарием', () {
    final writer = ZipWriter();
    final e = FixtureEntry('a', textBytes(100, 3));
    final data = deflateRaw(e.content);
    writer.add(fixtureTemplate(e, compressedSize: data.length),
        method: 8, data: data);
    final zip = writer.finish(comment: Uint8List.fromList(ascii.encode('hi')));

    final end = ZipLayout.findEnd(zip)!;
    expect(end.entryCount, 1);
    expect(ascii.decode(end.comment), 'hi');
  });

  test('zip64 не читается, вместо того чтобы читаться криво', () {
    final zip = buildZip([FixtureEntry('a', textBytes(100, 4))]);
    ByteData.sublistView(zip).setUint16(zip.length - 22 + 10, 0xFFFF, Endian.little);
    expect(ZipLayout.findEnd(zip), isNull);
  });
}
