import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/zip_piece_download.dart';

import '../helpers/zip_fixture.dart';

// обновление из кусков: файл обязан выйти байт в байт новым релизом, иначе его отвергнет проверка хеша
void main() {
  late Directory dir;
  late HttpServer server;
  final files = <String, Uint8List>{};
  final requests = <String>[];
  var honourRange = true;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('zip_piece_test');
    files.clear();
    requests.clear();
    honourRange = true;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      final range = request.headers.value('range');
      requests.add('$path ${range ?? ''}');
      final response = request.response;
      if (path == '/redirect') {
        response
          ..statusCode = HttpStatus.found
          ..headers.set('location', '/file.apk');
        await response.close();
        return;
      }
      final body = files[path]!;
      final m = RegExp(r'^bytes=(\d+)-(\d+)$').firstMatch(range ?? '');
      if (!honourRange || m == null) {
        response.add(body);
        await response.close();
        return;
      }
      final start = int.parse(m[1]!);
      final end = int.parse(m[2]!);
      response
        ..statusCode = HttpStatus.partialContent
        ..headers.set('content-range', 'bytes $start-$end/${body.length}')
        ..add(Uint8List.sublistView(body, start, end + 1));
      await response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await dir.delete(recursive: true);
  });

  String url(String path) => 'http://127.0.0.1:${server.port}$path';

  final core = randomBytes(300000, 1);
  final engine = randomBytes(200000, 2);
  final model = randomBytes(150000, 3);

  Uint8List release(Uint8List code, {Uint8List? geo}) => buildZip(
        [
          FixtureEntry('AndroidManifest.xml', textBytes(3000, code.length)),
          FixtureEntry('classes.dex', code),
          FixtureEntry('lib/arm64-v8a/libmihomo.so', core),
          FixtureEntry('lib/arm64-v8a/libflutter.so', engine),
          FixtureEntry('assets/model.tflite', model, method: 0),
          FixtureEntry('assets/geosite.dat', geo ?? randomBytes(100000, 4)),
          FixtureEntry('lib/arm64-v8a/libapp.so', code),
        ],
        beforeDirectory: randomBytes(4096, code.length),
      );

  Future<File> installed(Uint8List bytes) async =>
      File('${dir.path}/base.apk')..writeAsBytesSync(bytes);

  test('новый APK собирается из установленного байт в байт, качается только '
      'изменённое', () async {
    final old = release(randomBytes(120000, 10));
    final next = release(randomBytes(130000, 11), geo: randomBytes(100000, 5));
    files['/file.apk'] = next;
    final target = File('${dir.path}/update.apk');
    var lastProgress = (0, 0);

    final result = await ZipPieceDownload.assemble(
      dio: Dio(),
      url: url('/file.apk'),
      base: await installed(old),
      target: target,
      onProgress: (received, total) => lastProgress = (received, total),
    );

    expect(result, isNotNull);
    expect(target.readAsBytesSync(), next);
    expect(result!.total, next.length);
    // ядро, движок и модель взяты с диска: 650 КБ из примерно 1 МБ
    expect(result.downloaded, lessThan(next.length - 600000));
    expect(lastProgress, (result.downloaded, result.downloaded));
  });

  test('после редиректа GitHub куски идут сразу по конечной ссылке', () async {
    final old = release(randomBytes(120000, 10));
    final next = release(randomBytes(130000, 11));
    files['/file.apk'] = next;
    final target = File('${dir.path}/update.apk');

    final result = await ZipPieceDownload.assemble(
      dio: Dio(),
      url: url('/redirect'),
      base: await installed(old),
      target: target,
    );

    expect(result, isNotNull);
    expect(target.readAsBytesSync(), next);
    expect(requests.where((r) => r.startsWith('/redirect')), hasLength(1));
  });

  test('сервер без Range: null, файл скачает обычный путь', () async {
    files['/file.apk'] = release(randomBytes(130000, 11));
    honourRange = false;
    final target = File('${dir.path}/update.apk');

    final result = await ZipPieceDownload.assemble(
      dio: Dio(),
      url: url('/file.apk'),
      base: await installed(release(randomBytes(120000, 10))),
      target: target,
    );

    expect(result, isNull);
    expect(target.existsSync(), isFalse);
  });

  test('установлена чужая сборка, совпадений мало: null', () async {
    files['/file.apk'] = release(randomBytes(130000, 11));
    final foreign = buildZip([
      FixtureEntry('classes.dex', randomBytes(200000, 20)),
      FixtureEntry('lib/arm64-v8a/libmihomo.so', randomBytes(300000, 21)),
    ]);

    final result = await ZipPieceDownload.assemble(
      dio: Dio(),
      url: url('/file.apk'),
      base: await installed(foreign),
      target: File('${dir.path}/update.apk'),
    );

    expect(result, isNull);
  });

  test('сервер отдал не тот кусок: ошибка, а не кривой файл', () async {
    files['/file.apk'] = release(randomBytes(130000, 11));
    final old = release(randomBytes(120000, 10));
    final target = File('${dir.path}/update.apk');
    await server.close(force: true);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = files['/file.apk']!;
      final m = RegExp(r'^bytes=(\d+)-(\d+)$')
          .firstMatch(request.headers.value('range')!)!;
      var start = int.parse(m[1]!);
      var end = int.parse(m[2]!);
      // зонд и хвост с оглавлением честные, остальные куски со сдвигом на байт
      if (end != 0 && end != body.length - 1) {
        start += 1;
        end += 1;
      }
      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set('content-range', 'bytes $start-$end/${body.length}')
        ..add(Uint8List.sublistView(body, start, end + 1));
      await request.response.close();
    });

    await expectLater(
      ZipPieceDownload.assemble(
        dio: Dio(),
        url: url('/file.apk'),
        base: await installed(old),
        target: target,
      ),
      throwsStateError,
    );
  });
}
