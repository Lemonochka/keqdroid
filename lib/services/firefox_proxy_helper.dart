import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/app_logger.dart';

/// Firefox по умолчанию не переключается на системный прокси автоматически при
/// его смене, поэтому мы лишь ВКЛЮЧАЕМ ему режим «использовать системный прокси»
/// (`network.proxy.type = 5`) через user.js. Дальше Firefox едет по тому же
/// системному `127.0.0.1:httpPort`, что и Chrome/Edge, и сам отпускает его при
/// отключении VPN. Никакой ручной адрес/порт не прописываем.
class FirefoxProxyHelper {
  FirefoxProxyHelper._();

  static const _markerStart = '// keqdis-proxy-start';
  static const _markerEnd = '// keqdis-proxy-end';

  /// Включает в каждом профиле режим «использовать системный прокси».
  /// Returns profile directories that were updated.
  static Future<List<String>> applySystemProxyPref() async {
    final profiles = await _discoverProfileDirs();
    if (profiles.isEmpty) {
      AppLogger.instance.debug('Firefox: no profiles found under APPDATA');
      return [];
    }

    final block = _buildBlock();
    final updated = <String>[];

    for (final dir in profiles) {
      try {
        final userJs = File(p.join(dir.path, 'user.js'));
        var content = userJs.existsSync() ? await userJs.readAsString() : '';
        content = _stripBlock(content);
        if (content.isNotEmpty && !content.endsWith('\n')) {
          content = '$content\n';
        }
        await userJs.writeAsString('$content$block\n');
        updated.add(dir.path);
      } catch (e, st) {
        AppLogger.instance.warn(
          'Firefox: failed to update user.js in ${dir.path}',
          error: e,
          stackTrace: st,
        );
      }
    }

    if (updated.isNotEmpty) {
      AppLogger.instance.info(
        'Firefox: enabled "use system proxy" (network.proxy.type=5) in '
        '${updated.length} profile(s). Restart Firefox completely.',
      );
    }
    return updated;
  }

  static Future<List<String>> clearProxyPref() async {
    final profiles = await _discoverProfileDirs();
    final cleared = <String>[];

    for (final dir in profiles) {
      try {
        final userJs = File(p.join(dir.path, 'user.js'));
        if (!userJs.existsSync()) continue;
        final content = _stripBlock(await userJs.readAsString());
        if (content.trim().isEmpty) {
          await userJs.delete();
        } else {
          await userJs.writeAsString('${content.trim()}\n');
        }
        cleared.add(dir.path);
      } catch (e, st) {
        AppLogger.instance.warn(
          'Firefox: failed to clear user.js in ${dir.path}',
          error: e,
          stackTrace: st,
        );
      }
    }
    return cleared;
  }

  // network.proxy.type = 5 → «использовать системный прокси». Firefox сам
  // подхватывает системный HTTP-прокси Windows (тот же, что читает Chrome) и
  // освобождает его при отключении VPN — ручной адрес/порт не пишем.
  static String _buildBlock() => '''
$_markerStart — KeqDroid; restart Firefox after connect/disconnect
user_pref("network.proxy.type", 5);
$_markerEnd''';

  static String _stripBlock(String content) {
    final start = content.indexOf(_markerStart);
    if (start < 0) return content;
    final end = content.indexOf(_markerEnd, start);
    if (end < 0) {
      return content.substring(0, start).trimRight();
    }
    final after = end + _markerEnd.length;
    return '${content.substring(0, start)}${content.substring(after)}'.trim();
  }

  /// Firefox profile root per OS: `%APPDATA%\Mozilla\Firefox` on Windows,
  /// `~/.mozilla/firefox` on Linux. Other platforms are unsupported.
  static Directory? _firefoxBaseDir() {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData == null || appData.isEmpty) return null;
      return Directory(p.join(appData, 'Mozilla', 'Firefox'));
    }
    if (Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home == null || home.isEmpty) return null;
      return Directory(p.join(home, '.mozilla', 'firefox'));
    }
    return null;
  }

  static Future<List<Directory>> _discoverProfileDirs() async {
    final base = _firefoxBaseDir();
    if (base == null) return [];

    final iniFile = File(p.join(base.path, 'profiles.ini'));
    if (!iniFile.existsSync()) return [];

    final lines = await iniFile.readAsLines();
    final profiles = <Directory>[];

    String? path;
    var isRelative = true;

    void flush() {
      if (path == null || path!.isEmpty) return;
      // profiles.ini stores relative paths with `/`; join in OS separators.
      final fullPath = isRelative
          ? p.join(base.path, p.joinAll(path!.split('/')))
          : p.normalize(path!);
      final dir = Directory(fullPath);
      if (dir.existsSync()) profiles.add(dir);
      path = null;
      isRelative = true;
    }

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('Path=')) {
        path = trimmed.substring(5).trim();
      } else if (trimmed.startsWith('IsRelative=')) {
        isRelative = trimmed.substring(11).trim() != '0';
      } else if (trimmed.isEmpty) {
        flush();
      }
    }
    flush();
    return profiles;
  }
}
