import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/tunnel/macos_core_paths.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('keq_macos_paths_');
    MacosCorePaths.cacheRootOverride = p.join(tmp.path, 'Caches');
    MacosCorePaths.executableOverride = p.join(
      tmp.path,
      'keqdroid.app',
      'Contents',
      'MacOS',
      'keqdroid',
    );
    MacosCorePaths.isExecutableOverride = null;
  });

  tearDown(() {
    MacosCorePaths.cacheRootOverride = null;
    MacosCorePaths.executableOverride = null;
    MacosCorePaths.isExecutableOverride = null;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test(
    'uses executable bundle binaries directly in place without copying',
    () async {
      final binDir = Directory(
        p.join(tmp.path, 'keqdroid.app', 'Contents', 'Resources', 'bin'),
      )..createSync(recursive: true);
      final xraySrc = File(p.join(binDir.path, 'xray'))
        ..writeAsStringSync('xray-bin');
      final mihomoSrc = File(p.join(binDir.path, 'mihomo'))
        ..writeAsStringSync('mihomo-bin');
      final daemonSrc = File(p.join(binDir.path, 'keqdroid-tun'))
        ..writeAsStringSync('daemon-bin');
      MacosCorePaths.isExecutableOverride = (_) => true;

      expect(await MacosCorePaths.xrayExecutable(), xraySrc.path);
      expect(await MacosCorePaths.mihomoExecutable(), mihomoSrc.path);
      expect(MacosCorePaths.daemonExecutable(), daemonSrc.path);
      expect(
        Directory(p.join(tmp.path, 'Caches', 'keqdroid', 'cores')).existsSync(),
        isFalse,
      );
    },
  );

  test(
    'stages non-executable bundle binaries into Caches and restages on change',
    () async {
      MacosCorePaths.isExecutableOverride = (_) => false;
      final binDir = Directory(
        p.join(tmp.path, 'keqdroid.app', 'Contents', 'Resources', 'bin'),
      )..createSync(recursive: true);
      final source = File(p.join(binDir.path, 'xray'))
        ..writeAsStringSync('core-v1');

      final staged = await MacosCorePaths.xrayExecutable();
      expect(
        staged!,
        startsWith(p.join(tmp.path, 'Caches', 'keqdroid', 'cores')),
      );
      expect(File(staged).readAsStringSync(), 'core-v1');

      source.writeAsStringSync('core-v2');
      await source.setLastModified(
        source.lastModifiedSync().add(const Duration(seconds: 2)),
      );
      final restaged = await MacosCorePaths.xrayExecutable();
      expect(restaged, staged);
      expect(File(restaged!).readAsStringSync(), 'core-v2');
    },
  );

  test(
    'prefers user cached geo over bundle geo and syncs mihomo home',
    () async {
      final binDir = Directory(
        p.join(tmp.path, 'keqdroid.app', 'Contents', 'Resources', 'bin'),
      )..createSync(recursive: true);
      File(p.join(binDir.path, 'geoip.dat')).writeAsBytesSync([1, 2, 3, 4]);
      File(p.join(binDir.path, 'geosite.dat')).writeAsBytesSync([5, 6, 7]);

      expect(await MacosCorePaths.geoAssetDir(), binDir.path);

      final home = await MacosCorePaths.mihomoHomeDir();
      expect(File(p.join(home, 'geoip.dat')).readAsBytesSync(), [1, 2, 3, 4]);
      expect(File(p.join(home, 'geosite.dat')).readAsBytesSync(), [5, 6, 7]);

      final updatedGeo = File(p.join(binDir.path, 'geoip.dat'))
        ..writeAsBytesSync([9, 8, 7, 6, 5]);
      await updatedGeo.setLastModified(
        updatedGeo.lastModifiedSync().add(const Duration(seconds: 2)),
      );
      await MacosCorePaths.mihomoHomeDir();
      expect(File(p.join(home, 'geoip.dat')).readAsBytesSync(), [
        9,
        8,
        7,
        6,
        5,
      ]);

      final cachedGeo = Directory(
        p.join(tmp.path, 'Caches', 'keqdroid', 'geo'),
      )..createSync(recursive: true);
      File(p.join(cachedGeo.path, 'geoip.dat')).writeAsBytesSync([42]);
      expect(await MacosCorePaths.geoAssetDir(), cachedGeo.path);
    },
  );

  test('sha256Of refreshes when file content and mtime change', () async {
    final file = File(p.join(tmp.path, 'sample.bin'))
      ..writeAsStringSync('alpha');
    final h1 = await MacosCorePaths.sha256Of(file.path);
    expect(h1, hasLength(64));
    expect(await MacosCorePaths.sha256Of(file.path), h1);

    file.writeAsStringSync('bravo');
    await file.setLastModified(
      file.lastModifiedSync().add(const Duration(seconds: 2)),
    );
    final h2 = await MacosCorePaths.sha256Of(file.path);
    expect(h2, isNot(h1));
  });

  test('replaceAtomically writes cleanly and cleans temp on error', () async {
    final target = p.join(tmp.path, 'file.bin');
    await MacosCorePaths.replaceAtomically(
      target,
      (tmpPath) => File(tmpPath).writeAsString('ok'),
    );
    expect(File(target).readAsStringSync(), 'ok');

    await expectLater(
      MacosCorePaths.replaceAtomically(target, (tmpPath) async {
        await File(tmpPath).writeAsString('partial');
        throw StateError('boom');
      }),
      throwsStateError,
    );
    expect(File(target).readAsStringSync(), 'ok');
    expect(tmp.listSync().where((e) => e.path.contains('.tmp-')), isEmpty);
  });
}
