import 'dart:io';

import '../core/app_logger.dart';

/// firefox не берёт системный прокси windows сам — пишем блок в user.js каждого профиля
class FirefoxProxyHelper {
  FirefoxProxyHelper._();

  static const _markerStart = '// keqdis-proxy-start';
  static const _markerEnd = '// keqdis-proxy-end';

  /// Returns profile directories that were updated.
  static Future<List<String>> applyManualHttpProxy(int httpPort) async {
    final profiles = await _discoverProfileDirs();
    if (profiles.isEmpty) {
      AppLogger.instance.debug('Firefox: no profiles found under APPDATA');
      return [];
    }

    final block = _buildBlock(httpPort);
    final updated = <String>[];

    for (final dir in profiles) {
      try {
        final userJs = File('${dir.path}\\user.js');
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
        'Firefox: wrote HTTP proxy 127.0.0.1:$httpPort to ${updated.length} '
        'profile(s). Restart Firefox completely.',
      );
    }
    return updated;
  }

  static Future<List<String>> clearManualHttpProxy() async {
    final profiles = await _discoverProfileDirs();
    final cleared = <String>[];

    for (final dir in profiles) {
      try {
        final userJs = File('${dir.path}\\user.js');
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

  static String _buildBlock(int httpPort) => '''
$_markerStart — KeqDroid; restart Firefox after connect/disconnect
user_pref("network.proxy.type", 1);
user_pref("network.proxy.http", "127.0.0.1");
user_pref("network.proxy.http_port", $httpPort);
user_pref("network.proxy.ssl", "127.0.0.1");
user_pref("network.proxy.ssl_port", $httpPort);
user_pref("network.proxy.share_proxy_settings", true);
user_pref("network.proxy.no_proxies_on", "localhost,127.0.0.1,::1");
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

  static Future<List<Directory>> _discoverProfileDirs() async {
    if (!Platform.isWindows) return [];

    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.isEmpty) return [];

    final base = Directory('$appData\\Mozilla\\Firefox');
    final iniFile = File('${base.path}\\profiles.ini');
    if (!iniFile.existsSync()) return [];

    final lines = await iniFile.readAsLines();
    final profiles = <Directory>[];

    String? path;
    var isRelative = true;

    void flush() {
      if (path == null || path!.isEmpty) return;
      final fullPath =
          isRelative ? '${base.path}\\$path' : path!.replaceAll('/', '\\');
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
