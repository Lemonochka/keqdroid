import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/core/app_logger.dart';
import 'package:keqdroid/services/app_log_service.dart';

void main() {
  group('журнал файлом', () {
    late Directory logs;
    late Directory out;

    setUp(() async {
      logs = Directory.systemTemp.createTempSync('app_log_bundle');
      out = Directory.systemTemp.createTempSync('app_log_out');
      AppLogger.instance.enableFileLogIn(logs);
      for (var i = 0; i < 310; i++) {
        AppLogger.instance.info('record ${i.toString().padLeft(3, '0')}');
      }
      await AppLogger.instance.flush();
    });

    tearDown(() {
      for (final dir in [logs, out]) {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('файл несёт журнал целиком, от старых записей до свежих', () async {
      final file = await AppLogService.writeBundleFile(
        out,
        now: DateTime(2026, 11, 19, 19, 7),
      );

      expect(file.uri.pathSegments.last, 'keqdroid-log-2026-11-19-1907.txt');
      final text = await file.readAsString();
      expect(text, contains('record 000'));
      expect(text, contains('record 309'));
    });

    test('в буфер по-прежнему идут последние 300 записей', () async {
      final text = await AppLogService.bundle();
      expect(text, isNot(contains('record 009')));
      expect(text, contains('record 010'));
      expect(text, contains('record 309'));
    });
  });

  group('журнал приложения и нативной части', () {
    // Формат общий: так пишут и AppLogger в Dart, и NativeLog в Kotlin.
    const text =
        '2026-09-27T22:51:39.123456 [INFO] VPN connected\n'
        '2026-09-27T22:51:40.000 [ERROR] KEQDIS: startVpn failed: boom\n'
        'java.lang.IllegalStateException: boom\n'
        '\tat com.keqdroid.keqdroid.KeqdisVpnService.startXray(Unknown)\n'
        '2026-09-27T22:51:41.000 [WARN] handover: mihomo API did not answer\n'
        '2026-09-27T22:51:42.000 [DEBUG] syncFromNative failed\n';

    test('записи с уровнями, стек остаётся при своей ошибке', () {
      final entries = AppLogService.parse(AppLogSource.native, text);

      expect(entries.map((e) => e.level), [
        LogLevel.info,
        LogLevel.error,
        LogLevel.warn,
        LogLevel.debug,
      ]);
      expect(entries[1].text, contains('startVpn failed'));
      expect(entries[1].text, contains('\tat com.keqdroid.keqdroid'));
      expect(entries[2].text, isNot(contains('\tat')));
    });

    test('проблемы — это предупреждения и ошибки', () {
      final problems = AppLogService.parse(
        AppLogSource.app,
        text,
      ).where((e) => e.isProblem).map((e) => e.level);
      expect(problems, [LogLevel.error, LogLevel.warn]);
    });

    test('хвост записи, начало которой срезал предел чтения, не теряется', () {
      final entries = AppLogService.parse(
        AppLogSource.app,
        '\tat some.Frame(Unknown)\n2026-09-27T22:51:39.1 [INFO] next\n',
      );
      expect(entries.first.text, '\tat some.Frame(Unknown)');
      expect(entries.last.text, contains('next'));
    });

    test('пустой журнал — пустой список', () {
      expect(AppLogService.parse(AppLogSource.app, ''), isEmpty);
      expect(AppLogService.parse(AppLogSource.native, '\n\n'), isEmpty);
    });
  });
}
