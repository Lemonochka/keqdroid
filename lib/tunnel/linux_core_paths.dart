import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Linux counterpart of [WindowsCorePaths]: locates the bundled xray / sing-box
/// / wireproxy ELF binaries and the geoip/geosite data files.
///
/// Resolution order mirrors Windows: next to flutter_assets, next to the
/// executable, extracted from the asset bundle to a temp dir, then `$PATH`.
/// Extracted binaries are marked executable (`chmod +x`) since the asset bundle
/// does not preserve the executable bit.
class LinuxCorePaths {
  LinuxCorePaths._();

  static const assetXray = 'assets/bin/linux/xray';
  static const assetSingbox = 'assets/bin/linux/sing-box';
  static const assetWireproxy = 'assets/bin/linux/wireproxy';
  static const assetGeoip = 'assets/bin/linux/geoip.dat';
  static const assetGeosite = 'assets/bin/linux/geosite.dat';
  static const geoFileNames = ['geoip.dat', 'geosite.dat'];

  static const binariesHint =
      'Положите xray, sing-box и wireproxy в assets/bin/linux/ '
      '(см. README) и пересоберите приложение, '
      'или поместите их рядом с исполняемым файлом / в \$PATH.';

  static Future<Directory> sessionDir() async {
    return Directory.systemTemp.createTemp('keqdis_session_');
  }

  static Future<String?> xrayExecutable() =>
      _resolveExecutable(assetXray, 'xray');

  static Future<String?> singboxExecutable() =>
      _resolveExecutable(assetSingbox, 'sing-box');

  static Future<String?> wireproxyExecutable() =>
      _resolveExecutable(assetWireproxy, 'wireproxy');

  /// Directory holding geoip.dat / geosite.dat for xray's asset lookup
  /// (passed to xray via XRAY_LOCATION_ASSET). Null if not found.
  static Future<String?> geoAssetDir() async {
    final besideAssets = _geoDirBesideFlutterAssets();
    if (besideAssets != null) return besideAssets;

    final exeDir = p.dirname(Platform.resolvedExecutable);
    if (geoFileNames.any((f) => File(p.join(exeDir, f)).existsSync())) {
      return exeDir;
    }

    return _extractGeoFilesToTemp();
  }

  static String? _geoDirBesideFlutterAssets() {
    final dir = p.join(
      p.dirname(Platform.resolvedExecutable),
      'data',
      'flutter_assets',
      'assets',
      'bin',
      'linux',
    );
    final hasGeo = geoFileNames.any((f) => File(p.join(dir, f)).existsSync());
    return hasGeo ? dir : null;
  }

  static Future<String?> _extractGeoFilesToTemp() async {
    try {
      final outDir = Directory(
        p.join(
          (await Directory.systemTemp.createTemp('keqdis_geo_')).path,
          'geo',
        ),
      );
      if (!outDir.existsSync()) outDir.createSync(recursive: true);

      var extracted = false;
      for (final entry in {
        assetGeoip: 'geoip.dat',
        assetGeosite: 'geosite.dat',
      }.entries) {
        try {
          final data = await rootBundle.load(entry.key);
          await File(p.join(outDir.path, entry.value)).writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            flush: true,
          );
          extracted = true;
        } catch (_) {
          // file not bundled — skip
        }
      }
      return extracted ? outDir.path : null;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _resolveExecutable(
    String assetKey,
    String fileName,
  ) async {
    final fromFlutterBundle = _pathBesideFlutterAssets(fileName);
    if (fromFlutterBundle != null) {
      await _ensureExecutable(fromFlutterBundle);
      return fromFlutterBundle;
    }

    final besideExe = p.join(p.dirname(Platform.resolvedExecutable), fileName);
    if (File(besideExe).existsSync()) {
      await _ensureExecutable(besideExe);
      return besideExe;
    }

    final fromAsset = await _extractAssetToTemp(assetKey, fileName);
    if (fromAsset != null) {
      await _ensureExecutable(fromAsset);
      return fromAsset;
    }

    return _which(fileName);
  }

  /// `build/linux/x64/release/bundle/data/flutter_assets/...`
  static String? _pathBesideFlutterAssets(String fileName) {
    final path = p.join(
      p.dirname(Platform.resolvedExecutable),
      'data',
      'flutter_assets',
      'assets',
      'bin',
      'linux',
      fileName,
    );
    return File(path).existsSync() ? path : null;
  }

  static Future<String?> _extractAssetToTemp(
    String assetKey,
    String fileName,
  ) async {
    try {
      final data = await rootBundle.load(assetKey);
      final outDir = Directory(
        p.join(
          (await Directory.systemTemp.createTemp('keqdis_bin_')).path,
          'cores',
        ),
      );
      if (!outDir.existsSync()) outDir.createSync(recursive: true);
      final outFile = File(p.join(outDir.path, fileName));
      await outFile.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      return outFile.path;
    } catch (_) {
      return null;
    }
  }

  /// Adds the executable bit; the asset bundle stores files without it.
  static Future<void> _ensureExecutable(String path) async {
    try {
      final stat = await FileStat.stat(path);
      // Already executable by owner — skip the chmod round-trip.
      if (stat.mode & 0x40 != 0) return;
      await Process.run('chmod', ['+x', path]);
    } catch (_) {
      // best effort; the launch will surface a clear error if it stays non-exec
    }
  }

  static String? _which(String name) {
    final pathEnv = Platform.environment['PATH'];
    if (pathEnv == null) return null;
    for (final dir in pathEnv.split(':')) {
      final candidate = p.join(dir.trim(), name);
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }
}
