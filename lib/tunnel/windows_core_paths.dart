import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../core/app_logger.dart';

class WindowsCorePaths {
  WindowsCorePaths._();

  static const assetXray = 'assets/bin/windows/xray.exe';
  static const assetMihomo = 'assets/bin/windows/mihomo.exe';
  static const assetGeoip = 'assets/bin/windows/geoip.dat';
  static const assetGeosite = 'assets/bin/windows/geosite.dat';
  static const geoFileNames = ['geoip.dat', 'geosite.dat'];

  static const binariesHint =
      'Положите xray.exe, mihomo.exe и '
      'wintun.dll (нужен для TUN) в assets/bin/windows/ (см. README) и '
      'пересоберите приложение, или рядом с keqdroid.exe.';

  static Future<Directory> sessionDir() async {
    _sweepLegacyTempDirs();
    return Directory.systemTemp.createTemp('keqdis_session_');
  }

  // не %TEMP%: Defender строже к exe оттуда, а папки там копились
  static String _stableExtractRoot() {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final base = (localAppData != null && localAppData.isNotEmpty)
        ? localAppData
        : Directory.systemTemp.path;
    return p.join(base, 'keqdroid');
  }

  static bool _legacySweepStarted = false;

  static void _sweepLegacyTempDirs() {
    if (_legacySweepStarted) return;
    _legacySweepStarted = true;
    Future(() async {
      try {
        await for (final e in Directory.systemTemp.list(followLinks: false)) {
          if (e is! Directory) continue;
          final name = p.basename(e.path);
          if (!name.startsWith('keqdis_bin_') &&
              !name.startsWith('keqdis_geo_')) {
            continue;
          }
          try {
            await e.delete(recursive: true);
          } catch (_) {}
        }
      } catch (_) {}
    });
  }

  static Future<String?> xrayExecutable() =>
      _resolveExecutable(assetXray, 'xray.exe');

  static Future<String?> mihomoExecutable() =>
      _resolveExecutable(assetMihomo, 'mihomo.exe');

  // отдельный дом: ядро создаёт в нём config.yaml и на недоступном для записи каталоге не стартует
  static Future<String> mihomoHomeDir() async {
    final dir = Directory(p.join(_stableExtractRoot(), 'mihomo'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final geoDir = await geoAssetDir();
    if (geoDir != null && geoDir != dir.path) {
      for (final name in geoFileNames) {
        final src = File(p.join(geoDir, name));
        if (!src.existsSync()) continue;
        final dst = File(p.join(dir.path, name));
        if (dst.existsSync() && dst.lengthSync() == src.lengthSync()) continue;
        try {
          await src.copy(dst.path);
        } catch (e) {
          AppLogger.instance.warn('Geo file not copied: $name', error: e);
        }
      }
    }
    return dir.path;
  }

  static Future<String?> geoAssetDir() async {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    if (_dirHasGeoFiles(exeDir)) return exeDir;

    final besideAssets = _geoDirBesideFlutterAssets();
    if (besideAssets != null) return besideAssets;

    return _extractGeoFiles();
  }

  static bool _dirHasGeoFiles(String dir) {
    return geoFileNames.every((f) => File(p.join(dir, f)).existsSync());
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
    return _dirHasGeoFiles(dir) ? dir : null;
  }

  static Future<String?> _extractGeoFiles() async {
    try {
      final outDir = Directory(p.join(_stableExtractRoot(), 'geo'));
      if (!outDir.existsSync()) outDir.createSync(recursive: true);

      var extracted = false;
      for (final entry in {
        assetGeoip: 'geoip.dat',
        assetGeosite: 'geosite.dat',
      }.entries) {
        try {
          final data = await rootBundle.load(entry.key);
          final bytes = data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
          final outFile = File(p.join(outDir.path, entry.value));
          if (!outFile.existsSync() || outFile.lengthSync() != bytes.length) {
            await outFile.writeAsBytes(bytes, flush: true);
          }
          extracted = true;
        } catch (e) {
          AppLogger.instance.warn(
            'Geo file not extracted: ${entry.value}',
            error: e,
          );
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
    if (fromFlutterBundle != null) return fromFlutterBundle;

    final besideExe = p.join(p.dirname(Platform.resolvedExecutable), fileName);
    if (File(besideExe).existsSync()) return besideExe;

    final fromAsset = await _extractAssetToStableDir(assetKey, fileName);
    if (fromAsset != null) return fromAsset;

    return _which(fileName);
  }

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

  static Future<String?> _extractAssetToStableDir(
    String assetKey,
    String fileName,
  ) async {
    try {
      final data = await rootBundle.load(assetKey.replaceAll('\\', '/'));
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final outDir = Directory(p.join(_stableExtractRoot(), 'cores'));
      if (!outDir.existsSync()) outDir.createSync(recursive: true);
      final outFile = File(p.join(outDir.path, fileName));
      if (outFile.existsSync() && outFile.lengthSync() == bytes.length) {
        return outFile.path;
      }
      try {
        await outFile.writeAsBytes(bytes, flush: true);
      } on FileSystemException {
        if (outFile.existsSync()) return outFile.path;
        rethrow;
      }
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
