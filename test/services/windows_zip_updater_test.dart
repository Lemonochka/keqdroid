import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/windows_zip_updater.dart';
import 'package:path/path.dart' as p;

void main() {
  group('WindowsZipUpdater.findPayloadRoot', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('keqdroid_zip_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('finds exe at archive root', () async {
      await File(p.join(tempDir.path, WindowsZipUpdater.exeName)).create();

      expect(WindowsZipUpdater.findPayloadRoot(tempDir), tempDir.path);
    });

    test('finds exe inside a single nested folder', () async {
      final nested = Directory(p.join(tempDir.path, 'keqdroid'));
      await nested.create();
      await File(p.join(nested.path, WindowsZipUpdater.exeName)).create();

      expect(WindowsZipUpdater.findPayloadRoot(tempDir), nested.path);
    });

    test('returns null when exe is missing', () async {
      await Directory(p.join(tempDir.path, 'data')).create();

      expect(WindowsZipUpdater.findPayloadRoot(tempDir), isNull);
    });
  });
}
