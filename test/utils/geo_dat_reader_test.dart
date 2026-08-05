import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/geo_dat_reader.dart';

void _varint(List<int> out, int value) {
  var v = value;
  while (v >= 0x80) {
    out.add((v & 0x7f) | 0x80);
    v >>= 7;
  }
  out.add(v);
}

/// `Domain { Type type = 1; string value = 2; }`
List<int> _domain(int type, String value) {
  final body = <int>[];
  if (type != 0) {
    body..add(0x08)..addAll([type]); // field 1, varint
  }
  body.add(0x12); // field 2, length-delimited
  _varint(body, value.length);
  body.addAll(value.codeUnits);
  final out = <int>[0x12]; // GeoSite.domain = 2
  _varint(out, body.length);
  return out..addAll(body);
}

/// `CIDR { bytes ip = 1; uint32 prefix = 2; }`
List<int> _cidr(List<int> ip, int prefix) {
  final body = <int>[0x0a];
  _varint(body, ip.length);
  body.addAll(ip);
  body.add(0x10); // field 2, varint
  _varint(body, prefix);
  final out = <int>[0x12]; // GeoIP.cidr = 2
  _varint(out, body.length);
  return out..addAll(body);
}

/// Одна запись верхнего уровня: `entry = 1` + код + тело.
List<int> _entry(String code, List<int> body) {
  final entry = <int>[0x0a];
  _varint(entry, code.length);
  entry.addAll(code.codeUnits);
  entry.addAll(body);
  final out = <int>[0x0a];
  _varint(out, entry.length);
  return out..addAll(entry);
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('geo_dat_reader_');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  Future<File> write(String name, List<int> bytes) async {
    final f = File('${tmp.path}${Platform.pathSeparator}$name');
    await f.writeAsBytes(Uint8List.fromList(bytes));
    return f;
  }

  test('reads domains with their match type', () async {
    final file = await write('geosite.dat', [
      ..._entry('TELEGRAM', [
        ..._domain(2, 'telegram.org'), // Domain (суффикс)
        ..._domain(3, 't.me'), // Full (точное)
        ..._domain(1, r'.*\.telesco\.pe$'), // Regex
        ..._domain(0, 'telegram'), // Plain (подстрока)
      ]),
      ..._entry('VK', [..._domain(2, 'vk.com')]),
    ]);

    final domains = await GeoDatReader.domains(file, 'telegram');
    expect(domains.length, 4);
    expect(domains[0].type, GeoDomainType.domain);
    expect(domains[0].value, 'telegram.org');
    expect(domains[1].type, GeoDomainType.full);
    expect(domains[1].value, 't.me');
    expect(domains[2].type, GeoDomainType.regex);
    expect(domains[3].type, GeoDomainType.plain);

    // Код ищется без учёта регистра — в файлах он заглавный.
    expect((await GeoDatReader.domains(file, 'VK')).single.value, 'vk.com');
  });

  test('reads ipv4 and ipv6 cidrs', () async {
    final file = await write('geoip.dat', [
      ..._entry('TELEGRAM', [
        ..._cidr([91, 108, 4, 0], 22),
        ..._cidr([
          0x2a, 0x0a, 0x01, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        ], 32),
      ]),
    ]);

    expect(
      await GeoDatReader.cidrs(file, 'telegram'),
      ['91.108.4.0/22', '2a0a:100::/32'],
    );
  });

  test('missing code and missing file yield empty lists, not throws', () async {
    final file = await write('geosite.dat', _entry('VK', _domain(2, 'vk.com')));
    expect(await GeoDatReader.domains(file, 'nope'), isEmpty);
    expect(
      await GeoDatReader.domains(
        File('${tmp.path}${Platform.pathSeparator}absent.dat'),
        'vk',
      ),
      isEmpty,
    );
  });

  test('codes are lowercased and complete', () async {
    final file = await write('geosite.dat', [
      ..._entry('CATEGORY-ADS-ALL', _domain(2, 'doubleclick.net')),
      ..._entry('REFILTER', _domain(2, 'example.com')),
    ]);
    expect(await GeoDatReader.codes(file), {'category-ads-all', 'refilter'});
  });

  group('bundled databases', () {
    // Файлы едут в APK как flutter-ассеты; в тестах читаем их из репозитория.
    final geosite = File('assets/bin/windows/geosite.dat');
    final geoip = File('assets/bin/windows/geoip.dat');

    test('codes merged by tool/fetch_xray_geo.ps1 are present and readable', () async {
      if (!geoip.existsSync() || !geosite.existsSync()) return;

      // Их нет в базах v2fly, поэтому правила вида `geoip:telegram` раньше
      // молча выкидывались санитайзером (жалоба «ТГ не учитывается»).
      final ipCodes = await GeoDatReader.codes(geoip);
      expect(ipCodes, containsAll(['telegram', 'refilter', 'ru', 'private']));

      final siteCodes = await GeoDatReader.codes(geosite);
      expect(siteCodes, containsAll(['telegram', 'refilter', 'category-ru']));

      // Тело домерженной записи должно читаться, а не только её заголовок.
      expect(await GeoDatReader.cidrs(geoip, 'telegram'), isNotEmpty);
      expect(await GeoDatReader.domains(geosite, 'refilter'), isNotEmpty);
    });
  });
}
