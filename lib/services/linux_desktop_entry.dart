import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import '../core/app_logger.dart';
import 'linux_appimage_updater.dart';

// на Wayland иконку окна среда берёт только из ярлыка со StartupWMClass
class LinuxDesktopEntry {
  LinuxDesktopEntry._();

  static const _fileName = 'keqdroid.desktop';
  static const _iconNames = ['keqdroid', 'com.keqdroid.keqdroid'];

  static const marker = 'X-KeqDroid-AppImage=true';

  static Future<void> sync() async {
    try {
      final home = Platform.environment['HOME'];
      if (home == null) return;
      final dataHome =
          Platform.environment['XDG_DATA_HOME'] ?? p.join(home, '.local', 'share');
      final apps = Directory(p.join(dataHome, 'applications'));
      final entry = File(p.join(apps.path, _fileName));
      final existing = entry.existsSync() ? entry.readAsStringSync() : null;
      if (existing != null && !existing.contains(marker)) return;

      final appImage = LinuxAppImageUpdater.currentAppImagePath();
      if (appImage == null) {
        if (existing != null) entry.deleteSync();
        return;
      }

      final others = <String>[];
      if (apps.existsSync()) {
        await for (final f in apps.list()) {
          if (f is! File || !f.path.endsWith('.desktop')) continue;
          if (p.basename(f.path) == _fileName) continue;
          try {
            others.add(await f.readAsString());
          } on FileSystemException {
            // битый или чужой ярлык, не наш случай
          }
        }
      }
      final content = contentFor(
        appImage,
        hidden: integratedElsewhere(appImage, others),
      );
      if (content == existing) return;

      await _writeIcons(dataHome);
      apps.createSync(recursive: true);
      entry.writeAsStringSync(content);
    } catch (e, st) {
      AppLogger.instance.warn(
        'Could not install the AppImage desktop entry',
        error: e,
        stackTrace: st,
      );
    }
  }

  @visibleForTesting
  static bool integratedElsewhere(String appImage, Iterable<String> entries) =>
      entries.any((text) => text.contains(appImage));

  @visibleForTesting
  static String contentFor(String appImage, {required bool hidden}) {
    return [
      '[Desktop Entry]',
      'Type=Application',
      'Name=KeqDroid',
      'Comment=keqdroid proxy/VPN client',
      'Exec=${execArgument(appImage)}',
      'TryExec=${appImage.replaceAll(r'\', r'\\')}',
      'Icon=keqdroid',
      'Categories=Network;',
      'Terminal=false',
      'StartupWMClass=com.keqdroid.keqdroid',
      if (hidden) 'NoDisplay=true',
      marker,
      '',
    ].join('\n');
  }

  static String execArgument(String path) {
    final quoted = path
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll(r'$', r'\$')
        .replaceAll('`', r'\`');
    return '"${quoted.replaceAll(r'\', r'\\')}"'.replaceAll('%', '%%');
  }

  static Future<void> _writeIcons(String dataHome) async {
    final data = await rootBundle.load('assets/icon.png');
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: 256,
      targetHeight: 256,
    );
    final frame = await codec.getNextFrame();
    final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    if (png == null) return;
    final dir = Directory(
      p.join(dataHome, 'icons', 'hicolor', '256x256', 'apps'),
    )..createSync(recursive: true);
    for (final name in _iconNames) {
      File(p.join(dir.path, '$name.png'))
          .writeAsBytesSync(png.buffer.asUint8List());
    }
  }
}
