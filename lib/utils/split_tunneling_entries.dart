/// Тождество записи в списках раздельного туннелирования.
///
/// Экран сводит вместе три источника, и в каждом имя приходит в своём виде:
/// список процессов Windows отдаёт `Discord.exe` с настоящим регистром,
/// добавленное руками приезжает путём (`C:\...\Discord.exe`), а в сохранённых
/// списках у давних пользователей лежит `discord.exe` — так писала старая
/// версия. Для правил sing-box это одно и то же приложение
/// (`processNameMatchVariants` шлёт оба варианта регистра), поэтому и на
/// экране оно обязано быть ОДНОЙ строкой.
library;

import '../models/app_info.dart';
import 'process_name_utils.dart';

/// Ключ, по которому записи считаются одним приложением.
///
/// Регистр снимаем ПОСЛЕ нормализации: `normalizeProcessName` приводит путь к
/// имени файла и дописывает `.exe`, и только после этого имена из разных
/// источников сравнимы. На Android имена пакетов проходят ту же функцию —
/// суффикс достаётся обеим сторонам сравнения, так что тождество не портится.
String splitEntryKey(String raw) => normalizeProcessName(raw).toLowerCase();

/// Схлопывает записи с одинаковым [splitEntryKey], сохраняя порядок.
///
/// Из двух одинаковых побеждает та, у которой есть путь установки: это живая
/// строка списка процессов (у неё же грузится иконка), а не заглушка,
/// собранная из сохранённого имени.
List<AppInfo> dedupeSplitEntries(List<AppInfo> apps) {
  // Map в Dart хранит порядок вставки, а замена значения существующего ключа
  // его не меняет — значит, победитель встанет на место первой встреченной
  // записи, и список не перетасуется.
  final byKey = <String, AppInfo>{};
  for (final app in apps) {
    final key = splitEntryKey(app.packageName);
    if (key.isEmpty) continue;
    final existing = byKey[key];
    if (existing == null) {
      byKey[key] = app;
      continue;
    }
    if (_isStub(existing) && !_isStub(app)) byKey[key] = app;
  }
  return byKey.values.toList();
}

bool _isStub(AppInfo app) =>
    app.installPath == null || app.installPath!.isEmpty;
