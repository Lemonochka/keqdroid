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
  });

  tearDown(() {
    MacosCorePaths.cacheRootOverride = null;
    MacosCorePaths.executableOverride = null;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('resolves and stages xray and mihomo from Contents/Resources/bin', () async {
    final binDir = Directory(
      p.join(tmp.path, 'keqdroid.app', 'Contents', 'Resources', 'bin'),
    )..createSync(recursive: true);
    File(p.join(binDir.path, 'xray')).writeAsStringSync('#!/bin/sh\necho xray\n');
    File(p.join(binDir.path, 'mihomo')).writeAsStringSync('#!/bin/sh\necho mihomo\n');

    final xray = await MacosCorePaths.xrayExecutable();
    final mihomo = await MacosCorePaths.mihomoExecutable();

    expect(xray, isNotNull);
    expect(mihomo, isNotNull);
    expect(xray!, startsWith(p.join(tmp.path, 'Caches', 'keqdroid', 'cores')));
    expect(mihomo!, startsWith(p.join(tmp.path, 'Caches', 'keqdroid', 'cores')));
    expect(File(xray).existsSync(), isTrue);
    expect(File(mihomo).existsSync(), isTrue);
  });

  test('finds geoip and geosite in bundle Resources/bin and copies to mihomo home', () async {
    final binDir = Directory(
      p.join(tmp.path, 'keqdroid.app', 'Contents', 'Resources', 'bin'),
    )..createSync(recursive: true);
    File(p.join(binDir.path, 'geoip.dat')).writeAsBytesSync([1, 2, 3, 4]);
    File(p.join(binDir.path, 'geosite.dat')).writeAsBytesSync([5, 6, 7]);

    final geoDir = await MacosCorePaths.geoAssetDir();
    expect(geoDir, binDir.path);

    final home = await MacosCorePaths.mihomoHomeDir();
    expect(File(p.join(home, 'geoip.dat')).readAsBytesSync(), [1, 2, 3, 4]);
    expect(File(p.join(home, 'geosite.dat')).readAsBytesSync(), [5, 6, 7]);
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
