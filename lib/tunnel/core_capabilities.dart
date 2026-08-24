import 'dart:io';

import '../utils/go_build_info.dart';

/// Что умеет конкретный бинарь ядра — по его собственному блоку build info.
///
/// Нужно одному вопросу: собрано ли ядро с `-tags with_gvisor`. Без тега
/// `stack: gvisor` и `stack: mixed` не просто игнорируются, а роняют СТАРТ
/// («gVisor is not included in this build»), то есть TUN не поднимается вовсе.
/// Читаем сам файл, а не спрашиваем ядро: своей команды `version` у keqrnel
/// нет, а запуск ради одной строки — лишний процесс на каждый коннект.
class CoreCapabilities {
  CoreCapabilities._();

  /// Кэш по пути к бинарю: разбор — это поиск метки в файле на десятки
  /// мегабайт, а файл в пределах запуска не меняется.
  static final _cache = <String, bool?>{};

  /// Только для тестов.
  static void resetCacheForTests() => _cache.clear();

  /// `true` — в ядре есть gVisor, `false` — точно нет, `null` — выяснить не
  /// удалось (не Go-бинарь, старый формат, файла нет). Null НЕ означает «нет»:
  /// по нему ничего переписывать нельзя.
  static Future<bool?> hasGvisor(String? binaryPath) async {
    final path = binaryPath;
    if (path == null || path.isEmpty) return null;
    if (_cache.containsKey(path)) return _cache[path];
    final result = await _probe(path);
    _cache[path] = result;
    return result;
  }

  static Future<bool?> _probe(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      final info = await GoBuildInfo.fromFile(file);
      if (info == null || !info.hasBuildSettings) return null;
      return info.buildTags.contains('with_gvisor');
    } catch (_) {
      return null;
    }
  }
}
