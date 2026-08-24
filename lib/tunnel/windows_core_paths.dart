import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// пути к xray.exe и sing-box.exe на windows
class WindowsCorePaths {
  WindowsCorePaths._();

  static const assetXray = 'assets/bin/windows/xray.exe';
  static const assetSingbox = 'assets/bin/windows/sing-box.exe';
  static const assetKeqrnel = 'assets/bin/windows/keqrnel.exe';
  static const assetMihomo = 'assets/bin/windows/mihomo.exe';
  static const assetGeoip = 'assets/bin/windows/geoip.dat';
  static const assetGeosite = 'assets/bin/windows/geosite.dat';
  static const geoFileNames = ['geoip.dat', 'geosite.dat'];
  static const assetWireproxy = 'assets/bin/windows/wireproxy.exe';

  static const binariesHint =
      'Положите keqrnel.exe, mihomo.exe, wireproxy.exe (для AmneziaWG) и '
      'wintun.dll (нужен для TUN) в assets/bin/windows/ (см. README) и '
      'пересоберите приложение, или рядом с keqdroid.exe.';

  static Future<Directory> sessionDir() async {
    _sweepLegacyTempDirs();
    return Directory.systemTemp.createTemp('keqdis_session_');
  }

  /// Стабильный пользовательский каталог для извлечённых из ассетов файлов.
  /// НЕ %TEMP%: Defender агрессивнее к exe, запускаемым из Temp (правило
  /// «never run from %TEMP%»), а случайные keqdis_bin_*/keqdis_geo_* папки
  /// копились там без подчистки.
  static String _stableExtractRoot() {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final base = (localAppData != null && localAppData.isNotEmpty)
        ? localAppData
        : Directory.systemTemp.path; // крайний фоллбэк
    return p.join(base, 'keqdroid');
  }

  static bool _legacySweepStarted = false;

  /// Одноразовая (на процесс) подчистка keqdis_bin_*/keqdis_geo_* из %TEMP%:
  /// старые версии создавали их через createTemp на каждое извлечение и
  /// никогда не удаляли. Новые извлечения идут в LOCALAPPDATA.
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
          } catch (_) {
            // занято (например, ядром старого экземпляра) — заберём позже
          }
        }
      } catch (_) {
        // недоступный Temp — не мешаем подключению
      }
    });
  }

  static Future<String?> xrayExecutable() =>
      _resolveExecutable(assetXray, 'xray.exe');

  static Future<String?> singboxExecutable() =>
      _resolveExecutable(assetSingbox, 'sing-box.exe');

  /// keqrnel — единое ядро (sing-box host + встроенный xray). Заменяет связку
  /// xray + sing-box, когда выбран coreEngine == keqrnel.
  static Future<String?> keqrnelExecutable() =>
      _resolveExecutable(assetKeqrnel, 'keqrnel.exe');

  /// mihomo — второе ядро: исполняет готовые конфиги Clash и ссылки, а в
  /// TUN-режиме само владеет wintun-адаптером (keqrnel ему для этого не нужен).
  static Future<String?> mihomoExecutable() =>
      _resolveExecutable(assetMihomo, 'mihomo.exe');

  /// wireproxy-awg — userspace AmneziaWG (embeds amneziawg-go), exposes a local
  /// SOCKS5/HTTP proxy. Used for both Proxy and TUN mode (TUN: wireproxy SOCKS →
  /// sing-box). Bundled in flutter_assets like xray/sing-box and resolved from
  /// there; wintun.dll is what sing-box needs for the TUN adapter.
  static Future<String?> wireproxyExecutable() =>
      _resolveExecutable(assetWireproxy, 'wireproxy.exe');

  /// Домашний каталог mihomo (аргумент `-d`).
  ///
  /// Отдельный от каталога с geo-базами намеренно. Ядро на старте создаёт в
  /// доме `config.yaml`, если его там нет (`config.Init`), и на недоступном для
  /// записи каталоге возвращает ошибку — а `config.Init` в mihomo фатален,
  /// то есть ядро просто не стартует. Каталог рядом с exe бывает недоступен
  /// (установка в Program Files, карантин, read-only носитель), поэтому дом
  /// живёт в пользовательском каталоге, а geo-базы копируются в него один раз —
  /// сверка по размеру, как и во всех остальных извлечениях здесь.
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
        } catch (_) {
          // Занят работающим ядром или нет места — geo-правила тогда не
          // сработают, но подключение важнее; ядро скажет об этом в лог.
        }
      }
    }
    return dir.path;
  }

  /// Directory holding geoip.dat / geosite.dat for xray's asset lookup
  /// (passed to xray via XRAY_LOCATION_ASSET so `geoip:`/`geosite:` rules
  /// resolve regardless of the process working directory). Null if not found.
  static Future<String?> geoAssetDir() async {
    // Prefer the directory next to keqdroid.exe — CMake installs *.dat there on
    // Windows release builds (same folder as keqrnel.exe / wintun.dll).
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

  /// Extracts whatever geo files are bundled into a stable user dir; returns
  /// the dir when at least one is available there, else null.
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
          final bytes = data.buffer
              .asUint8List(data.offsetInBytes, data.lengthInBytes);
          final outFile = File(p.join(outDir.path, entry.value));
          // размер совпадает — уже извлечено этой же сборкой, не перезаписываем
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

  static Future<String?> _resolveExecutable(String assetKey, String fileName) async {
    final fromFlutterBundle = _pathBesideFlutterAssets(fileName);
    if (fromFlutterBundle != null) return fromFlutterBundle;

    final besideExe = p.join(p.dirname(Platform.resolvedExecutable), fileName);
    if (File(besideExe).existsSync()) return besideExe;

    final fromAsset = await _extractAssetToStableDir(assetKey, fileName);
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

  static Future<String?> _extractAssetToStableDir(
    String assetKey,
    String fileName,
  ) async {
    try {
      final data = await rootBundle.load(assetKey.replaceAll('\\', '/'));
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final outDir = Directory(p.join(_stableExtractRoot(), 'cores'));
      if (!outDir.existsSync()) outDir.createSync(recursive: true);
      final outFile = File(p.join(outDir.path, fileName));
      // размер совпадает — уже извлечён этой же сборкой
      if (outFile.existsSync() && outFile.lengthSync() == bytes.length) {
        return outFile.path;
      }
      try {
        await outFile.writeAsBytes(bytes, flush: true);
      } on FileSystemException {
        // exe занят запущенным ядром — пользуемся существующей копией
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
