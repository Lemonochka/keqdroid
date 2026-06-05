import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/update_service.dart';

void main() {
  group('UpdateService.compareVersions', () {
    test('0.2.10 is newer than 0.2.9', () {
      expect(
        UpdateService.compareVersions('Android0.2.10', 'Android0.2.9'),
        1,
      );
    });

    test('0.2.9 is numerically older than 0.2.81', () {
      expect(
        UpdateService.compareVersions('Android0.2.9', 'Android0.2.81'),
        -1,
      );
    });
  });

  group('UpdateService.isNewerRelease', () {
    test('0.2.9 is newer than 0.2.81 when GitHub release is later', () {
      final older = DateTime.utc(2026, 1, 1);
      final newer = DateTime.utc(2026, 2, 1);
      expect(
        UpdateService.isNewerRelease(
          'Android0.2.9',
          'Android0.2.81',
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
          'Android0.2.81',
          'Android0.2.9',
          latestPublished: older,
          currentPublished: newer,
        ),
        isFalse,
      );
    });

    test('0.2.10 is newer without needing dates', () {
      expect(
        UpdateService.isNewerRelease('Android0.2.10', 'Android0.2.9'),
        isTrue,
      );
    });
  });

  group('UpdateService.displayVersion', () {
    test('strips Android prefix', () {
      expect(UpdateService.displayVersion('Android0.2.9'), '0.2.9');
    });
  });
}
