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

  @visibleForTesting
  static bool Function(String path)? isExecutableOverride;

  static final _staging = <String, Future<String>>{};
  static final _shaCache = <String, ({int size, int mtimeUs, String sha256})>{};
  static int _tmpCounter = 0;

  static Future<Directory> sessionDir() =>
      Directory.systemTemp.createTemp('keqdis_session_');

  static String bundleBinDir() {
    final exeDir = p.dirname(executableOverride ?? Platform.resolvedExecutable);
    return p.normalize(p.join(exeDir, '..', 'Resources', 'bin'));
  }

  static String? bundledCorePath(String fileName) {
    final inBundle = p.join(bundleBinDir(), fileName);
    if (File(inBundle).existsSync()) return inBundle;

    final besideExe = p.join(
      p.dirname(executableOverride ?? Platform.resolvedExecutable),
      fileName,
    );
    if (File(besideExe).existsSync()) return besideExe;
    return null;
  }

  static String? daemonExecutable() => bundledCorePath('keqdroid-tun');

  static Future<String?> xrayExecutable() => _resolveExecutable('xray');

  static Future<String?> mihomoExecutable() => _resolveExecutable('mihomo');

  static Future<String> sha256Of(String path) async {
    try {
      final stat = await FileStat.stat(path);
      if (stat.type != FileSystemEntityType.file) return '';
      final mtimeUs = stat.modified.microsecondsSinceEpoch;
      final cached = _shaCache[path];
      if (cached != null &&
          cached.size == stat.size &&
          cached.mtimeUs == mtimeUs) {
        return cached.sha256;
      }
      final digest = (await sha256.bind(File(path).openRead()).first)
          .toString();
      _shaCache[path] = (size: stat.size, mtimeUs: mtimeUs, sha256: digest);
      return digest;
    } catch (_) {
      return '';
    }
  }

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
        if (_sameSizeAndMtime(src, dst)) continue;
        try {
          await replaceAtomically(dst.path, (tmp) async {
            await src.copy(tmp);
            await File(tmp).setLastModified(src.lastModifiedSync());
          });
        } catch (e) {
          AppLogger.instance.warn('Geo file not copied: $name', error: e);
        }
      }
    }
    return dir.path;
  }

  static bool _sameSizeAndMtime(File src, File dst) {
    final dstStat = dst.statSync();
    if (dstStat.type == FileSystemEntityType.notFound) return false;
    final srcStat = src.statSync();
    return srcStat.size == dstStat.size &&
        srcStat.modified.isAtSameMomentAs(dstStat.modified);
  }

  static Future<String?> geoAssetDir() async {
    final candidates = [
      p.join(_cacheRoot(), 'keqdroid', 'geo'),
      bundleBinDir(),
      p.dirname(executableOverride ?? Platform.resolvedExecutable),
    ];
    for (final dir in candidates) {
      if (geoFileNames.every((f) => File(p.join(dir, f)).existsSync())) {
        return dir;
      }
    }
    for (final dir in candidates) {
      if (geoFileNames.any((f) => File(p.join(dir, f)).existsSync())) {
        return dir;
      }
    }
    return null;
  }

  static bool _hasExecBit(String path) {
    final override = isExecutableOverride;
    if (override != null) return override(path);
    try {
      return FileStat.statSync(path).mode & 0x49 != 0;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> _resolveExecutable(String fileName) async {
    // в готовом .app бинарники уже 0755 и запускаются на месте без копирования в кэш
    final bundled = bundledCorePath(fileName);
    if (bundled != null) {
      return _hasExecBit(bundled)
          ? bundled
          : stageExecutable(bundled, fileName);
    }
    return _which(fileName);
  }

  @visibleForTesting
  static Future<String> stageExecutable(String src, String fileName) =>
      _staging[fileName] ??= _stage(src, fileName).whenComplete(() {
        _staging.remove(fileName);
      });

  static Future<String> _stage(String src, String fileName) async {
    try {
      final dstPath = p.join(await _coresCacheDir(), fileName);
      final dst = File(dstPath);
      final srcFile = File(src);
      if (!_sameSizeAndMtime(srcFile, dst) ||
          await sha256Of(src) != await sha256Of(dstPath)) {
        await replaceAtomically(dstPath, (tmp) async {
          await srcFile.copy(tmp);
          await File(tmp).setLastModified(srcFile.lastModifiedSync());
        });
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
    if (!Platform.isMacOS && !Platform.isLinux) return;
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
