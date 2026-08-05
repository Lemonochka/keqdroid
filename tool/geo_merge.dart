// Домерживает отдельные коды из чужой geo-базы в нашу поставляемую.
//
// Зачем: в v2fly geoip.dat лежат только страны (+ private/test), поэтому
// популярнейшие правила вида `geoip:telegram` в приложении не работали вообще —
// xray падает на неизвестном коде, а санитайзер выкидывал такой токен молча.
// Тянуть целиком базы Loyalsoldier (17 МБ) или runetfreedom (72 МБ) незачем:
// нужны единицы категорий, и весят они килобайты.
//
// Формат позволяет это делать дописыванием: `GeoIPList`/`GeoSiteList` — это
// `repeated entry = 1`, так что валидный protobuf получается простой
// конкатенацией записей. Существующие коды не трогаем (при дубликате ядро
// берёт первый), поэтому наша база остаётся приоритетной.
//
// Использование:
//   dart run tool/geo_merge.dart --base assets/bin/windows/geoip.dat \
//       --source /tmp/loyal_geoip.dat --codes telegram,google,netflix
//   dart run tool/geo_merge.dart ... --dry-run   # только отчёт по весу

import 'dart:io';
import 'dart:typed_data';

import 'package:keqdroid/utils/geo_dat_reader.dart';

Future<int> main(List<String> args) async {
  final opts = _parseArgs(args);
  if (opts == null) {
    stderr.writeln(
      'usage: dart run tool/geo_merge.dart --base <base.dat> '
      '--source <source.dat> --codes a,b,c [--dry-run]',
    );
    return 64;
  }

  final base = File(opts.base);
  final source = File(opts.source);
  if (!base.existsSync()) {
    stderr.writeln('base not found: ${opts.base}');
    return 66;
  }
  if (!source.existsSync()) {
    stderr.writeln('source not found: ${opts.source}');
    return 66;
  }

  final existing = await GeoDatReader.codes(base);
  final sourceRecords = await GeoDatReader.records(source);
  final sourceCodes = {for (final r in sourceRecords) r.code};

  // geoip-записи несут CIDR'ы, geosite — домены; в отчёт печатаем и то и то,
  // чтобы сразу видеть, что перенеслась настоящая запись, а не пустышка.
  final isGeoip = opts.base.toLowerCase().contains('geoip');

  final appended = <int>[];
  final added = <String, ({int bytes, int items})>{};
  final skipped = <String>[];
  final missing = <String>[];

  for (final raw in opts.codes) {
    final code = raw.trim().toLowerCase();
    if (code.isEmpty) continue;
    if (existing.contains(code)) {
      // Свой код важнее чужого: перезаписывать страну из другой базы — не то,
      // что просили, а дубликат ядро всё равно разрешит в пользу первого.
      skipped.add(code);
      continue;
    }
    if (!sourceCodes.contains(code)) {
      missing.add(code);
      continue;
    }
    final body = await GeoDatReader.entryBody(source, code);
    if (body == null) {
      missing.add(code);
      continue;
    }
    final record = _encodeRecord(body);
    appended.addAll(record);
    added[code] = (
      bytes: record.length,
      items: isGeoip
          ? GeoDatReader.parseCidrs(body).length
          : GeoDatReader.parseDomains(body).length,
    );
    existing.add(code);
  }

  final baseSize = base.lengthSync();
  stdout.writeln('base:   ${opts.base} (${_kib(baseSize)}, '
      '${existing.length - added.length} codes)');
  stdout.writeln('source: ${opts.source} (${_kib(source.lengthSync())}, '
      '${sourceCodes.length} codes)');
  for (final e in added.entries) {
    stdout.writeln(
      '  + ${e.key.padRight(20)} ${_kib(e.value.bytes).padLeft(10)}  '
      '${e.value.items} ${isGeoip ? 'cidrs' : 'domains'}',
    );
  }
  for (final code in skipped) {
    stdout.writeln('  = $code (already in base, kept as is)');
  }
  for (final code in missing) {
    stdout.writeln('  ! $code (not in source)');
  }

  if (appended.isEmpty) {
    stdout.writeln('nothing to append');
    return missing.isEmpty ? 0 : 1;
  }

  stdout.writeln('total added: ${_kib(appended.length)} '
      '(${added.values.fold(0, (a, e) => a + e.items)} entries) '
      '-> ${_kib(baseSize + appended.length)}');

  if (opts.dryRun) {
    stdout.writeln('(dry run, base not modified)');
    return 0;
  }

  await base.writeAsBytes(appended, mode: FileMode.append, flush: true);

  // Пересчитываем базу тем же ридером, которым её читает приложение: битую
  // конкатенацию лучше поймать здесь, чем «SOCKS port not ready» у юзера.
  final verify = await GeoDatReader.codes(base);
  final lost = added.keys.where((c) => !verify.contains(c)).toList();
  if (lost.isNotEmpty) {
    stderr.writeln('VERIFY FAILED: appended codes not readable back: $lost');
    return 70;
  }
  stdout.writeln('ok: ${verify.length} codes readable in ${opts.base}');
  return 0;
}

/// Одна запись верхнего уровня: `entry = 1` (тег 0x0a) + varint-длина + тело.
List<int> _encodeRecord(Uint8List body) {
  final out = <int>[0x0a];
  var len = body.length;
  while (len >= 0x80) {
    out.add((len & 0x7f) | 0x80);
    len >>= 7;
  }
  out.add(len);
  out.addAll(body);
  return out;
}

String _kib(int bytes) => bytes >= 1024 * 1024
    ? '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MiB'
    : '${(bytes / 1024).toStringAsFixed(1)} KiB';

({String base, String source, List<String> codes, bool dryRun})? _parseArgs(
  List<String> args,
) {
  String? base;
  String? source;
  var codes = <String>[];
  var dryRun = false;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--base':
        base = i + 1 < args.length ? args[++i] : null;
      case '--source':
        source = i + 1 < args.length ? args[++i] : null;
      case '--codes':
        codes = i + 1 < args.length ? args[++i].split(',') : const [];
      case '--dry-run':
        dryRun = true;
      default:
        stderr.writeln('unknown argument: ${args[i]}');
        return null;
    }
  }
  if (base == null || source == null || codes.isEmpty) return null;
  return (base: base, source: source, codes: codes, dryRun: dryRun);
}
