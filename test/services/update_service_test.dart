import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/linux_install.dart';
import 'package:keqdroid/services/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Сетевой слой по сценарию: каждый ответ — либо исключение, которое бросил бы
/// dart:io, либо HTTP-ответ.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.script);

  final List<Object> script;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final step = script[calls++];
    if (step is ResponseBody) return step;
    throw step;
  }

  @override
  void close({bool force = false}) {}
}

// Текст с жалобы: рукопожатие с GitHub прошло, начало ответа — не TLS.
// Dio получает его от dart:io как HttpException и заворачивает в unknown.
final _brokenTls = HttpException(
  '\n\tWRONG_VERSION_NUMBER(tls_record.cc:127) error 268435703',
  uri: Uri.parse('https://api.github.com/repos/Lemonochka/keqdroid/releases'),
);

ResponseBody _releases() => ResponseBody.fromString(
      jsonEncode([
        {
          'tag_name': 'v0.23.0',
          'published_at': '2026-09-27T10:00:00Z',
          'prerelease': false,
          'draft': false,
          'assets': <Object>[],
        },
      ]),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

void main() {
  group('загрузка списка релизов', () {
    test('испорченное начало ответа — один повтор, и проверка проходит',
        () async {
      final adapter = _ScriptedAdapter([_brokenTls, _releases()]);
      final dio = Dio()..httpClientAdapter = adapter;

      final releases = await UpdateService.fetchReleases(dio);

      expect(adapter.calls, 2);
      expect(releases.single['tag_name'], 'v0.23.0');
    });

    test('сломалось и при повторе — ошибка доходит до экрана', () async {
      final adapter = _ScriptedAdapter([_brokenTls, _brokenTls]);
      final dio = Dio()..httpClientAdapter = adapter;

      await expectLater(
        UpdateService.fetchReleases(dio),
        throwsA(isA<DioException>()),
      );
      expect(adapter.calls, 2);
    });

    test('лимит GitHub повтором не лечится', () async {
      final adapter = _ScriptedAdapter([ResponseBody.fromString('{}', 403)]);
      final dio = Dio()..httpClientAdapter = adapter;

      await expectLater(
        UpdateService.fetchReleases(dio),
        throwsA(isA<StateError>()),
      );
      expect(adapter.calls, 1);
    });

    test('таймаут не повторяем: ручная проверка ждала бы вдвое дольше',
        () async {
      final adapter = _ScriptedAdapter([
        DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.connectionTimeout,
        ),
      ]);
      final dio = Dio()..httpClientAdapter = adapter;

      await expectLater(
        UpdateService.fetchReleases(dio),
        throwsA(isA<DioException>()),
      );
      expect(adapter.calls, 1);
    });
  });

  group('фоновая проверка', () {
    final realFetch = UpdateService.fetchUpdate;
    final realGap = UpdateService.minAutoCheckGap;
    final offline = DioException(
      requestOptions: RequestOptions(),
      type: DioExceptionType.connectionError,
    );
    UpdateInfo info(String version) => UpdateInfo(
          currentVersion: '0.26.0',
          latestVersion: version,
          downloadUrl: 'https://example.invalid/keqdroid.apk',
          apkSize: 1,
        );
    late int calls;

    void answer(List<Object?> script) {
      UpdateService.fetchUpdate = ({
        required bool viaLocalProxy,
        required int httpPort,
      }) async {
        final step = script[calls++];
        if (step is Exception) throw step;
        return step as UpdateInfo?;
      };
    }

    setUp(() {
      calls = 0;
      UpdateService.resetAutoCheck();
      SharedPreferences.setMockInitialValues({});
    });
    tearDown(() {
      UpdateService.fetchUpdate = realFetch;
      UpdateService.minAutoCheckGap = realGap;
      UpdateService.resetAutoCheck();
    });

    test('GitHub не ответил и удачной проверки не было: ошибка, а не актуальная версия',
        () async {
      answer([offline, offline]);

      await expectLater(UpdateService.checkForUpdate(), throwsA(offline));
      // неудача паузу между проверками не включает
      await expectLater(UpdateService.checkForUpdate(), throwsA(offline));
      expect(calls, 2);
    });

    test('после удачной проверки «обновлений нет» сбой не поднимает тревогу',
        () async {
      UpdateService.minAutoCheckGap = Duration.zero;
      answer([null, offline]);

      expect(await UpdateService.checkForUpdate(), isNull);
      expect(await UpdateService.checkForUpdate(), isNull);
      expect(calls, 2);
    });

    test('после удачной проверки с обновлением сбой оставляет обновление',
        () async {
      UpdateService.minAutoCheckGap = Duration.zero;
      answer([info('0.27.0'), offline]);

      await UpdateService.checkForUpdate();
      final again = await UpdateService.checkForUpdate();
      expect(again?.latestVersion, '0.27.0');
      expect(calls, 2);
    });

    test('пропущенная версия остаётся в ответе, окно гасит сам показ', () async {
      SharedPreferences.setMockInitialValues({
        'skip_update_version': '0.27.0',
      });
      answer([info('0.27.0')]);

      final found = await UpdateService.checkForUpdate();
      expect(found?.latestVersion, '0.27.0');
      expect(await UpdateService.isSkipped('0.27.0'), isTrue);
      expect(await UpdateService.isSkipped('0.28.0'), isFalse);
      // и из кэша между проверками тоже
      expect((await UpdateService.checkForUpdate())?.latestVersion, '0.27.0');
      expect(calls, 1);
    });

    test('переключение VPN посреди первой проверки ждёт её, а не отвечает пустым',
        () async {
      final reply = Completer<UpdateInfo?>();
      UpdateService.fetchUpdate = ({
        required bool viaLocalProxy,
        required int httpPort,
      }) {
        calls++;
        return reply.future;
      };

      final first = UpdateService.checkForUpdate();
      final second = UpdateService.checkForUpdate(viaLocalProxy: true);
      reply.complete(info('0.27.0'));

      expect((await first)?.latestVersion, '0.27.0');
      expect((await second)?.latestVersion, '0.27.0');
      expect(calls, 1);
    });

    test('ручная проверка ошибку показывает всегда, даже после удачной', () async {
      answer([null, offline]);

      await UpdateService.checkForUpdate();
      await expectLater(
        UpdateService.checkForUpdate(force: true),
        throwsA(offline),
      );
    });
  });

  group('UpdateService.compareVersions', () {
    test('v0.2.10 is newer than v0.2.9', () {
      expect(UpdateService.compareVersions('v0.2.10', 'v0.2.9'), 1);
    });

    test('0.2.9 is numerically older than 0.2.81', () {
      expect(UpdateService.compareVersions('v0.2.9', '0.2.81'), -1);
    });

    test('legacy Android tags still compare correctly', () {
      expect(UpdateService.compareVersions('Android0.2.10', 'Android0.2.9'), 1);
    });
  });

  group('UpdateService.isNewerRelease', () {
    test('v0.2.9 is newer than 0.2.81 when GitHub release is later', () {
      final older = DateTime.utc(2026, 1, 1);
      final newer = DateTime.utc(2026, 2, 1);
      expect(
        UpdateService.isNewerRelease(
          'v0.2.9',
          '0.2.81',
          latestPublished: newer,
          currentPublished: older,
        ),
        isTrue,
      );
    });

    test('does not offer downgrade when numeric and dates disagree', () {
      final older = DateTime.utc(2026, 1, 1);
      final newer = DateTime.utc(2026, 2, 1);
      expect(
        UpdateService.isNewerRelease(
          'v0.2.81',
          '0.2.9',
          latestPublished: older,
          currentPublished: newer,
        ),
        isFalse,
      );
    });

    test('v0.2.10 is newer without needing dates', () {
      expect(UpdateService.isNewerRelease('v0.2.10', '0.2.9'), isTrue);
    });
  });

  group('UpdateService.displayVersion', () {
    test('strips v prefix', () {
      expect(UpdateService.displayVersion('v0.2.9'), '0.2.9');
    });

    test('strips legacy Android prefix', () {
      expect(UpdateService.displayVersion('Android0.2.9'), '0.2.9');
    });
  });

  group('UpdateService asset selection', () {
    final assets = [
      {'name': 'keqdroid-0.5.1.apk'},
      {'name': 'keqdroid-windows-x64-0.5.1.zip'},
      {'name': 'keqdroid-0.5.1-linux-x64.tar.gz'},
      {'name': 'keqdroid-0.5.1-x86_64.AppImage'},
      {'name': 'keqdroid_0.5.1_amd64.deb'},
    ];

    test('selects APK for Android', () {
      expect(
        UpdateService.findAssetNameForPlatform(assets, 'android'),
        'keqdroid-0.5.1.apk',
      );
    });

    test('selects Windows archive for Windows', () {
      expect(
        UpdateService.findAssetNameForPlatform(assets, 'windows'),
        'keqdroid-windows-x64-0.5.1.zip',
      );
    });

    test('the installed copy takes the installer, the portable one the zip', () {
      final withSetup = [
        ...assets,
        {'name': 'keqdroid-windows-x64-0.5.1-setup.exe'},
      ];
      expect(
        UpdateService.findAssetNameForPlatform(withSetup, 'windows-installed'),
        'keqdroid-windows-x64-0.5.1-setup.exe',
      );
      expect(
        UpdateService.findAssetNameForPlatform(withSetup, 'windows'),
        'keqdroid-windows-x64-0.5.1.zip',
      );
      // релиз без установщика: установленная копия всё равно обновится
      expect(
        UpdateService.findAssetNameForPlatform(assets, 'windows-installed'),
        'keqdroid-windows-x64-0.5.1.zip',
      );
    });

    test('selects the AppImage for a Linux AppImage install', () {
      expect(
        UpdateService.findAssetNameForPlatform(assets, 'linux'),
        'keqdroid-0.5.1-x86_64.AppImage',
      );
    });
  });

  group('UpdateService.extractSha256', () {
    const hash =
        '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08';

    test('reads a bare hash sidecar', () {
      expect(UpdateService.extractSha256(hash, 'keqdroid-0.5.0.apk'), hash);
    });

    test('trims trailing whitespace/newline from a sidecar', () {
      expect(
        UpdateService.extractSha256('$hash\n', 'keqdroid-0.5.0.apk'),
        hash,
      );
    });

    test('normalizes uppercase hex to lowercase', () {
      expect(
        UpdateService.extractSha256(hash.toUpperCase(), 'keqdroid-0.5.0.apk'),
        hash,
      );
    });

    test('picks the matching line from a sha256sum-style manifest', () {
      const other =
          '0000000000000000000000000000000000000000000000000000000000000000';
      final manifest =
          '$other  keqdroid-windows-x64-0.5.0.zip\n'
          '$hash  keqdroid-0.5.0.apk\n';
      expect(UpdateService.extractSha256(manifest, 'keqdroid-0.5.0.apk'), hash);
      expect(
        UpdateService.extractSha256(manifest, 'keqdroid-windows-x64-0.5.0.zip'),
        other,
      );
    });

    test('returns null when no 64-hex hash is present', () {
      expect(UpdateService.extractSha256('not a hash', 'x.apk'), isNull);
    });
  });

  group('два APK в релизе: arm64 и armeabi-v7a', () {
    const main = 'keqdroid-0.30.0-android.apk';
    const arm32 = 'keqdroid-0.30.0-armeabi-v7a-android.apk';
    const names = [
      'PKGBUILD',
      'SHA256SUMS',
      'geoip.dat',
      'geoip.dat.sha256',
      'keqdroid-0.30.0-1.x86_64.rpm',
      main,
      arm32,
      'keqdroid-0.30.0-linux-x64.tar.gz',
      'keqdroid-0.30.0-x86_64.AppImage',
      'keqdroid-windows-x64-0.30.0.zip',
      'keqdroid_0.30.0_amd64.deb',
    ];
    List<Map<String, dynamic>> assetsOf(List<String> order) => [
          for (final n in order)
            {'name': n, 'browser_download_url': 'https://example.invalid/$n'},
        ];

    // GitHub отдаёт ассеты по имени без учёта регистра (так в каждом
    // опубликованном релизе), а не по времени загрузки.
    List<String> githubOrder(List<String> names) => [...names]
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    test('версии до 32-битного APK по-прежнему получают основной', () {
      // Все они берут первый .apk в списке.
      final firstApk =
          githubOrder(names).firstWhere((n) => n.toLowerCase().endsWith('.apk'));
      expect(firstApk, main);
    });

    test('каждая архитектура получает свой APK при любом порядке', () {
      for (final order in [names, names.reversed.toList()]) {
        final assets = assetsOf(order);
        expect(UpdateService.findAssetNameForPlatform(assets, 'android'), main);
        expect(
          UpdateService.findAssetNameForPlatform(assets, 'android-arm'),
          arm32,
        );
      }
    });

    test('в старом релизе 32-битного нет — обновление ему не предлагается', () {
      final assets = assetsOf(names.where((n) => n != arm32).toList());
      expect(
        UpdateService.findAssetNameForPlatform(assets, 'android-arm'),
        isNull,
      );
      expect(UpdateService.findAssetNameForPlatform(assets, 'android'), main);
    });

    test('у каждого APK своя строка в SHA256SUMS', () {
      final manifest = [
        for (final n in names.where((n) => n != 'SHA256SUMS'))
          '${'0' * 63}${names.indexOf(n) % 10}  $n',
      ];
      for (final apk in [main, arm32]) {
        expect(
          manifest.where((l) => l.toLowerCase().contains(apk.toLowerCase())),
          hasLength(1),
          reason: apk,
        );
        expect(
          UpdateService.checksumAssetFor(assetsOf(names), apk)?['name'],
          'SHA256SUMS',
        );
      }
    });
  });

  group('one SHA256SUMS for the whole release', () {
    // Так выглядит релиз с 0.19.0: рядом с ассетами нет ни одного .sha256,
    // кроме geoip.dat.sha256 для загрузчика geo-базы в 0.15–0.18.
    const names = [
      'PKGBUILD',
      'geoip.dat',
      'keqdroid-0.19.0-1.x86_64.rpm',
      'keqdroid-0.19.0-android.apk',
      'keqdroid-0.19.0-linux-x64.tar.gz',
      'keqdroid-0.19.0-x86_64.AppImage',
      'keqdroid-windows-x64-0.19.0.zip',
      'keqdroid-windows-x64-0.19.0-setup.exe',
      'keqdroid_0.19.0_amd64.deb',
    ];
    String hashOf(int i) => (i + 1).toRadixString(16).padLeft(64, '0');
    final manifest = [
      for (var i = 0; i < names.length; i++) '${hashOf(i)}  ${names[i]}',
    ].join('\n');
    final assets = <Map<String, dynamic>>[
      for (final n in [...names, 'geoip.dat.sha256', 'SHA256SUMS'])
        {'name': n, 'browser_download_url': 'https://example.invalid/$n'},
    ];

    test('every platform asset is verified against the manifest', () {
      for (final platform in [
        'android',
        'windows',
        'windows-installed',
        'linux',
      ]) {
        final name = UpdateService.findAssetNameForPlatform(assets, platform)!;
        expect(
          UpdateService.checksumAssetFor(assets, name)?['name'],
          'SHA256SUMS',
          reason: name,
        );
      }
      for (final kind in LinuxInstallKind.values) {
        final name = UpdateService.findAssetNameForPlatform(
          assets,
          'linux',
          linuxKind: kind,
        )!;
        expect(
          UpdateService.checksumAssetFor(assets, name)?['name'],
          'SHA256SUMS',
          reason: '$kind: $name',
        );
      }
    });

    test('each asset reads its own line, the way every version reads it', () {
      for (var i = 0; i < names.length; i++) {
        expect(
          UpdateService.extractSha256(manifest, names[i]),
          hashOf(i),
          reason: names[i],
        );
        // Все версии берут первую строку, СОДЕРЖАЩУЮ имя ассета: имя, которое
        // оказалось частью чужой строки, получило бы чужой хеш.
        final lines = manifest
            .split('\n')
            .where((l) => l.toLowerCase().contains(names[i].toLowerCase()));
        expect(lines, hasLength(1), reason: names[i]);
      }
    });

    test('Linux updates with the file it was installed from', () {
      String? pick(LinuxInstallKind kind) =>
          UpdateService.findAssetNameForPlatform(
            assets,
            'linux',
            linuxKind: kind,
          );
      expect(pick(LinuxInstallKind.appImage), 'keqdroid-0.19.0-x86_64.AppImage');
      expect(pick(LinuxInstallKind.deb), 'keqdroid_0.19.0_amd64.deb');
      expect(pick(LinuxInstallKind.rpm), 'keqdroid-0.19.0-1.x86_64.rpm');
      for (final kind in [
        LinuxInstallKind.pacman,
        LinuxInstallKind.portable,
        LinuxInstallKind.readOnly,
      ]) {
        expect(pick(kind), 'keqdroid-0.19.0-linux-x64.tar.gz', reason: '$kind');
      }
    });
  });

  group('обновление Linux по способу установки', () {
    final releases = [
      {
        'tag_name': 'v0.25.0',
        'published_at': '2026-10-01T00:00:00Z',
        'html_url': 'https://example.invalid/releases/tag/v0.25.0',
        'body': '',
        'assets': [
          for (final n in [
            'keqdroid-0.25.0-x86_64.AppImage',
            'keqdroid_0.25.0_amd64.deb',
            'keqdroid-0.25.0-1.x86_64.rpm',
            'keqdroid-0.25.0-linux-x64.tar.gz',
            'SHA256SUMS',
          ])
            {
              'name': n,
              'size': n.length,
              'browser_download_url': 'https://example.invalid/$n',
            },
        ],
      },
    ];
    UpdateInfo info(LinuxInstallKind kind) => UpdateService.buildUpdateInfo(
          releases,
          '0.24.0',
          linuxKind: kind,
        )!;

    test('deb, rpm, AppImage и архив качаются и ставятся из приложения', () {
      for (final kind in [
        LinuxInstallKind.appImage,
        LinuxInstallKind.deb,
        LinuxInstallKind.rpm,
        LinuxInstallKind.portable,
      ]) {
        expect(info(kind).openInBrowser, isFalse, reason: '$kind');
        expect(
          info(kind).downloadUrl,
          'https://example.invalid/${info(kind).assetName}',
        );
        expect(info(kind).checksumUrl, 'https://example.invalid/SHA256SUMS');
      }
    });

    test('пакет pacman ведёт на страницу релиза, его файлы не трогаются', () {
      final arch = info(LinuxInstallKind.pacman);
      expect(arch.openInBrowser, isTrue);
      expect(arch.downloadUrl, 'https://example.invalid/releases/tag/v0.25.0');
      // Размер — архива, из которого PKGBUILD собирает пакет.
      expect(arch.apkSize, 'keqdroid-0.25.0-linux-x64.tar.gz'.length);
    });

    test('архив в папке без записи скачивается браузером', () {
      final ro = info(LinuxInstallKind.readOnly);
      expect(ro.openInBrowser, isTrue);
      expect(
        ro.downloadUrl,
        'https://example.invalid/keqdroid-0.25.0-linux-x64.tar.gz',
      );
    });

    test('скачанный файл любого вида узнаётся по расширению', () {
      // Без этого файл, выбранный для установки, падал бы на «Unsupported
      // update file type» уже после загрузки.
      for (final kind in LinuxInstallKind.values) {
        final url = info(kind).downloadUrl;
        if (info(kind).openInBrowser) continue;
        expect(
          () => UpdateService.extensionFromUrl(url),
          returnsNormally,
          reason: '$kind: $url',
        );
      }
      expect(
        UpdateService.extensionFromUrl(
          'https://example.invalid/keqdroid-0.25.0-1.x86_64.rpm',
        ),
        '.rpm',
      );
    });

    test('нет файла своего вида — нет и обновления', () {
      final noDeb = [
        {
          ...releases.single,
          'assets': [
            for (final a in releases.single['assets'] as List)
              if (!(a['name'] as String).endsWith('.deb')) a,
          ],
        },
      ];
      expect(
        UpdateService.buildUpdateInfo(
          noDeb,
          '0.24.0',
          linuxKind: LinuxInstallKind.deb,
        ),
        isNull,
      );
    });
  });
}
