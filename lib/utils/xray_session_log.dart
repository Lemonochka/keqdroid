import 'dart:convert';

// Отказ дозвона до сервера xray 26 пишет только на info, а по этим строкам автовыбор (CoreDialFailures) узнаёт об отказе.
// Поэтому встроенный xray работает на info, а строки ниже выбранного уровня видит только счётчик. На Android то же в forkexec.c
abstract final class XraySessionLog {
  static const _levels = ['debug', 'info', 'warning', 'error', 'none'];

  static ({String config, int threshold}) raise(String xrayConfig) {
    try {
      final json = jsonDecode(xrayConfig);
      if (json is! Map<String, dynamic>) {
        return (config: xrayConfig, threshold: 0);
      }
      final log = json['log'] is Map
          ? Map<String, dynamic>.from(json['log'] as Map)
          : <String, dynamic>{};
      // без поля xray пишет с warning
      final chosen = _levels.indexOf(
        (log['loglevel']?.toString() ?? 'warning').toLowerCase(),
      );
      final level = chosen < 0 ? _levels.indexOf('warning') : chosen;
      if (level <= _levels.indexOf('info')) {
        return (config: xrayConfig, threshold: 0);
      }
      json['log'] = {...log, 'loglevel': 'info'};
      return (config: jsonEncode(json), threshold: level);
    } on FormatException {
      // не разобрали: запускаем как есть, без счётчика отказов
      return (config: xrayConfig, threshold: 0);
    }
  }

  static bool keep(String line, int threshold) =>
      threshold == 0 || lineLevel(line) >= threshold;

  // строку без метки (mihomo, баннер, access-лог) не режем никогда
  static int lineLevel(String line) {
    final tag = line.indexOf('[');
    if (tag < 0) return _levels.length - 1;
    final rest = line.substring(tag);
    if (rest.startsWith('[Debug]')) return 0;
    if (rest.startsWith('[Info]')) return 1;
    if (rest.startsWith('[Warning]')) return 2;
    if (rest.startsWith('[Error]')) return 3;
    return _levels.length - 1;
  }
}
