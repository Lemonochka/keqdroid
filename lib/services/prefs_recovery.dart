import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/app_logger.dart';

/// Чинит файл настроек до того, как его впервые прочитает SharedPreferences.
///
/// На Windows и Linux плагин держит всё в одном JSON и пишет его без атомарной
/// замены: обрезает файл и пишет поверх. Перезагрузка посреди записи оставляет
/// файл прежней длины, но из нулей — метаданные NTFS записать успевает, данные
/// нет. На таком файле getInstance() кидает исключение, причём до runApp: кадра
/// не будет, а окно на Windows показывается только по первому кадру. Итог для
/// пользователя — живой процесс без окна и без трея, снимать через диспетчер
/// задач. Так у человека и пропало приложение после принудительного обновления.
class PrefsRecovery {
  PrefsRecovery._();

  static const _fileName = 'shared_preferences.json';
  static const _backupName = 'shared_preferences.backup.json';
  static const _corruptName = 'shared_preferences.corrupt.json';

  /// Зовётся из main() перед первым [StorageService.init].
  static Future<void> prepare() async {
    // У Android, iOS и macOS настройки хранит система, ломаться этим способом
    // там нечему.
    if (!Platform.isWindows && !Platform.isLinux) return;
    try {
      repairIn(await getApplicationSupportDirectory());
    } catch (e, st) {
      // Починка не имеет права сама стать причиной не запуститься.
      AppLogger.instance
          .warn('Prefs recovery skipped', error: e, stackTrace: st);
    }
  }

  /// Каталог параметром, а не через path_provider: в тестах он не отвечает.
  @visibleForTesting
  static void repairIn(Directory dir) {
    final sep = Platform.pathSeparator;
    final prefs = File('${dir.path}$sep$_fileName');
    final backup = File('${dir.path}$sep$_backupName');

    // Файла нет — первый запуск или сознательный сброс руками. Поднимать в этом
    // случае бэкап значило бы возвращать человеку то, что он только что снёс.
    if (!prefs.existsSync()) return;

    if (_isUsable(prefs)) {
      prefs.copySync(backup.path);
      return;
    }

    AppLogger.instance.error('Prefs file is unreadable, recovering');
    if (prefs.lengthSync() > 0) {
      // Уцелевшая голова файла может ещё хранить серверы и подписки — отдать
      // её на разбор дешевле, чем объяснять человеку, что всё потеряно.
      prefs.copySync('${dir.path}$sep$_corruptName');
    }
    prefs.deleteSync();
    if (_isUsable(backup)) {
      backup.copySync(prefs.path);
      AppLogger.instance.info('Prefs restored from backup');
    }
  }

  /// Читается ли файл так, как его читает плагин: строка и `json.decode` в Map.
  /// Пустой файл плагин переживает (пропускает decode), но это тот же обрыв
  /// записи — с целым бэкапом поднять настройки лучше, чем стартовать пустым.
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
