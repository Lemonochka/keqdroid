import 'dart:convert';

/// Уровень логов xray сессии на десктопе.
///
/// Отказ дозвона до своего сервера xray 26.x пишет только на уровне info:
/// исходящий обработчик логирует свою ошибку через LogInfo, а XHTTP и вовсе
/// сообщает об отказе строкой транспорта того же уровня. По этим строкам
/// автовыбор узнаёт, что сервер отвечает отказом (см. CoreDialFailures), —
/// тишины в ответ в этом случае нет. Поэтому встроенный в keqrnel xray
/// работает не тише info, а строки ниже уровня, выбранного человеком, в лог
/// приложения не попадают: их видит только счётчик отказов. На Android то же
/// делают сервис (sessionConfigFor) и читатель вывода в forkexec.c.
abstract final class XraySessionLog {
  static const _levels = ['debug', 'info', 'warning', 'error', 'none'];

  /// Конфиг с поднятым до info уровнем и порог для [keep]; порог 0
  /// пропускает всё — так и остаётся, если человек сам выбрал info или debug.
  static ({String config, int threshold}) raise(String xrayConfig) {
    try {
      final json = jsonDecode(xrayConfig);
      if (json is! Map<String, dynamic>) {
        return (config: xrayConfig, threshold: 0);
      }
      final log = json['log'] is Map
          ? Map<String, dynamic>.from(json['log'] as Map)
          : <String, dynamic>{};
      // Без поля xray пишет с warning — так его и читаем.
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
      // Не разобрали — запускаем как есть: без счётчика отказов, но с тем
      // уровнем, что заказан.
      return (config: xrayConfig, threshold: 0);
    }
  }

  /// Пропускать ли строку вывода ядра в лог при пороге [threshold].
  static bool keep(String line, int threshold) =>
      threshold == 0 || lineLevel(line) >= threshold;

  /// Уровень строки xray по метке после времени: «2026/09/23 02:09:14.123456
  /// [Info] ...». У строки без метки — sing-box, mihomo, баннер, access-лог —
  /// уровень выше любого порога: её не режут никогда.
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
