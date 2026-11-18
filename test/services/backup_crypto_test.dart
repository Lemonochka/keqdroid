import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/backup_crypto.dart';
import 'package:keqdroid/services/settings_backup_service.dart';

final _backup = KeqdroidBackup(
  version: 1,
  exportedAt: DateTime.utc(2026, 11, 18, 14, 2),
  data: {
    'subscriptions': [
      {'id': 's1', 'name': 'Ranteis', 'url': 'https://sub.example/secret-token'},
    ],
  },
);

final _releaseKey = List<int>.generate(32, (i) => i * 7 + 3);

void main() {
  tearDown(() {
    BackupKeys.releaseOverride = null;
    BackupKeys.noReleaseKey = false;
  });

  test('the file hides the subscription links and opens back the same', () async {
    BackupKeys.releaseOverride = _releaseKey;
    final file = await SettingsBackupService.encodeFile(_backup);

    expect(BackupCrypto.isSealed(file), isTrue);
    expect(latin1.decode(file), isNot(contains('secret-token')));
    expect(latin1.decode(file), isNot(contains('keqdis_backup')));

    final back = await SettingsBackupService.decodeFile(file);
    expect(back.data, _backup.data);
    expect(back.exportedAt, _backup.exportedAt);
  });

  test('the same backup encrypts differently every time', () async {
    BackupKeys.releaseOverride = _releaseKey;
    final one = await SettingsBackupService.encodeFile(_backup);
    final two = await SettingsBackupService.encodeFile(_backup);
    expect(one, isNot(two));
  });

  test('an old plain file still opens', () async {
    final plain = utf8.encode(_backup.toJsonString());
    final back = await SettingsBackupService.decodeFile(plain);
    expect(back.data, _backup.data);
  });

  test('a release file in a build without the release key says why', () async {
    BackupKeys.releaseOverride = _releaseKey;
    final file = await SettingsBackupService.encodeFile(_backup);
    BackupKeys.releaseOverride = null;
    BackupKeys.noReleaseKey = true;
    await expectLater(
      SettingsBackupService.decodeFile(file),
      throwsA(isA<BackupKeyUnavailable>()),
    );
  });

  test('a build without the release key writes files any build can read',
      () async {
    BackupKeys.noReleaseKey = true;
    final file = await SettingsBackupService.encodeFile(_backup);
    BackupKeys.noReleaseKey = false;
    BackupKeys.releaseOverride = _releaseKey;
    final back = await SettingsBackupService.decodeFile(file);
    expect(back.data, _backup.data);
  });

  test('a changed byte is caught instead of restoring garbage', () async {
    BackupKeys.releaseOverride = _releaseKey;
    final file = await SettingsBackupService.encodeFile(_backup);
    for (final at in [5, 10, file.length ~/ 2, file.length - 1]) {
      final broken = List<int>.of(file);
      broken[at] ^= 0x01;
      await expectLater(
        SettingsBackupService.decodeFile(broken),
        throwsA(anyOf(isA<FormatException>(), isA<BackupKeyUnavailable>())),
        reason: 'byte $at',
      );
    }
  });

  test('another release key cannot open it', () async {
    BackupKeys.releaseOverride = _releaseKey;
    final file = await SettingsBackupService.encodeFile(_backup);
    BackupKeys.releaseOverride = List<int>.filled(32, 9);
    await expectLater(
      SettingsBackupService.decodeFile(file),
      throwsA(isA<FormatException>()),
    );
  });

  test('the release key is the xor of the two halves the build carries', () {
    expect(BackupKeys.assemble(List.filled(8, 0), List.filled(8, 0)), isNull);
    final key = BackupKeys.assemble(
      [0xFFFFFFFF, 0, 0, 0, 0, 0, 0, 0x12345678],
      [0x0F0F0F0F, 0, 0, 0, 0, 0, 0, 0x12345679],
    )!;
    expect(key, hasLength(32));
    expect(key.sublist(0, 4), [0xF0, 0xF0, 0xF0, 0xF0]);
    expect(key.sublist(28), [0, 0, 0, 1]);
  });
}
