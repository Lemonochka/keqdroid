import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/geo_asset_index.dart';

/// Собирает v2fly-подобный .dat: `repeated entry = 1`, у записи первое поле —
/// `string country_code = 1`, за ним произвольное тело (у нас — bytes-поле 2).
Uint8List buildGeoDat(Map<String, int> codesWithBodySize) {
  void writeVarint(List<int> out, int value) {
    var v = value;
    while (v >= 0x80) {
      out.add((v & 0x7f) | 0x80);
      v >>= 7;
    }
    out.add(v);
  }

  final out = <int>[];
  codesWithBodySize.forEach((code, bodySize) {
    final entry = <int>[];
    entry.add(0x0a); // field 1 (country_code), wire type 2
    writeVarint(entry, code.length);
    entry.addAll(code.codeUnits);
    if (bodySize > 0) {
      entry.add(0x12); // field 2, wire type 2 — тело записи
      writeVarint(entry, bodySize);
      entry.addAll(List<int>.filled(bodySize, 0x41));
    }
    out.add(0x0a); // top-level entry
    writeVarint(out, entry.length);
    out.addAll(entry);
  });
  return Uint8List.fromList(out);
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('geo_index_test_');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  Future<File> writeDat(String name, Uint8List bytes) async {
    final f = File('${tmp.path}${Platform.pathSeparator}$name');
    await f.writeAsBytes(bytes);
    return f;
  }

  group('GeoAssetIndex.readCodes', () {
    test('reads every top-level country_code, lowercased', () async {
      final file = await writeDat(
        'geosite.dat',
        buildGeoDat({'YANDEX': 12, 'CATEGORY-ADS-ALL': 300, 'VK': 0}),
      );
      expect(
        await GeoAssetIndex.readCodes(file),
        {'yandex', 'category-ads-all', 'vk'},
      );
    });

    test('skips entries whose body needs a multi-byte length varint', () async {
      // Тело > 127 байт → длина записи занимает 2 байта varint: если seek
      // считает её однобайтовой, разбор уезжает и коды теряются.
      final file = await writeDat(
        'geoip.dat',
        buildGeoDat({'RU': 5000, 'US': 200000, 'PRIVATE': 4}),
      );
      expect(await GeoAssetIndex.readCodes(file), {'ru', 'us', 'private'});
    });

    test('missing file yields an empty set, not a throw', () async {
      final missing = File('${tmp.path}${Platform.pathSeparator}nope.dat');
      expect(await GeoAssetIndex.readCodes(missing), isEmpty);
    });

    test('garbage file yields an empty set', () async {
      final file = await writeDat(
        'geosite.dat',
        Uint8List.fromList(List<int>.filled(64, 0xff)),
      );
      expect(await GeoAssetIndex.readCodes(file), isEmpty);
    });

    test('fromDirectory reads both databases', () async {
      await writeDat('geoip.dat', buildGeoDat({'RU': 8}));
      await writeDat('geosite.dat', buildGeoDat({'YOUTUBE': 8}));
      final index = await GeoAssetIndex.fromDirectory(tmp.path);
      expect(index.geoipCodes, {'ru'});
      expect(index.geositeCodes, {'youtube'});
      expect(index.isEmpty, isFalse);
    });
  });

  group('bundled databases', () {
    // Файлы едут в APK как flutter-ассеты; в тестах читаем их из репозитория.
    final geosite = File('assets/bin/windows/geosite.dat');
    final geoip = File('assets/bin/windows/geoip.dat');

    test('geosite.dat parses into the codes the presets rely on', () async {
      if (!geosite.existsSync()) return; // сборка без geo-баз — не наш случай
      final codes = await GeoAssetIndex.readCodes(geosite);
      expect(codes.length, greaterThan(100));
      expect(
        codes,
        containsAll(['category-ads-all', 'category-ru', 'yandex', 'youtube']),
      );
      // Коды хранятся заглавными — индекс обязан отдавать нижний регистр.
      expect(codes.any((c) => c != c.toLowerCase()), isFalse);
    });

    test('geoip.dat parses into country codes', () async {
      if (!geoip.existsSync()) return;
      final codes = await GeoAssetIndex.readCodes(geoip);
      expect(codes.length, greaterThan(100));
      expect(codes, containsAll(['ru', 'us', 'private']));
    });
  });
}
