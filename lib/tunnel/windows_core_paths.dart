import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// пути к xray.exe и sing-box.exe на windows
class WindowsCorePaths {
  WindowsCorePaths._();

  static const assetXray = 'assets/bin/windows/xray.exe';
  static const assetSingbox = 'assets/bin/windows/sing-box.exe';

  static const binariesHint =
      'Положите xray.exe и sing-box.exe в assets/bin/windows/ '
      '(см. README) и пересоберите приложение, '
      'или рядом с keqdroid.exe.';

  static Future<Directory> sessionDir() async {
    return Directory.systemTemp.createTemp('keqdis_session_');
  }

  static Future<String?> xrayExecutable() =>
      _resolveExecutable(assetXray, 'xray.exe');

  static Future<String?> singboxExecutable() =>
      _resolveExecutable(assetSingbox, 'sing-box.exe');

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
