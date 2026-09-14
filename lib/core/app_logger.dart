import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'crashlytics_reporter.dart';
import 'crashlytics_reporter_stub.dart'
    if (dart.library.io) 'crashlytics_reporter_io.dart' as crashlytics;

class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();

  final CrashlyticsReporter _crashlytics =
      crashlytics.createCrashlyticsReporter();

  bool _crashlyticsEnabled = false;

  /// Половина мегабайта на два файла: столько человек ещё пришлёт письмом, а
  /// причина обычно в последних строках.
  static const _maxLogBytes = 256 * 1024;

  File? _logFile;

  void setCrashlyticsEnabled(bool enabled) {
    _crashlyticsEnabled = enabled;
  }

  /// Дублировать лог в файл рядом с настройками (только десктоп).
  ///
  /// Crashlytics живёт лишь под Android, а developer.log в релизной сборке не
  /// видно нигде: упавший до runApp старт не оставлял ни строчки ни на экране,
  /// ни на диске, и разбирать поломку у человека было нечем.
  Future<void> enableFileLog() async {
    if (!Platform.isWindows && !Platform.isLinux) return;
    try {
      enableFileLogIn(await getApplicationSupportDirectory());
    } catch (_) {
      // Каталог недоступен — логгер молчит, но старт не трогает.
    }
  }

  /// Каталог параметром, а не через path_provider: в тестах он не отвечает.
  @visibleForTesting
  void enableFileLogIn(Directory dir) {
    final file = File('${dir.path}${Platform.pathSeparator}app.log');
    try {
      // Ротация одна, на старте: внутри сессии лог растёт редко, а проверять
      // длину на каждой строке значило бы лишний stat на каждый лог.
      if (file.existsSync() && file.lengthSync() > _maxLogBytes) {
        final previous = File('${file.path}.1');
        if (previous.existsSync()) previous.deleteSync();
        file.renameSync(previous.path);
      }
    } catch (_) {
      // Ротация не вышла — пишем дальше в тот же файл.
    }
    _logFile = file;
  }

  void debug(String message, {Object? error, StackTrace? stackTrace}) {
    _log('DEBUG', message, error: error, stackTrace: stackTrace);
  }

  void info(String message, {Object? error, StackTrace? stackTrace}) {
    _log('INFO', message, error: error, stackTrace: stackTrace);
  }

  void warn(String message, {Object? error, StackTrace? stackTrace}) {
    _log('WARN', message, error: error, stackTrace: stackTrace);
  }

  void error(String message, {Object? error, StackTrace? stackTrace}) {
    _log('ERROR', message, error: error, stackTrace: stackTrace);
  }

  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    String reason = 'Unhandled error',
    bool fatal = false,
  }) async {
    _log('ERROR', reason, error: error, stackTrace: stackTrace);
    if (_crashlyticsEnabled) {
      // Крашрепорт уходит на внешний сервис — маскируем секреты (uuid/пароли
      // в URI серверов, токены подписок). Полным остаётся только developer.log,
      // который никуда не уезжает.
      final rawText = error.toString();
      final redactedText = redactSensitive(rawText);
      final Object sanitized =
          redactedText == rawText ? error : _RedactedError(redactedText);
      await _crashlytics.recordError(
        sanitized,
        stackTrace,
        reason: redactSensitive(reason),
        fatal: fatal,
      );
    }
  }

  /// Маскирует чувствительные фрагменты в строке перед отправкой наружу:
  /// userinfo в URI (uuid/пароль до @), значения секретных query-параметров,
  /// UUID и длинные токены в path-сегментах URL (секрет подписки).
  static String redactSensitive(String input) {
    var s = input;
    // scheme://userinfo@host — userinfo это uuid/пароль/base64(method:pass)
    s = s.replaceAllMapped(
      RegExp(r'([a-zA-Z][a-zA-Z0-9+.-]*://)[^/@\s]+@'),
      (m) => '${m.group(1)}***@',
    );
    // секретные query-параметры
    s = s.replaceAllMapped(
      RegExp(
        r'''([?&](?:token|key|secret|password|pass|auth|hwid|device_id|deviceid)=)[^&\s"']+''',
        caseSensitive: false,
      ),
      (m) => '${m.group(1)}***',
    );
    // UUID где угодно (id серверов vless/vmess)
    s = s.replaceAll(
      RegExp(
        r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
        r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b',
      ),
      '***',
    );
    // длинный токен последним path-сегментом URL (типичный секрет подписки)
    s = s.replaceAllMapped(
      RegExp(r'''(https?://[^\s"']*/)([A-Za-z0-9_-]{16,})(?![\w-])'''),
      (m) => '${m.group(1)}***',
    );
    return s;
  }

  void _log(
    String level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final text = '[$level] $message';
    developer.log(
      text,
      name: 'keqdroid',
      error: error,
      stackTrace: stackTrace,
    );
    if (kDebugMode && error != null) {
      debugPrint('$text | error: $error');
    }
    _appendToFile(text, error, stackTrace);
  }

  void _appendToFile(String text, Object? error, StackTrace? stackTrace) {
    final file = _logFile;
    if (file == null) return;
    final line = StringBuffer('${DateTime.now().toIso8601String()} $text');
    if (error != null) line.write(' | error: $error');
    if (stackTrace != null) line.write('\n$stackTrace');
    try {
      // Файл человек пересылает в поддержку — маскируем то же, что и для
      // Crashlytics. flush: строка нужна на диске до того, как процесс умрёт.
      file.writeAsStringSync(
        '${redactSensitive(line.toString())}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // Диск занят, файл заблокирован, места нет — логгер молчит и только.
    }
  }
}

/// Обёртка для Crashlytics: несёт уже замаскированный toString() исходной
/// ошибки (тип обычно входит в него, см. [AppLogger.redactSensitive]).
class _RedactedError implements Exception {
  final String message;

  const _RedactedError(this.message);

  @override
  String toString() => message;
}
