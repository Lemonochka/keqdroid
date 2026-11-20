import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/app_logger.dart';

// плагин на Windows/Linux пишет JSON без атомарной замены, и перезагрузка посреди записи оставляет файл из нулей;
// тогда getInstance() падает до runApp, и окно не появляется вовсе
class PrefsRecovery {
  PrefsRecovery._();

  static const _fileName = 'shared_preferences.json';
  static const _backupName = 'shared_preferences.backup.json';
  static const _corruptName = 'shared_preferences.corrupt.json';

  static Future<void> prepare() async {
    if (!Platform.isWindows && !Platform.isLinux) return;
    try {
      repairIn(await getApplicationSupportDirectory());
    } catch (e, st) {
      // починка сама не должна мешать запуску
      AppLogger.instance
          .warn('Prefs recovery skipped', error: e, stackTrace: st);
    }
  }

  @visibleForTesting
  static void repairIn(Directory dir) {
    final sep = Platform.pathSeparator;
    final prefs = File('${dir.path}$sep$_fileName');
    final backup = File('${dir.path}$sep$_backupName');

    // файла нет: первый запуск или сброс руками, бэкап не поднимаем
    if (!prefs.existsSync()) return;

    if (_isUsable(prefs)) {
      _refreshBackup(prefs, backup);
      return;
    }

    AppLogger.instance.error('Prefs file is unreadable, recovering');
    if (prefs.lengthSync() > 0) {
      prefs.copySync('${dir.path}$sep$_corruptName');
    }
    prefs.deleteSync();
    if (_isUsable(backup)) {
      backup.copySync(prefs.path);
      AppLogger.instance.info('Prefs restored from backup');
    }
  }

  // на Linux второй запуск доходит до Dart, и копия могла сняться посреди чужой записи
  static void _refreshBackup(File prefs, File backup) {
    final temp = File('${backup.path}.tmp');
    prefs.copySync(temp.path);
    if (_isUsable(temp)) {
      temp.renameSync(backup.path);
    } else {
      temp.deleteSync();
    }
  }

  static bool _isUsable(File file) {
    try {
      if (!file.existsSync()) return false;
      final text = file.readAsStringSync();
      return text.isNotEmpty && json.decode(text) is Map;
    } catch (_) {
      return false;
    }
  }
}
