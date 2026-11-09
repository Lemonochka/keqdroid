import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/geo_base_downloader.dart';
import 'package:keqdroid/services/release_signature.dart';
import 'package:keqdroid/services/update_service.dart';

// Фикстуры подписаны openssl (pkeyutl -sign -rawin), как это делает
// tool/sign_sums.sh на GitHub: тест сверяет формат подписи с тем, что
// проверяет приложение. Закрытые ключи фикстур выброшены, ниже только открытые.
const _testMain = '0gs9Q1SKAxwNrgZ6zE9AQMdxzM++E56UMqmVhwoL9ZA=';
const _testReserve = 'fJnDY8I5jsNFcr8dSEyx5BoQMkJVVEM+eX/CHboeHMA=';

const _dir = 'test/fixtures/release_signature';

List<int> _sums() => File('$_dir/SHA256SUMS').readAsBytesSync();
String _sig([String name = 'SHA256SUMS.sig']) =>
    File('$_dir/$name').readAsStringSync();

void main() {
  late List<String> productionKeys;

  setUp(() {
    productionKeys = ReleaseSignature.publicKeys;
    ReleaseSignature.publicKeys = const [_testMain, _testReserve];
  });
  tearDown(() => ReleaseSignature.publicKeys = productionKeys);

  group('ReleaseSignature.verify', () {
    test('подпись основным ключом принимается', () async {
      expect(await ReleaseSignature.verify(_sums(), _sig()), isTrue);
    });

    test('подпись запасным ключом тоже', () async {
      expect(
        await ReleaseSignature.verify(_sums(), _sig('SHA256SUMS.reserve.sig')),
        isTrue,
      );
    });

    test('один изменённый байт в манифесте, и подписи нет', () async {
      final sums = _sums();
      // подмена хеша APK: ровно то, ради чего подпись и нужна
      final i = utf8.decode(sums).indexOf('3e4f5a6b');
      sums[i] = '4'.codeUnitAt(0);
      expect(await ReleaseSignature.verify(sums, _sig()), isFalse);
    });

    test('ключ, которого нет в приложении, не годится', () async {
      ReleaseSignature.publicKeys = const [_testReserve];
      expect(await ReleaseSignature.verify(_sums(), _sig()), isFalse);
    });

    test('мусор вместо подписи не роняет проверку', () async {
      for (final junk in [
        '',
        'not base64 at all',
        base64.encode([1, 2, 3]),
      ]) {
        expect(
          await ReleaseSignature.verify(_sums(), junk),
          isFalse,
          reason: junk,
        );
      }
    });

    test('перевод строки CRLF в манифесте ломает подпись', () async {
      // GitHub отдаёт файл байт в байт; если его по дороге перекодировали,
      // хеши в нём уже не те, что подписаны
      final crlf = utf8.encode(utf8.decode(_sums()).replaceAll('\n', '\r\n'));
      expect(await ReleaseSignature.verify(crlf, _sig()), isFalse);
    });
  });

  test('ключи приложения: два разных по 32 байта', () {
    expect(productionKeys, hasLength(2));
    expect(productionKeys.toSet(), hasLength(2));
    for (final k in productionKeys) {
      expect(base64.decode(k), hasLength(32), reason: k);
    }
  });

  group('fetchVerifiedSums', () {
    Dio dioWith(Map<String, List<int>> files) =>
        Dio()..httpClientAdapter = _Files(files);

    test('отдаёт текст манифеста, когда подпись сходится', () async {
      final text = await ReleaseSignature.fetchVerifiedSums(
        dioWith({
          'https://x.invalid/SHA256SUMS': _sums(),
          'https://x.invalid/SHA256SUMS.sig': utf8.encode(_sig()),
        }),
        sumsUrl: 'https://x.invalid/SHA256SUMS',
        signatureUrl: 'https://x.invalid/SHA256SUMS.sig',
      );
      expect(
        UpdateService.extractSha256(text, 'keqdroid-0.36.0-android.apk'),
        '3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f',
      );
    });

    test('чужая подпись: исключение, а не хеш', () async {
      final forged = base64.encode(List.filled(64, 7));
      await expectLater(
        ReleaseSignature.fetchVerifiedSums(
          dioWith({
            'https://x.invalid/SHA256SUMS': _sums(),
            'https://x.invalid/SHA256SUMS.sig': utf8.encode(forged),
          }),
          sumsUrl: 'https://x.invalid/SHA256SUMS',
          signatureUrl: 'https://x.invalid/SHA256SUMS.sig',
        ),
        throwsStateError,
      );
    });

    test('подписи нет на сервере: тоже исключение', () async {
      await expectLater(
        ReleaseSignature.fetchVerifiedSums(
          dioWith({'https://x.invalid/SHA256SUMS': _sums()}),
          sumsUrl: 'https://x.invalid/SHA256SUMS',
          signatureUrl: 'https://x.invalid/SHA256SUMS.sig',
        ),
        throwsA(anything),
      );
    });
  });

  group('где апдейтер и загрузчик гео-базы берут подпись', () {
    Map<String, dynamic> asset(String name) => {
      'name': name,
      'browser_download_url': 'https://x.invalid/$name',
    };

    List<Map<String, dynamic>> release(List<String> names) => [
      {
        'tag_name': 'v0.36.0',
        'published_at': '2026-11-20T00:00:00Z',
        'html_url': 'https://x.invalid/releases/tag/v0.36.0',
        'assets': [for (final n in names) asset(n)],
      },
    ];

    const signed = [
      'geoip.dat',
      'geoip.dat.sha256',
      'keqdroid-0.36.0-android.apk',
      'keqdroid-0.36.0-armeabi-v7a-android.apk',
      'keqdroid-windows-x64-0.36.0.zip',
      'SHA256SUMS',
      'SHA256SUMS.sig',
    ];

    test('обновление ссылается на SHA256SUMS и его подпись', () {
      final info = UpdateService.buildUpdateInfo(release(signed), '0.35.0')!;
      expect(info.checksumUrl, 'https://x.invalid/SHA256SUMS');
      expect(info.signatureUrl, 'https://x.invalid/SHA256SUMS.sig');
    });

    test('у неподписанного релиза ссылки на подпись нет', () {
      final info = UpdateService.buildUpdateInfo(
        release(signed.where((n) => n != 'SHA256SUMS.sig').toList()),
        '0.35.0',
      )!;
      expect(info.signatureUrl, isNull);
    });

    test(
      'гео-база сверяется по подписанному SHA256SUMS, не по своему .sha256',
      () {
        expect(
          GeoBaseDownloader.urlsFromAssets([for (final n in signed) asset(n)]),
          (
            'https://x.invalid/geoip.dat',
            'https://x.invalid/SHA256SUMS',
            'https://x.invalid/SHA256SUMS.sig',
          ),
        );
      },
    );

    test('без подписи гео-базу не ставим, даже при живом .sha256', () {
      expect(
        GeoBaseDownloader.urlsFromAssets([
          asset('geoip.dat'),
          asset('geoip.dat.sha256'),
          asset('SHA256SUMS'),
        ]),
        isNull,
      );
    });
  });
}

class _Files implements HttpClientAdapter {
  _Files(this.files);

  final Map<String, List<int>> files;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = files[options.uri.toString()];
    if (body == null) return ResponseBody.fromString('', 404);
    return ResponseBody.fromBytes(body, 200);
  }
}
