// Пережимает zip (APK, архив Windows) тем же deflate, только 7-Zip на
// максимуме: APK 0.36.3 легчал на 1.8 МБ, архив Windows на 2.9 МБ. После
// распаковки каждая запись байт в байт прежняя, инструмент сверяет это сам и
// падает, если нет. Блок подписи APK не переносится: tool/make_release.ps1
// подписывает результат заново.
//
//   dart run tool/repack_zip.dart --in app.apk --out app.repacked.apk --apk
//   dart run tool/repack_zip.dart --in windows.zip --out windows.repacked.zip [--7z 7zz]

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:keqdroid/utils/zip_layout.dart';

typedef Deflater = Future<Map<int, Uint8List>> Function(
  Map<int, Uint8List> plain,
);

class RepackResult {
  RepackResult(this.bytes, {required this.recompressed, required this.total});

  final Uint8List bytes;
  final int recompressed;
  final int total;
}

Future<void> main(List<String> args) async {
  String? input;
  String? output;
  String? sevenZip;
  var apk = false;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--in':
        input = args[++i];
      case '--out':
        output = args[++i];
      case '--7z':
        sevenZip = args[++i];
      case '--apk':
        apk = true;
      default:
        stderr.writeln('unknown argument ${args[i]}');
        exit(2);
    }
  }
  if (input == null || output == null) {
    stderr.writeln('usage: repack_zip.dart --in <zip> --out <zip> [--apk] [--7z <exe>]');
    exit(2);
  }

  final tool = sevenZip ?? await _findSevenZip();
  final source = File(input).readAsBytesSync();
  final result = await repackZip(
    source,
    apk: apk,
    deflate: (plain) => sevenZipDeflate(plain, tool),
  );
  File(output).writeAsBytesSync(result.bytes, flush: true);
  stdout.writeln(
    '${File(input).uri.pathSegments.last}: ${source.length} -> '
    '${result.bytes.length} bytes, ${result.recompressed} of ${result.total} '
    'entries recompressed, every entry checked',
  );
}

Future<RepackResult> repackZip(
  Uint8List source, {
  required Deflater deflate,
  bool apk = false,
}) async {
  final tailStart = math.max(0, source.length - 65557);
  final end = ZipLayout.findEnd(Uint8List.sublistView(source, tailStart));
  if (end == null) throw const FormatException('no zip end record');
  final entries = ZipLayout.parseCentralDirectory(
    Uint8List.sublistView(
      source,
      end.centralDirectoryOffset,
      end.centralDirectoryOffset + end.centralDirectorySize,
    ),
    end.entryCount,
  )..sort((a, b) => a.localHeaderOffset.compareTo(b.localHeaderOffset));

  final original = <Uint8List>[];
  final extras = <Uint8List>[];
  final plain = <Uint8List>[];
  final toDeflate = <int, Uint8List>{};
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    if (e.isEncrypted || (e.method != 0 && e.method != 8)) {
      throw FormatException('${e.name}: method ${e.method} is not supported');
    }
    final header = Uint8List.sublistView(
      source,
      e.localHeaderOffset,
      math.min(source.length, e.localHeaderOffset + 65536 + 30),
    );
    final headerLength = ZipLayout.localHeaderLength(header);
    if (headerLength == null) {
      throw FormatException('${e.name}: no local header');
    }
    final start = e.localHeaderOffset + headerLength;
    final data = Uint8List.sublistView(source, start, start + e.compressedSize);
    final content = e.method == 8 ? _inflate(data) : data;
    if (content.length != e.uncompressedSize ||
        ZipLayout.crc32(content) != e.crc32) {
      throw FormatException('${e.name}: content does not match its CRC');
    }
    original.add(data);
    extras.add(ZipLayout.localExtra(header));
    plain.add(content);
    if (e.method == 8 && e.uncompressedSize > 0) toDeflate[i] = content;
  }

  final better = await deflate(toDeflate);

  final writer = ZipWriter();
  var recompressed = 0;
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    var data = original[i];
    final candidate = better[i];
    if (candidate != null &&
        candidate.length < data.length &&
        _same(_inflate(candidate), plain[i])) {
      data = candidate;
      recompressed++;
    }
    // несжатые .so Android читает прямо из APK страницами, остальное AGP ровняет на 4
    final align = apk && e.method == 0
        ? (e.name.endsWith('.so') ? 16384 : 4)
        : 0;
    writer.add(
      e,
      method: e.method,
      data: data,
      localExtra: align > 0 ? null : extras[i],
      alignTo: align,
    );
  }
  final out = writer.finish(comment: end.comment);
  _checkSame(out, entries, plain);
  return RepackResult(out, recompressed: recompressed, total: entries.length);
}

void _checkSame(Uint8List out, List<ZipEntry> entries, List<Uint8List> plain) {
  final end = ZipLayout.findEnd(
    Uint8List.sublistView(out, math.max(0, out.length - 65557)),
  );
  if (end == null) throw StateError('repacked zip has no end record');
  final written = ZipLayout.parseCentralDirectory(
    Uint8List.sublistView(
      out,
      end.centralDirectoryOffset,
      end.centralDirectoryOffset + end.centralDirectorySize,
    ),
    end.entryCount,
  );
  if (written.length != entries.length) {
    throw StateError('repacked zip lost entries');
  }
  for (var i = 0; i < written.length; i++) {
    final w = written[i];
    final e = entries[i];
    if (!_same(w.nameBytes, e.nameBytes) ||
        w.method != e.method ||
        w.crc32 != e.crc32 ||
        w.uncompressedSize != e.uncompressedSize ||
        w.externalAttrs != e.externalAttrs ||
        w.modDate != e.modDate ||
        w.modTime != e.modTime) {
      throw StateError('${e.name}: header differs after repack');
    }
    final header = Uint8List.sublistView(out, w.localHeaderOffset);
    final start = w.localHeaderOffset + ZipLayout.localHeaderLength(header)!;
    final data = Uint8List.sublistView(out, start, start + w.compressedSize);
    if (!_same(w.method == 8 ? _inflate(data) : data, plain[i])) {
      throw StateError('${e.name}: content differs after repack');
    }
  }
}

Uint8List _inflate(Uint8List data) =>
    Uint8List.fromList(ZLibDecoder(raw: true).convert(data));

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// -mx=9 без -mpass=15: тот дал ещё 0.03% за двойное время
Future<Map<int, Uint8List>> sevenZipDeflate(
  Map<int, Uint8List> plain,
  String sevenZip,
) async {
  if (plain.isEmpty) return const {};
  final dir = Directory.systemTemp.createTempSync('repack_zip');
  try {
    final files = Directory('${dir.path}/f')..createSync();
    for (final MapEntry(:key, :value) in plain.entries) {
      File('${files.path}/$key').writeAsBytesSync(value);
    }
    final archive = '${dir.path}/out.zip';
    final run = await Process.run(
      sevenZip,
      ['a', '-tzip', '-mx=9', '-mm=Deflate', '-bd', archive, '*'],
      workingDirectory: files.path,
    );
    if (run.exitCode != 0) {
      throw StateError('$sevenZip failed (${run.exitCode}): ${run.stderr}');
    }
    final bytes = File(archive).readAsBytesSync();
    final end = ZipLayout.findEnd(
      Uint8List.sublistView(bytes, math.max(0, bytes.length - 65557)),
    )!;
    final result = <int, Uint8List>{};
    for (final e in ZipLayout.parseCentralDirectory(
      Uint8List.sublistView(
        bytes,
        end.centralDirectoryOffset,
        end.centralDirectoryOffset + end.centralDirectorySize,
      ),
      end.entryCount,
    )) {
      final index = int.tryParse(e.name);
      if (index == null || e.method != 8) continue;
      final header = Uint8List.sublistView(bytes, e.localHeaderOffset);
      final start = e.localHeaderOffset + ZipLayout.localHeaderLength(header)!;
      result[index] = Uint8List.fromList(
        bytes.sublist(start, start + e.compressedSize),
      );
    }
    return result;
  } finally {
    dir.deleteSync(recursive: true);
  }
}

Future<String> _findSevenZip() async {
  final candidates = [
    if (Platform.isWindows) r'C:\Program Files\7-Zip\7z.exe',
    '7z',
    '7zz',
    '7za',
  ];
  for (final c in candidates) {
    try {
      final r = await Process.run(c, const ['i']);
      if (r.exitCode == 0) return c;
    } on ProcessException {
      continue;
    }
  }
  stderr.writeln('7-Zip not found, pass --7z <path>');
  exit(2);
}
