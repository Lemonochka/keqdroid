import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import '../core/app_logger.dart';
import 'linux_appimage_updater.dart';

// на Wayland иконку окна среда берёт только из ярлыка: GNOME и панель Plasma ищут его по StartupWMClass,
// а KWin (Alt+Tab, обзор окон) только по имени app_id, для него скрытый двойник
class LinuxDesktopEntry {
  LinuxDesktopEntry._();

  static const _fileName = 'keqdroid.desktop';
  static const windowEntryFileName = 'com.keqdroid.keqdroid.desktop';
  static const _iconNames = ['keqdroid', 'com.keqdroid.keqdroid'];

  static const marker = 'X-KeqDroid-AppImage=true';

  // кнопки «Добавить в keqdroid» на страницах подписок, тот же список схем в tool/package_linux.sh
  static const mimeTypes = 'x-scheme-handler/keqdroid;x-scheme-handler/keqdis;';

  @visibleForTesting
  static Future<void> Function(String appsDir) refreshMimeCache =
      _updateDesktopDatabase;

  static Future<void> sync() async {
    try {
      final home = Platform.environment['HOME'];
      if (home == null) return;
      final dataHome =
          Platform.environment['XDG_DATA_HOME'] ??
          p.join(home, '.local', 'share');
      final apps = Directory(p.join(dataHome, 'applications'));
      final appImage = LinuxAppImageUpdater.currentAppImagePath();
      syncWindowEntry(apps.path, appImage);

      final entry = File(p.join(apps.path, _fileName));
      final existing = entry.existsSync() ? entry.readAsStringSync() : null;
      if (existing != null && !existing.contains(marker)) return;

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
      await _writeIcons(dataHome);
      if (content == existing) return;

      apps.createSync(recursive: true);
      entry.writeAsStringSync(content);
      await refreshMimeCache(apps.path);
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
      'Exec=${execArgument(appImage)} %u',
      'TryExec=${appImage.replaceAll(r'\', r'\\')}',
      'MimeType=$mimeTypes',
      'Icon=keqdroid',
      'Categories=Network;',
      'Terminal=false',
      'StartupWMClass=com.keqdroid.keqdroid',
      if (hidden) 'NoDisplay=true',
      marker,
      '',
    ].join('\n');
  }

  @visibleForTesting
  static void syncWindowEntry(String appsDir, String? appImage) {
    final file = File(p.join(appsDir, windowEntryFileName));
    final existing = file.existsSync() ? file.readAsStringSync() : null;
    if (existing != null && !existing.contains(marker)) return;
    if (appImage == null) {
      if (existing != null) file.deleteSync();
      return;
    }
    final content = windowEntryFor(appImage);
    if (content == existing) return;
    Directory(appsDir).createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  // без StartupWMClass: с этой строкой панель Plasma и GNOME привязали бы окно к двойнику, а не к закреплённому ярлыку
  @visibleForTesting
  static String windowEntryFor(String appImage) => [
    '[Desktop Entry]',
    'Type=Application',
    'Name=KeqDroid',
    'Exec=${execArgument(appImage)} %u',
    'TryExec=${appImage.replaceAll(r'\', r'\\')}',
    'Icon=keqdroid',
    'NoDisplay=true',
    marker,
    '',
  ].join('\n');

  // GIO читает MimeType из ярлыков сам, а xdg-mime вне GNOME и KDE ищет схему в mimeinfo.cache (defapp_generic в xdg-utils 1.1.3)
  static Future<void> _updateDesktopDatabase(String appsDir) async {
    try {
      await Process.run('update-desktop-database', [appsDir]);
    } on ProcessException {
      // нет desktop-file-utils: ссылки откроются там, где среда читает ярлыки сама
    }
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
    writeIcons(
      dataHome,
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }

  // AppImage обновляется на месте и ярлык не меняется: без сверки у прежних установок осталась бы старая иконка
  @visibleForTesting
  static void writeIcons(String dataHome, Uint8List png) {
    final dir = Directory(
      p.join(dataHome, 'icons', 'hicolor', '256x256', 'apps'),
    )..createSync(recursive: true);
    for (final name in _iconNames) {
      final file = File(p.join(dir.path, '$name.png'));
      if (file.existsSync() && listEquals(file.readAsBytesSync(), png)) {
        continue;
      }
      file.writeAsBytesSync(png);
    }
  }
}
