import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../core/app_logger.dart';

class MacosCorePaths {
  MacosCorePaths._();

  static const geoFileNames = ['geoip.dat', 'geosite.dat'];

  static const binariesHint =
      'Build macOS cores with `bash tool/build_macos_cores.sh` and rebuild '
      'the app, or place xray and mihomo in Contents/Resources/bin/ or \$PATH.';

  @visibleForTesting
  static String? cacheRootOverride;

  @visibleForTesting
  static String? executableOverride;

  static final _staging = <String, Future<String>>{};
  static int _tmpCounter = 0;

  static Future<Directory> sessionDir() =>
      Directory.systemTemp.createTemp('keqdis_session_');

  static Future<String?> xrayExecutable() => _resolveExecutable('xray');

  static Future<String?> mihomoExecutable() => _resolveExecutable('mihomo');

  static String _cacheRoot() {
    final override = cacheRootOverride;
    if (override != null) return override;
    final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    return p.join(home, 'Library', 'Caches');
  }

  static Future<String> _coresCacheDir() async {
    final dir = Directory(p.join(_cacheRoot(), 'keqdroid', 'cores'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  static Future<String> mihomoHomeDir() async {
    final dir = Directory(p.join(_cacheRoot(), 'keqdroid', 'mihomo'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final geoDir = await geoAssetDir();
    if (geoDir != null && geoDir != dir.path) {
      for (final name in geoFileNames) {
        final src = File(p.join(geoDir, name));
        if (!src.existsSync()) continue;
        final dst = File(p.join(dir.path, name));
        if (await _sameContents(src, dst)) continue;
        try {
          await replaceAtomically(dst.path, (tmp) => src.copy(tmp));
        } catch (e) {
          AppLogger.instance.warn('Geo file not copied: $name', error: e);
        }
      }
    }
    return dir.path;
  }

  static String _bundleBinDir() {
    final exeDir = p.dirname(executableOverride ?? Platform.resolvedExecutable);
    return p.normalize(p.join(exeDir, '..', 'Resources', 'bin'));
  }

  static Future<String?> geoAssetDir() async {
    final bundleBin = _bundleBinDir();
    if (geoFileNames.any((f) => File(p.join(bundleBin, f)).existsSync())) {
      return bundleBin;
    }

    final exeDir = p.dirname(executableOverride ?? Platform.resolvedExecutable);
    if (geoFileNames.any((f) => File(p.join(exeDir, f)).existsSync())) {
      return exeDir;
    }

    final cachedGeo = p.join(_cacheRoot(), 'keqdroid', 'geo');
    if (geoFileNames.any((f) => File(p.join(cachedGeo, f)).existsSync())) {
      return cachedGeo;
    }

    return null;
  }

  static Future<String?> _resolveExecutable(String fileName) async {
    // App bundle (Contents/Resources/bin/) may be read-only (e.g. DMG mount or /Applications);
    // stage into user cache so chmod +x always succeeds.
    final inBundle = p.join(_bundleBinDir(), fileName);
    if (File(inBundle).existsSync()) {
      return stageExecutable(inBundle, fileName);
    }

    final besideExe = p.join(
      p.dirname(executableOverride ?? Platform.resolvedExecutable),
      fileName,
    );
    if (File(besideExe).existsSync()) {
      return stageExecutable(besideExe, fileName);
    }

    return _which(fileName);
  }

  @visibleForTesting
  static Future<String> stageExecutable(String src, String fileName) =>
      _staging[fileName] ??= _stage(src, fileName).whenComplete(() {
        _staging.remove(fileName);
      });

  static Future<bool> _sameContents(File a, File b) async {
    if (!await b.exists() || await a.length() != await b.length()) return false;
    final hashes = await Future.wait([
      sha256.bind(a.openRead()).first,
      sha256.bind(b.openRead()).first,
    ]);
    return hashes[0] == hashes[1];
  }

  static Future<String> _stage(String src, String fileName) async {
    try {
      final dstPath = p.join(await _coresCacheDir(), fileName);
      final dst = File(dstPath);
      final srcFile = File(src);
      if (!await _sameContents(srcFile, dst)) {
        await replaceAtomically(dstPath, (tmp) => srcFile.copy(tmp));
      }
      await _ensureExecutable(dstPath);
      return dstPath;
    } catch (_) {
      await _ensureExecutable(src);
      return src;
    }
  }

  @visibleForTesting
  static Future<void> replaceAtomically(
    String path,
    Future<void> Function(String tmpPath) write,
  ) async {
    final tmp = '$path.tmp-$pid-${_tmpCounter++}';
    try {
      await write(tmp);
      await File(tmp).rename(path);
    } catch (_) {
      try {
        File(tmp).deleteSync();
      } catch (_) {}
      rethrow;
    }
  }

  static Future<void> _ensureExecutable(String path) async {
    try {
      final stat = await FileStat.stat(path);
      if (stat.mode & 0x40 != 0) return;
      await Process.run('/bin/chmod', ['+x', path]);
    } catch (e) {
      AppLogger.instance.warn('Core binary not made executable', error: e);
    }
  }

  static String? _which(String name) {
    final dirs = <String>[
      ...(Platform.environment['PATH'] ?? '').split(':'),
      '/opt/homebrew/bin',
      '/usr/local/bin',
    ];
    for (final dir in dirs) {
      final trimmed = dir.trim();
      if (trimmed.isEmpty) continue;
      final candidate = p.join(trimmed, name);
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }
}
