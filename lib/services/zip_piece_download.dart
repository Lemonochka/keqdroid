import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../utils/zip_layout.dart';

// у соседних релизов 85-90% APK совпадают байт в байт (ядра, движок, базы), их берём из установленного.
// собранный файл проверяется тем же подписанным SHA256SUMS, что и скачанный целиком
class ZipPieceDownload {
  ZipPieceDownload._();

  // мелкую запись дешевле докачать вместе с соседями, чем рвать на ней запрос
  static const minReuse = 64 * 1024;
  // меньше четверти совпало: сборка не наша, проще скачать целиком
  static const minShare = 0.25;

  // null: куски взять неоткуда или сервер не отдаёт Range, качать целиком
  static Future<({int downloaded, int total})?> assemble({
    required Dio dio,
    required String url,
    required File base,
    required File target,
    void Function(int received, int total)? onProgress,
  }) async {
    final probe = await _probe(dio, Uri.parse(url));
    if (probe == null) return null;
    final (:uri, :total) = probe;

    final tailStart = math.max(0, total - 128 * 1024);
    final tail = await _fetch(dio, uri, tailStart, total);
    final end = ZipLayout.findEnd(tail);
    if (end == null) return null;
    final cdStart = end.centralDirectoryOffset;
    final cdEnd = cdStart + end.centralDirectorySize;
    if (cdEnd > total) return null;
    final cd = cdStart >= tailStart
        ? Uint8List.sublistView(tail, cdStart - tailStart, cdEnd - tailStart)
        : await _fetch(dio, uri, cdStart, cdEnd);
    final entries = ZipLayout.parseCentralDirectory(cd, end.entryCount)
      ..sort((a, b) => a.localHeaderOffset.compareTo(b.localHeaderOffset));
    if (entries.isEmpty || entries.last.localHeaderOffset >= cdStart) {
      return null;
    }

    final source = await base.open();
    try {
      final plan = _plan(entries, await _reusable(source), total);
      if (plan == null) return null;
      final toDownload = plan.pieces
          .where((p) => p.download)
          .fold<int>(0, (sum, p) => sum + p.length);

      final out = await target.open(mode: FileMode.write);
      var received = 0;
      try {
        for (final piece in plan.pieces) {
          if (piece.download) {
            await _stream(dio, uri, piece.at, piece.at + piece.length, out, (n) {
              received += n;
              onProgress?.call(received, toDownload);
            });
          } else {
            await _copy(source, piece.from, piece.length, out);
          }
        }
        if (await out.length() != total) {
          throw StateError('assembled update has the wrong length');
        }
        // смещения данных взяты из оглавления, сверяем их с настоящими заголовками
        for (final (header, data) in plan.reusedAt) {
          await out.setPosition(header);
          final length = ZipLayout.localHeaderLength(
            await out.read(ZipLayout.localHeaderSize),
          );
          if (length == null || header + length != data) {
            throw StateError('local header at $header does not fit');
          }
        }
      } finally {
        await out.close();
      }
      return (downloaded: toDownload, total: total);
    } finally {
      await source.close();
    }
  }

  static Future<Map<String, int>> _reusable(RandomAccessFile source) async {
    final length = await source.length();
    final tailStart = math.max(0, length - 128 * 1024);
    await source.setPosition(tailStart);
    final tail = await source.read(length - tailStart);
    final end = ZipLayout.findEnd(tail);
    if (end == null) return const {};
    await source.setPosition(end.centralDirectoryOffset);
    final cd = await source.read(end.centralDirectorySize);
    final found = <String, int>{};
    for (final e in ZipLayout.parseCentralDirectory(cd, end.entryCount)) {
      if (e.compressedSize < minReuse || e.isEncrypted) continue;
      await source.setPosition(e.localHeaderOffset);
      final header = ZipLayout.localHeaderLength(
        await source.read(ZipLayout.localHeaderSize),
      );
      if (header == null) continue;
      found[e.contentKey] = e.localHeaderOffset + header;
    }
    return found;
  }

  static _Plan? _plan(
    List<ZipEntry> entries,
    Map<String, int> reusable,
    int total,
  ) {
    final pieces = <_Piece>[];
    final reusedAt = <(int, int)>[];
    var cursor = 0;
    var reused = 0;
    // за последней записью идёт блок подписи, где кончаются её данные, по оглавлению не узнать
    for (var i = 0; i + 1 < entries.length; i++) {
      final e = entries[i];
      final from = reusable[e.contentKey];
      if (from == null ||
          e.compressedSize < minReuse ||
          e.isEncrypted ||
          e.hasDataDescriptor) {
        continue;
      }
      final data = entries[i + 1].localHeaderOffset - e.compressedSize;
      if (data < e.localHeaderOffset +
              ZipLayout.localHeaderSize +
              e.nameBytes.length ||
          data < cursor) {
        continue;
      }
      if (data > cursor) pieces.add(_Piece.download(cursor, data - cursor));
      pieces.add(_Piece.copy(from, e.compressedSize));
      reusedAt.add((e.localHeaderOffset, data));
      cursor = data + e.compressedSize;
      reused += e.compressedSize;
    }
    if (reused < total * minShare) return null;
    pieces.add(_Piece.download(cursor, total - cursor));
    return _Plan(pieces, reusedAt);
  }

  static Future<({Uri uri, int total})?> _probe(Dio dio, Uri uri) async {
    // за редиректом GitHub подписанная ссылка на час, ходим сразу туда, а не через редирект на каждый кусок
    for (var hop = 0; hop < 5; hop++) {
      final response = await dio.getUri<ResponseBody>(
        uri,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: false,
          validateStatus: (s) => s != null && s < 400,
          headers: {'Range': 'bytes=0-0'},
        ),
      );
      final status = response.statusCode ?? 0;
      final body = response.data?.stream;
      if (status == 206) {
        await body?.drain<void>();
        final range = _contentRange(response.headers.value('content-range'));
        if (range == null || range.start != 0) return null;
        return (uri: uri, total: range.total);
      }
      final location = response.headers.value('location');
      if (status >= 300 && status < 400 && location != null) {
        await body?.drain<void>();
        uri = uri.resolve(location);
        continue;
      }
      // 200 значит Range не понят и пошёл весь файл: рвём, его скачает обычный путь
      await body?.listen(null).cancel();
      return null;
    }
    return null;
  }

  static Future<Uint8List> _fetch(Dio dio, Uri uri, int start, int end) async {
    final bytes = BytesBuilder(copy: false);
    await _request(dio, uri, start, end, (chunk) async => bytes.add(chunk));
    return bytes.takeBytes();
  }

  static Future<void> _stream(
    Dio dio,
    Uri uri,
    int start,
    int end,
    RandomAccessFile out,
    void Function(int) onChunk,
  ) =>
      _request(dio, uri, start, end, (chunk) async {
        await out.writeFrom(chunk);
        onChunk(chunk.length);
      });

  static Future<void> _request(
    Dio dio,
    Uri uri,
    int start,
    int end,
    Future<void> Function(Uint8List chunk) sink,
  ) async {
    if (end <= start) return;
    final response = await dio.getUri<ResponseBody>(
      uri,
      options: Options(
        responseType: ResponseType.stream,
        headers: {'Range': 'bytes=$start-${end - 1}'},
      ),
    );
    final range = _contentRange(response.headers.value('content-range'));
    final body = response.data!.stream;
    if (response.statusCode != 206 ||
        range == null ||
        range.start != start ||
        range.end != end - 1) {
      await body.listen(null).cancel();
      throw StateError('server ignored the range $start-${end - 1}');
    }
    var got = 0;
    await for (final chunk in body) {
      got += chunk.length;
      if (got > end - start) throw StateError('range $start-${end - 1} overran');
      await sink(chunk);
    }
    if (got != end - start) {
      throw StateError('range $start-${end - 1} ended after $got bytes');
    }
  }

  static Future<void> _copy(
    RandomAccessFile source,
    int from,
    int length,
    RandomAccessFile out,
  ) async {
    await source.setPosition(from);
    var left = length;
    while (left > 0) {
      final chunk = await source.read(math.min(left, 1 << 20));
      if (chunk.isEmpty) throw StateError('installed APK ended early');
      await out.writeFrom(chunk);
      left -= chunk.length;
    }
  }

  static ({int start, int end, int total})? _contentRange(String? header) {
    final m = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(header ?? '');
    if (m == null) return null;
    return (
      start: int.parse(m[1]!),
      end: int.parse(m[2]!),
      total: int.parse(m[3]!),
    );
  }
}

class _Plan {
  _Plan(this.pieces, this.reusedAt);

  final List<_Piece> pieces;
  final List<(int, int)> reusedAt;
}

class _Piece {
  _Piece.download(this.at, this.length)
      : download = true,
        from = 0;
  _Piece.copy(this.from, this.length)
      : download = false,
        at = 0;

  final bool download;
  final int at;
  final int from;
  final int length;
}
