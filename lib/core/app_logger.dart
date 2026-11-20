import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();

  static const _maxLogBytes = 256 * 1024;

  File? _logFile;

  final _pending = StringBuffer();
  Future<void>? _draining;

  Future<void> enableFileLog() async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isAndroid) return;
    try {
      enableFileLogIn(await getApplicationSupportDirectory());
    } catch (_) {}
  }

  Future<String> readFileLog({int maxChars = 512 * 1024}) async {
    final file = _logFile;
    if (file == null) return '';
    await flush();
    try {
      final previous = File('${file.path}.1');
      final text = [
        if (await previous.exists()) await previous.readAsString(),
        if (await file.exists()) await file.readAsString(),
      ].join();
      return text.length > maxChars
          ? text.substring(text.length - maxChars)
          : text;
    } catch (_) {
      return '';
    }
  }

  @visibleForTesting
  void enableFileLogIn(Directory dir) {
    final file = File('${dir.path}${Platform.pathSeparator}app.log');
    try {
      if (file.existsSync() && file.lengthSync() > _maxLogBytes) {
        final previous = File('${file.path}.1');
        if (previous.existsSync()) previous.deleteSync();
        file.renameSync(previous.path);
      }
    } catch (_) {}
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
  }) async {
    _log('ERROR', reason, error: error, stackTrace: stackTrace);
  }

  static String redactSensitive(String input) {
    var s = input;
    s = s.replaceAllMapped(
      RegExp(r'([a-zA-Z][a-zA-Z0-9+.-]*://)[^/@\s]+@'),
      (m) => '${m.group(1)}***@',
    );
    s = s.replaceAllMapped(
      RegExp(
        r'''([?&](?:token|key|secret|password|pass|auth|hwid|device_id|deviceid)=)[^&\s"']+''',
        caseSensitive: false,
      ),
      (m) => '${m.group(1)}***',
    );
    s = s.replaceAll(
      RegExp(
        r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
        r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b',
      ),
      '***',
    );
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
    developer.log(text, name: 'keqdroid', error: error, stackTrace: stackTrace);
    if (kDebugMode && error != null) {
      debugPrint('$text | error: $error');
    }
    _appendToFile(text, error, stackTrace);
  }

  void _appendToFile(String text, Object? error, StackTrace? stackTrace) {
    if (_logFile == null) return;
    final line = StringBuffer('${DateTime.now().toIso8601String()} $text');
    if (error != null) line.write(' | error: $error');
    if (stackTrace != null) line.write('\n$stackTrace');
    _pending.write('${redactSensitive(line.toString())}\n');
    _draining ??= _drain();
  }

  // синхронная строка с flush стоила потоку интерфейса на ПК с Defender 21 мс в медиане и до 460 мс, без flush
  // 7 мс (замер 18.11.2026); файл открывается на каждую запись, потому что в него же пишет фоновый изолят
  Future<void> _drain() async {
    try {
      while (_pending.isNotEmpty) {
        final file = _logFile;
        final chunk = _pending.toString();
        _pending.clear();
        if (file == null) break;
        try {
          await file.writeAsString(chunk, mode: FileMode.append);
        } catch (_) {}
      }
    } finally {
      _draining = null;
    }
  }

  // перед выходом из процесса и перед чтением журнала
  Future<void> flush() => _draining ?? Future<void>.value();
}
