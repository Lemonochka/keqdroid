import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/repack_zip.dart';
import '../helpers/zip_fixture.dart';

// переупаковка обязана менять только сжатые байты: всё, что увидит распаковщик, прежнее
void main() {
  Future<Map<int, Uint8List>> zlib9(Map<int, Uint8List> plain) async => {
        for (final MapEntry(:key, :value) in plain.entries)
          key: deflateRaw(value, level: 9),
      };

  final entries = [
    FixtureEntry('AndroidManifest.xml', textBytes(4000, 1), level: 1),
    FixtureEntry('resources.arsc', randomBytes(900, 2), method: 0),
    FixtureEntry(r'data\flutter_assets\a.txt', textBytes(60000, 3), level: 1,
        modTime: 0x7777, externalAttrs: 0x81A40000),
    FixtureEntry('lib/arm64-v8a/libx.so', textBytes(80000, 4), level: 1),
    FixtureEntry('assets/model.tflite', randomBytes(5000, 5), method: 0),
    FixtureEntry('empty', Uint8List(0)),
  ];

  test('пережатая запись распаковывается в те же байты, заголовки прежние',
      () async {
    final source = buildZip(entries);
    final result = await repackZip(source, deflate: zlib9);

    expect(result.recompressed, greaterThan(0));
    expect(result.bytes.length, lessThan(source.length));
    final before = readEntries(source);
    final after = readEntries(result.bytes);
    expect(after, hasLength(before.length));
    for (var i = 0; i < before.length; i++) {
      expect(after[i].nameBytes, before[i].nameBytes);
      expect(after[i].method, before[i].method);
      expect(after[i].crc32, before[i].crc32);
      expect(after[i].modTime, before[i].modTime);
      expect(after[i].modDate, before[i].modDate);
      expect(after[i].externalAttrs, before[i].externalAttrs);
      expect(contentOf(result.bytes, after[i]), entries[i].content);
    }
  });

  test('упаковщик, вернувший чужие или более длинные байты, ничего не меняет',
      () async {
    final source = buildZip(entries);
    final result = await repackZip(
      source,
      deflate: (plain) async => {
        for (final key in plain.keys)
          key: key.isEven ? deflateRaw(textBytes(10, key)) : Uint8List(1 << 20),
      },
    );

    expect(result.recompressed, 0);
    final after = readEntries(result.bytes);
    for (var i = 0; i < entries.length; i++) {
      expect(contentOf(result.bytes, after[i]), entries[i].content);
    }
  });

  test('в APK несжатые записи выровнены как у AGP, .so по странице', () async {
    final apk = buildZip([
      ...entries,
      FixtureEntry('lib/arm64-v8a/libstored.so', randomBytes(3000, 6),
          method: 0),
    ]);
    final result = await repackZip(apk, deflate: zlib9, apk: true);
    for (final e in readEntries(result.bytes).where((e) => e.method == 0)) {
      final align = e.name.endsWith('.so') ? 16384 : 4;
      expect(dataOffset(result.bytes, e) % align, 0, reason: e.name);
    }
  });

  test('блок подписи APK не переносится, записи все на месте', () async {
    final apk = buildZip(entries, beforeDirectory: randomBytes(4096, 7));
    final result = await repackZip(apk, deflate: zlib9, apk: true);
    final after = readEntries(result.bytes);
    expect(after, hasLength(entries.length));
    final last = after.last;
    expect(
      result.bytes.length,
      lessThan(dataOffset(result.bytes, last) + last.compressedSize + 4096),
    );
  });

  test('запись, не сходящаяся со своим CRC, останавливает переупаковку',
      () async {
    final source = buildZip(entries);
    final e = readEntries(source)[1];
    source[dataOffset(source, e)] ^= 0xFF;
    expect(() => repackZip(source, deflate: zlib9), throwsFormatException);
  });
}
