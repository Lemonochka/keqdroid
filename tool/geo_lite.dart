// Собирает облегчённую geoip.dat — только те коды, которые приложение может
// выпустить само.
//
// Зачем: полная база v2fly несёт 263 страны и весит 23.5 МБ, из которых
// us=5.0, au=3.3, nl=2.4, be=1.7, ch=1.2 — 58% файла. Дефолтным правилам
// приложения нужны четыре кода на 0.6 МБ. В APK это разница между 4.8 МБ и
// примерно 150 КБ, а всё, чего не хватит пользователю, догружается по кнопке
// (GeoBaseDownloader) поверх вшитой базы.
//
// Режем ТОЛЬКО geoip.dat. У geosite.dat нужные коды — 44.5% файла (почти всё в
// нашем же refilter), кодов там 1534, и шанс, что правило упрётся в
// отсутствующий, несопоставимо выше при экономии в полмегабайта.
//
// Формат позволяет фильтровать так же, как geo_merge позволяет домердживать:
// верхний уровень — `repeated entry = 1`, то есть валидный protobuf получается
// конкатенацией нужных записей в исходном порядке.
//
// Использование:
//   dart run tool/geo_lite.dart
//   dart run tool/geo_lite.dart --source assets/bin/windows/geoip.dat \
//       --out assets/geo/geoip-lite.dat --codes private,ru,telegram,refilter

import 'dart:io';
import 'dart:typed_data';

import 'package:keqdroid/utils/geo_dat_reader.dart';

/// Коды, которые приложение выпускает само: пресеты маршрутизации плюс
/// `private`, который генераторы конфига дописывают всегда.
///
/// Список обязан оставаться надмножеством того, что может попасть в конфиг без
/// участия пользователя. Иначе свежая установка молча потеряет часть
/// маршрутизации: неизвестный код санитайзер выбрасывает до генерации конфига,
/// потому что xray на нём роняет конфиг целиком.
const _defaultCodes = ['private', 'ru', 'telegram', 'refilter'];

const _defaultSource = 'assets/bin/windows/geoip.dat';
const _defaultOut = 'assets/geo/geoip-lite.dat';

Future<int> main(List<String> args) async {
  final opts = _parseArgs(args);
  if (opts == null) {
    stderr.writeln(
      'usage: dart run tool/geo_lite.dart [--source <full.dat>] '
      '[--out <lite.dat>] [--codes a,b,c]',
    );
    return 2;
  }

  final source = File(opts.source);
  if (!source.existsSync()) {
    stderr.writeln('source not found: ${opts.source}');
    return 1;
  }

  final records = await GeoDatReader.records(source);
  if (records.isEmpty) {
    stderr.writeln('no records parsed from ${opts.source} — is it a v2fly .dat?');
    return 1;
  }

  final want = {for (final c in opts.codes) c.trim().toLowerCase()}
    ..removeWhere((c) => c.isEmpty);
  final bytes = await source.readAsBytes();

  final out = <int>[];
  final kept = <String, int>{};
  // Порядок исходного файла сохраняем: при дубликате кода ядро берёт первую
  // запись, и менять их местами — значит менять поведение.
  for (final r in records) {
    if (!want.contains(r.code)) continue;
    if (kept.containsKey(r.code)) continue;
    final body = Uint8List.sublistView(bytes, r.bodyStart, r.bodyStart + r.bodyLength);
    out.addAll(_encodeRecord(body));
    kept[r.code] = r.bodyLength;
  }

  final missing = want.difference(kept.keys.toSet());
  if (missing.isNotEmpty) {
    // Жёсткая ошибка: тихо собранная база без нужного кода — это молча
    // потерянное правило маршрутизации у каждого, кто поставит сборку.
    stderr.writeln('codes missing from ${opts.source}: ${missing.join(", ")}');
    return 1;
  }

  final target = File(opts.out);
  await target.parent.create(recursive: true);
  await target.writeAsBytes(out, flush: true);

  final full = bytes.length;
  final lite = out.length;
  stdout.writeln('source: ${opts.source} — ${_mib(full)}, ${records.length} codes');
  for (final e in kept.entries) {
    stdout.writeln('  keep ${e.key.padRight(12)} ${_kib(e.value).padLeft(10)}');
  }
  stdout.writeln('out:    ${opts.out} — ${_mib(lite)}, ${kept.length} codes '
      '(${(lite * 100 / full).toStringAsFixed(1)}% of full)');
  return 0;
}

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

String _kib(int bytes) => '${(bytes / 1024).toStringAsFixed(1)} KiB';
String _mib(int bytes) => '${(bytes / 1024 / 1024).toStringAsFixed(2)} MiB';

({String source, String out, List<String> codes})? _parseArgs(List<String> a) {
  var source = _defaultSource;
  var out = _defaultOut;
  var codes = _defaultCodes;
  for (var i = 0; i < a.length; i++) {
    switch (a[i]) {
      case '--source':
        if (++i >= a.length) return null;
        source = a[i];
      case '--out':
        if (++i >= a.length) return null;
        out = a[i];
      case '--codes':
        if (++i >= a.length) return null;
        codes = a[i].split(',');
      default:
        return null;
    }
  }
  return (source: source, out: out, codes: codes);
}
