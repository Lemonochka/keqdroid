import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'crashlytics_reporter.dart';
import 'crashlytics_reporter_stub.dart'
    if (dart.library.io) 'crashlytics_reporter_io.dart' as crashlytics;

class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();

  final CrashlyticsReporter _crashlytics =
      crashlytics.createCrashlyticsReporter();

  bool _crashlyticsEnabled = false;

  void setCrashlyticsEnabled(bool enabled) {
    _crashlyticsEnabled = enabled;
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
      // в URI серверов, токены подписок). Локальный лог выше остаётся полным.
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
