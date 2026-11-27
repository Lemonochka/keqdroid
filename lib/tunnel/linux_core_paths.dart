import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../core/app_logger.dart';

class LinuxCorePaths {
  LinuxCorePaths._();

  static const assetXray = 'assets/bin/linux/xray';
  static const assetMihomo = 'assets/bin/linux/mihomo';
  static const assetGeoip = 'assets/bin/linux/geoip.dat';
  static const assetGeosite = 'assets/bin/linux/geosite.dat';
  static const geoFileNames = ['geoip.dat', 'geosite.dat'];

  static const binariesHint =
      'Положите xray и mihomo в assets/bin/linux/ '
      '(см. README) и пересоберите приложение, '
      'или поместите их рядом с исполняемым файлом / в \$PATH.';

  // заранее: иначе ProcessException вписывает в текст всю команду вместе с телом root-обёртки
  static String? findPkexec({
    @visibleForTesting String? pathEnvOverride,
    @visibleForTesting bool Function(String)? fileExistsOverride,
  }) {
    final exists =
        fileExistsOverride ?? (String path) => File(path).existsSync();
    // на NixOS в sw/bin лежит pkexec из polkit.bin без setuid, живая обёртка только здесь
    if (exists('/run/wrappers/bin/pkexec')) {
      return '/run/wrappers/bin/pkexec';
    }
    final onPath = _which(
      'pkexec',
      pathEnvOverride: pathEnvOverride,
      fileExistsOverride: exists,
    );
    if (onPath != null) return onPath;
    // PATH графической сессии бывает урезан, а pkexec везде лежит здесь
    for (final candidate in const [
      '/usr/bin/pkexec',
      '/usr/local/bin/pkexec',
    ]) {
      if (exists(candidate)) return candidate;
    }
    return null;
  }

  static Future<Directory> sessionDir() async {
    return Directory.systemTemp.createTemp('keqdis_session_');
  }

  static Future<String?> xrayExecutable() =>
      _resolveExecutable(assetXray, 'xray');

  static Future<String?> mihomoExecutable() =>
      _resolveExecutable(assetMihomo, 'mihomo');

  // отдельный дом: ядро создаёт в нём config.yaml, а рядом с бинарём на Linux обычно нельзя писать (/opt, монт AppImage)
  static Future<String> mihomoHomeDir() async {
    final dir = Directory(p.join(await _cacheRoot(), 'keqdroid', 'mihomo'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final geoDir = await geoAssetDir();
    if (geoDir != null && geoDir != dir.path) {
      for (final name in geoFileNames) {
        final src = File(p.join(geoDir, name));
        if (!src.existsSync()) continue;
        final dst = File(p.join(dir.path, name));
        if (dst.existsSync() && dst.lengthSync() == src.lengthSync()) continue;
        try {
          await replaceAtomically(dst.path, (tmp) => src.copy(tmp));
        } catch (e) {
          AppLogger.instance.warn('Geo file not copied: $name', error: e);
        }
      }
    }
    return dir.path;
  }

  static Future<String> _cacheRoot() async =>
      Platform.environment['XDG_CACHE_HOME'] ??
      p.join(
        Platform.environment['HOME'] ?? Directory.systemTemp.path,
        '.cache',
      );

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

  // стабильный каталог: createTemp на каждый вызов копил бы мусор в /tmp
  static Future<String?> _extractGeoFiles() async {
    try {
      final base =
          Platform.environment['XDG_CACHE_HOME'] ??
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
    // там, где лежит бинарь, +x не поставить (монт AppImage, /opt от root), поэтому копируем в кэш;
    // без этого Process.start падает с Permission denied
    final fromFlutterBundle = _pathBesideFlutterAssets(fileName);
    if (fromFlutterBundle != null) {
      return stageExecutable(fromFlutterBundle, fileName);
    }

    final besideExe = p.join(p.dirname(Platform.resolvedExecutable), fileName);
    if (File(besideExe).existsSync()) {
      return stageExecutable(besideExe, fileName);
    }

    final fromAsset = await _extractAssetToCache(assetKey, fileName);
    if (fromAsset != null) {
      await _ensureExecutable(fromAsset);
      return fromAsset;
    }

    return _which(fileName);
  }

  static Future<String> _coresCacheDir() async {
    final base =
        cacheRootOverride ??
        Platform.environment['XDG_CACHE_HOME'] ??
        p.join(
          Platform.environment['HOME'] ?? Directory.systemTemp.path,
          '.cache',
        );
    final dir = Directory(p.join(base, 'keqdroid', 'cores'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  static final _staging = <String, Future<String>>{};

  @visibleForTesting
  static String? cacheRootOverride;

  // File.copy пишет поверх с O_TRUNC, и параллельные замеры переписывали ядро, пока другие его запускали;
  // уборка в whenComplete блоком, потому что стрелка вернула бы эту же раскладку, и whenComplete ждал бы сам себя
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
      if (!dst.existsSync() || dst.lengthSync() != srcFile.lengthSync()) {
        await replaceAtomically(dstPath, (tmp) => srcFile.copy(tmp));
      }
      await _ensureExecutable(dstPath);
      return dstPath;
    } catch (_) {
      await _ensureExecutable(src);
      return src;
    }
  }

  // запущенное ядро на старом файле доработает: rename меняет только запись в каталоге
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

  static int _tmpCounter = 0;

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

  static Future<String?> _extractAssetToCache(
    String assetKey,
    String fileName,
  ) async {
    try {
      final data = await rootBundle.load(assetKey);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final outFile = File(p.join(await _coresCacheDir(), fileName));
      if (outFile.existsSync() && outFile.lengthSync() == bytes.length) {
        return outFile.path;
      }
      try {
        await replaceAtomically(
          outFile.path,
          (tmp) => File(tmp).writeAsBytes(bytes, flush: true),
        );
      } on FileSystemException {
        if (outFile.existsSync()) return outFile.path;
        rethrow;
      }
      return outFile.path;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _ensureExecutable(String path) async {
    try {
      final stat = await FileStat.stat(path);
      if (stat.mode & 0x40 != 0) return;
      await Process.run('chmod', ['+x', path]);
    } catch (e) {
      AppLogger.instance.warn('Core binary not made executable', error: e);
    }
  }

  static String? _which(
    String name, {
    String? pathEnvOverride,
    bool Function(String)? fileExistsOverride,
  }) {
    final pathEnv = pathEnvOverride ?? Platform.environment['PATH'];
    if (pathEnv == null) return null;
    final exists =
        fileExistsOverride ?? (String path) => File(path).existsSync();
    for (final dir in pathEnv.split(':')) {
      final candidate = p.posix.join(dir.trim(), name);
      if (exists(candidate)) return candidate;
    }
    return null;
  }
}
