import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/app_logger.dart';

/// Только очистка. Раньше приложение на каждом подключении принудительно
/// включало Firefox режим «использовать системный прокси»
/// (`network.proxy.type = 5`) через user.js — это затирало вручную выставленный
/// пользователем прокси. Поведение убрано. Остался лишь [clearProxyPref],
/// который снимает НАШ старый блок (по маркерам) из user.js и никогда не трогает
/// файл, если нашего блока в нём нет.
class FirefoxProxyHelper {
  FirefoxProxyHelper._();

  static const _markerStart = '// keqdis-proxy-start';
  static const _markerEnd = '// keqdis-proxy-end';

  static Future<List<String>> clearProxyPref() async {
    final profiles = await _discoverProfileDirs();
    final cleared = <String>[];

    for (final dir in profiles) {
      try {
        final userJs = File(p.join(dir.path, 'user.js'));
        if (!userJs.existsSync()) continue;
        final original = await userJs.readAsString();
        // Нет нашего блока → это чужой/ручной user.js, не прикасаемся к нему.
        if (!original.contains(_markerStart)) continue;
        final content = _stripBlock(original);
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
    try {
      final base = _firefoxBaseDir();
      if (base == null) return [];

      final iniFile = File(p.join(base.path, 'profiles.ini'));
      if (!iniFile.existsSync()) return [];

      // profiles.ini бывает НЕ в UTF-8 (Windows ANSI/cp1251, нелатинские символы
      // в путях/именах профилей). Строгий readAsLines() кидал «Failed to decode
      // data using encoding 'utf-8'», и это исключение валило ПОДКЛЮЧЕНИЕ (чистка
      // зовётся из _cleanupForRestart на connect). Файл только читаем — декодируем
      // терпимо: битый путь просто не пройдёт existsSync. Любая ошибка → пустой
      // список, чистка Firefox никогда не должна ломать коннект.
      final bytes = await iniFile.readAsBytes();
      final lines = utf8.decode(bytes, allowMalformed: true).split(RegExp(r'\r?\n'));
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
    } catch (e, st) {
      AppLogger.instance.warn(
        'Firefox: could not read profiles.ini; skipping cleanup',
        error: e,
        stackTrace: st,
      );
      return [];
    }
  }
}
