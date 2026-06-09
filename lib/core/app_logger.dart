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
      await _crashlytics.recordError(
        error,
        stackTrace,
        reason: reason,
        fatal: fatal,
      );
    }
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
