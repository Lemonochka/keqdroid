import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/update_service.dart';

void main() {
  group('UpdateService.compareVersions', () {
    test('v0.2.10 is newer than v0.2.9', () {
      expect(
        UpdateService.compareVersions('v0.2.10', 'v0.2.9'),
        1,
      );
    });

    test('0.2.9 is numerically older than 0.2.81', () {
      expect(
        UpdateService.compareVersions('v0.2.9', '0.2.81'),
        -1,
      );
    });

    test('legacy Android tags still compare correctly', () {
      expect(
        UpdateService.compareVersions('Android0.2.10', 'Android0.2.9'),
        1,
      );
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
      expect(
        UpdateService.isNewerRelease('v0.2.10', '0.2.9'),
        isTrue,
      );
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
      expect(
        UpdateService.extractSha256(manifest, 'keqdroid-0.5.0.apk'),
        hash,
      );
      expect(
        UpdateService.extractSha256(manifest, 'keqdroid-windows-x64-0.5.0.zip'),
        other,
      );
    });

    test('returns null when no 64-hex hash is present', () {
      expect(UpdateService.extractSha256('not a hash', 'x.apk'), isNull);
    });
  });
}
