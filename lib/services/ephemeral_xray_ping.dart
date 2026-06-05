import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/app_logger.dart';
import '../tunnel/windows_core_paths.dart';

/// короткоживущий xray для url-пинга, как на android
class EphemeralXrayPing {
  EphemeralXrayPing._();

  static Future<void>? _serialGate;

  static Future<T> _runSerial<T>(Future<T> Function() body) async {
    while (_serialGate != null) {
      await _serialGate;
    }
    final done = Completer<void>();
    _serialGate = done.future;
    try {
      return await body();
    } finally {
      done.complete();
      _serialGate = null;
    }
  }

  static Future<
      ({
        bool success,
        int? latencyMs,
        String error,
        int? httpStatus,
      })> urlTest({
    required String xrayConfigJson,
    required int socksPort,
    required String testUrl,
    required int timeoutMs,
  }) async {
    return _runSerial(
      () => _runSingle(
        xrayConfigJson: xrayConfigJson,
        socksPort: socksPort,
        testUrl: testUrl,
        timeoutMs: timeoutMs,
      ),
    );
  }

  static Future<
      List<
          ({
            String id,
            bool success,
            int? latencyMs,
            String error,
            int? httpStatus,
          })>> urlTestBatch({
    required List<({String id, String xrayConfigJson})> items,
    required int socksPort,
    required String testUrl,
    required int timeoutMs,
  }) async {
    if (items.isEmpty) return [];
    return _runSerial(() async {
      final out = <({
        String id,
        bool success,
        int? latencyMs,
        String error,
        int? httpStatus,
      })>[];
      for (final item in items) {
        final r = await _runSingle(
          xrayConfigJson: item.xrayConfigJson,
          socksPort: socksPort,
          testUrl: testUrl,
          timeoutMs: timeoutMs,
        );
        out.add((
          id: item.id,
          success: r.success,
          latencyMs: r.latencyMs,
          error: r.error,
          httpStatus: r.httpStatus,
        ));
      }
      return out;
    });
  }

  /// Boots an ephemeral Xray per server and downloads [downloadUrl] through its
  /// SOCKS, returning throughput in kbps.
  static Future<
      List<({String id, bool success, int? kbps, String error})>> speedTestBatch({
    required List<({String id, String xrayConfigJson})> items,
    required int socksPort,
    required String downloadUrl,
    required int timeoutMs,
  }) async {
    if (items.isEmpty) return [];
    return _runSerial(() async {
      final out = <({String id, bool success, int? kbps, String error})>[];
      for (final item in items) {
        final r = await _runSpeedSingle(
          xrayConfigJson: item.xrayConfigJson,
          socksPort: socksPort,
          downloadUrl: downloadUrl,
          timeoutMs: timeoutMs,
        );
        out.add((
          id: item.id,
          success: r.success,
          kbps: r.kbps,
          error: r.error,
        ));
      }
      return out;
    });
  }

  static Future<
      ({
        bool success,
        int? latencyMs,
        String error,
        int? httpStatus,
      })> _runSingle({
    required String xrayConfigJson,
    required int socksPort,
    required String testUrl,
    required int timeoutMs,
  }) async {
    if (!Platform.isWindows) {
      return (
        success: false,
        latencyMs: null,
        error: 'Ephemeral Xray ping is only implemented on Windows in Dart',
        httpStatus: null,
      );
    }

    final xrayBin = await WindowsCorePaths.xrayExecutable();
    if (xrayBin == null) {
      return (
        success: false,
        latencyMs: null,
        error: 'xray.exe not found. ${WindowsCorePaths.binariesHint}',
        httpStatus: null,
      );
    }

    final sessionDir = await WindowsCorePaths.sessionDir();
    final configFile = File(
      p.join(sessionDir.path, 'xray_ping_${DateTime.now().microsecondsSinceEpoch}.json'),
    );
    Process? process;

    try {
      await configFile.writeAsString(xrayConfigJson);
      process = await Process.start(
        xrayBin,
        ['run', '-c', configFile.path],
        workingDirectory: sessionDir.path,
        mode: ProcessStartMode.normal,
      );

      final portReady = await _waitForPort(
        '127.0.0.1',
        socksPort,
        Duration(milliseconds: timeoutMs.clamp(500, 5000)),
        process: process,
      );
      if (!portReady) {
        return (
          success: false,
          latencyMs: null,
          error: 'Xray SOCKS port $socksPort not ready',
          httpStatus: null,
        );
      }

      return await _httpProbeViaSocks(
        testUrl: testUrl,
        socksPort: socksPort,
        timeoutMs: timeoutMs,
      );
    } catch (e) {
      AppLogger.instance.debug('EphemeralXrayPing failed: $e');
      return (
        success: false,
        latencyMs: null,
        error: e.toString(),
        httpStatus: null,
      );
    } finally {
      await _killProcess(process);
      try {
        await sessionDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  static Future<({bool success, int? kbps, String error})> _runSpeedSingle({
    required String xrayConfigJson,
    required int socksPort,
    required String downloadUrl,
    required int timeoutMs,
  }) async {
    if (!Platform.isWindows) {
      return (success: false, kbps: null, error: 'Speed test runs on Windows only');
    }

    final xrayBin = await WindowsCorePaths.xrayExecutable();
    if (xrayBin == null) {
      return (
        success: false,
        kbps: null,
        error: 'xray.exe not found. ${WindowsCorePaths.binariesHint}',
      );
    }

    final sessionDir = await WindowsCorePaths.sessionDir();
    final configFile = File(
      p.join(sessionDir.path,
          'xray_speed_${DateTime.now().microsecondsSinceEpoch}.json'),
    );
    Process? process;

    try {
      await configFile.writeAsString(xrayConfigJson);
      process = await Process.start(
        xrayBin,
        ['run', '-c', configFile.path],
        workingDirectory: sessionDir.path,
        mode: ProcessStartMode.normal,
      );

      final portReady = await _waitForPort(
        '127.0.0.1',
        socksPort,
        Duration(milliseconds: timeoutMs.clamp(500, 6000)),
        process: process,
      );
      if (!portReady) {
        return (
          success: false,
          kbps: null,
          error: 'Xray SOCKS port $socksPort not ready',
        );
      }

      return await _downloadProbeViaSocks(
        downloadUrl: downloadUrl,
        socksPort: socksPort,
        timeoutMs: timeoutMs,
      );
    } catch (e) {
      AppLogger.instance.debug('EphemeralXrayPing speed failed: $e');
      return (success: false, kbps: null, error: e.toString());
    } finally {
      await _killProcess(process);
      try {
        await sessionDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Downloads the payload through the SOCKS proxy and computes kbps from the
  /// bytes received over the body-transfer time.
  static Future<({bool success, int? kbps, String error})> _downloadProbeViaSocks({
    required String downloadUrl,
    required int socksPort,
    required int timeoutMs,
  }) async {
    final client = HttpClient();
    try {
      client.findProxy = (_) => 'PROXY 127.0.0.1:$socksPort';
      client.connectionTimeout = Duration(milliseconds: timeoutMs.clamp(1000, 8000));
      client.badCertificateCallback = (_, _, _) => true;

      final request = await client.getUrl(Uri.parse(_ensureHttps(downloadUrl)));
      request.headers.set('User-Agent', 'KEQDIS/1.0');
      final response = await request.close().timeout(
            Duration(milliseconds: timeoutMs.clamp(2000, 30000)),
          );

      if (response.statusCode < 200 || response.statusCode >= 400) {
        await response.drain<void>();
        return (success: false, kbps: null, error: 'HTTP ${response.statusCode}');
      }

      // Time only the body transfer (TLS/connect excluded) for cleaner numbers.
      final sw = Stopwatch()..start();
      var bytes = 0;
      await for (final chunk in response.timeout(
        Duration(milliseconds: timeoutMs.clamp(2000, 30000)),
      )) {
        bytes += chunk.length;
      }
      sw.stop();

      final seconds = sw.elapsedMilliseconds / 1000.0;
      if (bytes <= 0 || seconds <= 0) {
        return (success: false, kbps: null, error: 'No data received');
      }
      final kbps = (bytes * 8 / 1000.0 / seconds).round();
      return (success: true, kbps: kbps, error: '');
    } on TimeoutException {
      return (success: false, kbps: null, error: 'Timeout');
    } catch (e) {
      return (success: false, kbps: null, error: e.toString());
    } finally {
      client.close(force: true);
    }
  }

  static Future<
      ({
        bool success,
        int? latencyMs,
        String error,
        int? httpStatus,
      })> _httpProbeViaSocks({
    required String testUrl,
    required int socksPort,
    required int timeoutMs,
  }) async {
    final uri = _ensureHttps(testUrl);
    final useHead = uri.contains('generate_204') ||
        uri.contains('connecttest.txt');

    final client = HttpClient();
    try {
      client.findProxy = (_) => 'PROXY 127.0.0.1:$socksPort';
      client.connectionTimeout = Duration(milliseconds: timeoutMs.clamp(1000, 6000));
      client.badCertificateCallback = (_, _, _) => true;

      final sw = Stopwatch()..start();
      final request = await client.openUrl(
        useHead ? 'HEAD' : 'GET',
        Uri.parse(uri),
      );
      request.headers.set('User-Agent', 'KEQDIS/1.0');
      request.headers.set('Connection', 'close');
      final response = await request.close().timeout(
        Duration(milliseconds: timeoutMs.clamp(1000, 8000)),
      );
      if (!useHead && response.statusCode != 204) {
        await response.drain<void>();
      }
      sw.stop();

      final code = response.statusCode;
      final ok = (code >= 200 && code < 400) || code == 204;
      return (
        success: ok,
        latencyMs: sw.elapsedMilliseconds,
        error: ok ? '' : 'HTTP $code',
        httpStatus: code,
      );
    } on TimeoutException {
      return (
        success: false,
        latencyMs: null,
        error: 'Timeout',
        httpStatus: null,
      );
    } catch (e) {
      return (
        success: false,
        latencyMs: null,
        error: e.toString(),
        httpStatus: null,
      );
    } finally {
      client.close(force: true);
    }
  }

  static String _ensureHttps(String url) {
    final trimmed = url.trim();
    if (trimmed.toLowerCase().startsWith('http://')) {
      return 'https://${trimmed.substring(7)}';
    }
    return trimmed;
  }

  static Future<bool> _waitForPort(
    String host,
    int port,
    Duration maxWait, {
    Process? process,
  }) async {
    final deadline = DateTime.now().add(maxWait);
    var delay = const Duration(milliseconds: 20);
    while (DateTime.now().isBefore(deadline)) {
      if (process != null) {
        final code = await process.exitCode.timeout(
          const Duration(milliseconds: 1),
          onTimeout: () => -1,
        );
        if (code >= 0) return false;
      }
      try {
        final s = await Socket.connect(
          host,
          port,
          timeout: const Duration(milliseconds: 200),
        );
        await s.close();
        return true;
      } catch (_) {
        await Future<void>.delayed(delay);
        if (delay.inMilliseconds < 80) {
          delay = Duration(milliseconds: delay.inMilliseconds + 15);
        }
      }
    }
    return false;
  }

  static Future<void> _killProcess(Process? process) async {
    if (process == null) return;
    try {
      process.kill(ProcessSignal.sigterm);
      await process.exitCode.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }
}
