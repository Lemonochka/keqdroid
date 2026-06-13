import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// пути к xray.exe и sing-box.exe на windows
class WindowsCorePaths {
  WindowsCorePaths._();

  static const assetXray = 'assets/bin/windows/xray.exe';
  static const assetSingbox = 'assets/bin/windows/sing-box.exe';
  static const assetKphttp = 'assets/bin/windows/kphttp-client.exe';
  static const assetGeoip = 'assets/bin/windows/geoip.dat';
  static const assetGeosite = 'assets/bin/windows/geosite.dat';
  static const geoFileNames = ['geoip.dat', 'geosite.dat'];

  static const binariesHint =
      'Положите xray.exe, sing-box.exe и kphttp-client.exe в assets/bin/windows/ '
      '(см. README) и пересоберите приложение, '
      'или рядом с keqdroid.exe.';

  static Future<Directory> sessionDir() async {
    return Directory.systemTemp.createTemp('keqdis_session_');
  }

  static Future<String?> xrayExecutable() =>
      _resolveExecutable(assetXray, 'xray.exe');

  static Future<String?> singboxExecutable() =>
      _resolveExecutable(assetSingbox, 'sing-box.exe');

  static Future<String?> kphttpExecutable() =>
      _resolveExecutable(assetKphttp, 'kphttp-client.exe');

  /// Directory holding geoip.dat / geosite.dat for xray's asset lookup
  /// (passed to xray via XRAY_LOCATION_ASSET so `geoip:`/`geosite:` rules
  /// resolve regardless of the process working directory). Null if not found.
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
      'windows',
    );
    final hasGeo = geoFileNames.any((f) => File(p.join(dir, f)).existsSync());
    return hasGeo ? dir : null;
  }

  /// Extracts whatever geo files are bundled into a temp dir; returns the dir
  /// when at least one extracted, else null.
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

  static Future<String?> _resolveExecutable(String assetKey, String fileName) async {
    final fromFlutterBundle = _pathBesideFlutterAssets(fileName);
    if (fromFlutterBundle != null) return fromFlutterBundle;

    final besideExe = p.join(p.dirname(Platform.resolvedExecutable), fileName);
    if (File(besideExe).existsSync()) return besideExe;

    final fromAsset = await _extractAssetToTemp(assetKey, fileName);
    if (fromAsset != null) return fromAsset;

    return _which(fileName);
  }

  /// `build/windows/x64/runner/Debug/data/flutter_assets/...` при `flutter run`.
  static String? _pathBesideFlutterAssets(String fileName) {
    final path = p.join(
      p.dirname(Platform.resolvedExecutable),
      'data',
      'flutter_assets',
      'assets',
      'bin',
      'windows',
      fileName,
    );
    return File(path).existsSync() ? path : null;
  }

  static Future<String?> _extractAssetToTemp(
    String assetKey,
    String fileName,
  ) async {
    try {
      final data = await rootBundle.load(assetKey.replaceAll('\\', '/'));
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

  static String? _which(String name) {
    final pathEnv = Platform.environment['PATH'];
    if (pathEnv == null) return null;
    for (final dir in pathEnv.split(';')) {
      final candidate = p.join(dir.trim(), name);
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }
}
