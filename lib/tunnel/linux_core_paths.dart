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
  static const assetKeqrnel = 'assets/bin/linux/keqrnel';
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

  /// keqrnel — единое ядро (sing-box host + встроенный xray), заменяет xray+sing-box.
  static Future<String?> keqrnelExecutable() =>
      _resolveExecutable(assetKeqrnel, 'keqrnel');

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

    return _extractGeoFiles();
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

  /// Extracts geo files into the stable cache (`~/.cache/keqdroid/geo`) —
  /// именно в стабильный каталог: createTemp на каждый вызов копит в /tmp
  /// каталоги, которые никто не удаляет.
  static Future<String?> _extractGeoFiles() async {
    try {
      final base = Platform.environment['XDG_CACHE_HOME'] ??
          p.join(
            Platform.environment['HOME'] ?? Directory.systemTemp.path,
            '.cache',
          );
      final outDir = Directory(p.join(base, 'keqdroid', 'geo'));
      if (!outDir.existsSync()) outDir.createSync(recursive: true);

      var extracted = false;
      for (final entry in {
        assetGeoip: 'geoip.dat',
        assetGeosite: 'geosite.dat',
      }.entries) {
        try {
          final data = await rootBundle.load(entry.key);
          final bytes = data.buffer
              .asUint8List(data.offsetInBytes, data.lengthInBytes);
          final outFile = File(p.join(outDir.path, entry.value));
          // размер совпадает — уже извлечено этой же сборкой
          if (!outFile.existsSync() || outFile.lengthSync() != bytes.length) {
            await outFile.writeAsBytes(bytes, flush: true);
          }
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
    // The bundled binary lives where we CANNOT make it executable: a read-only
    // AppImage FUSE mount, or a root-owned /opt (deb). Flutter assets also drop
    // the +x bit. So copy the binary into a user-writable cache dir and chmod
    // it there, then run that copy. Without this, Process.start fails with
    // "Permission denied" (which the UI mis-reported as "VPN permission").
    final fromFlutterBundle = _pathBesideFlutterAssets(fileName);
    if (fromFlutterBundle != null) {
      return _stageExecutable(fromFlutterBundle, fileName);
    }

    final besideExe = p.join(p.dirname(Platform.resolvedExecutable), fileName);
    if (File(besideExe).existsSync()) {
      return _stageExecutable(besideExe, fileName);
    }

    final fromAsset = await _extractAssetToCache(assetKey, fileName);
    if (fromAsset != null) {
      await _ensureExecutable(fromAsset);
      return fromAsset;
    }

    return _which(fileName); // system PATH copy is already executable
  }

  /// User-writable cache for runnable core binaries (`~/.cache/keqdroid/cores`).
  static Future<String> _coresCacheDir() async {
    final base = Platform.environment['XDG_CACHE_HOME'] ??
        p.join(
          Platform.environment['HOME'] ?? Directory.systemTemp.path,
          '.cache',
        );
    final dir = Directory(p.join(base, 'keqdroid', 'cores'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  /// Copies [src] into the writable cache (only when missing or a different
  /// size) and marks it executable; returns the runnable path.
  static Future<String> _stageExecutable(String src, String fileName) async {
    try {
      final dstPath = p.join(await _coresCacheDir(), fileName);
      final dst = File(dstPath);
      final srcFile = File(src);
      if (!dst.existsSync() ||
          dst.lengthSync() != srcFile.lengthSync()) {
        await srcFile.copy(dstPath);
      }
      await _ensureExecutable(dstPath);
      return dstPath;
    } catch (_) {
      // Staging failed (e.g. no HOME) — fall back to the source path and at
      // least try to chmod it; better than nothing.
      await _ensureExecutable(src);
      return src;
    }
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

  /// Extracts a bundled binary into the stable cores cache (same dir as
  /// [_stageExecutable]); createTemp-каталог на каждый вызов копил бы мусор.
  static Future<String?> _extractAssetToCache(
    String assetKey,
    String fileName,
  ) async {
    try {
      final data = await rootBundle.load(assetKey);
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final outFile = File(p.join(await _coresCacheDir(), fileName));
      // размер совпадает — уже извлечён этой же сборкой
      if (outFile.existsSync() && outFile.lengthSync() == bytes.length) {
        return outFile.path;
      }
      try {
        await outFile.writeAsBytes(bytes, flush: true);
      } on FileSystemException {
        // бинарь занят запущенным ядром — пользуемся существующей копией
        if (outFile.existsSync()) return outFile.path;
        rethrow;
      }
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
