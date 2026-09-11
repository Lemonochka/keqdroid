import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/update_service.dart';

void main() {
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

    test('selects AppImage before tarball/deb for Linux', () {
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
      for (final platform in ['android', 'windows', 'linux']) {
        final name = UpdateService.findAssetNameForPlatform(assets, platform)!;
        expect(
          UpdateService.checksumAssetFor(assets, name)?['name'],
          'SHA256SUMS',
          reason: name,
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

    test('Linux still updates from the AppImage, the rpm is not picked', () {
      expect(
        UpdateService.findAssetNameForPlatform(assets, 'linux'),
        'keqdroid-0.19.0-x86_64.AppImage',
      );
    });
  });
}
