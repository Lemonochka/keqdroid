import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/app_logger.dart';
import '../tunnel/linux_core_paths.dart';
import '../tunnel/windows_core_paths.dart';
import '../utils/keqrnel_config.dart';
import 'windows_desktop_service.dart';

/// короткоживущий xray для url-пинга, как на android
class EphemeralXrayPing {
  EphemeralXrayPing._();

  // Desktop core resolution is platform-specific; the rest (config, socks probe)
  // is platform-neutral so url/speed ping work on Windows and Linux alike.
  static Future<String?> _resolveXray() {
    // Desktop runs the unified keqrnel core (standalone xray is gone).
    if (Platform.isWindows) return WindowsCorePaths.keqrnelExecutable();
    if (Platform.isLinux) return LinuxCorePaths.keqrnelExecutable();
    return Future<String?>.value(null);
  }

  /// The ephemeral test runs through keqrnel, so the xray config is wrapped into
  /// keqrnel's embedded-xray outbound (its own socks inbound binds the test port
  /// exactly like standalone xray).
  static String _coreConfig(String xrayConfigJson) =>
      (Platform.isWindows || Platform.isLinux)
          ? KeqrnelConfig.wrapXray(xrayConfigJson)
          : xrayConfigJson;

  static Future<Directory> _sessionDir() {
    if (Platform.isLinux) return LinuxCorePaths.sessionDir();
    return WindowsCorePaths.sessionDir();
  }

  static String get _binariesHint =>
      Platform.isLinux ? LinuxCorePaths.binariesHint : WindowsCorePaths.binariesHint;

  /// Windows registers cores for taskkill cleanup; no-op elsewhere.
  static Future<void> _attachCoreProcess(int pid) async {
    if (Platform.isWindows) {
      await WindowsDesktopService.attachCoreProcess(pid);
    }
  }

  static Future<void>? _serialGate;

  /// Пропускает по одному замеру за раз.
  ///
  /// Нужен только спидтесту: он меряет полосу канала, и параллельные качалки
  /// делили бы её между собой, выдавая N заниженных цифр вместо одной честной.
  /// URL-пинг через эту калитку не идёт — каждый его замер живёт в своём
  /// временном каталоге ([_sessionDir] делает `createTemp`) и на своём порту,
  /// общего состояния между замерами нет. Сколько их идёт разом, решает
  /// PingService.urlPingConcurrency — одна точка на все платформы.
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
    return _runSingle(
      xrayConfigJson: xrayConfigJson,
      socksPort: socksPort,
      testUrl: testUrl,
      timeoutMs: timeoutMs,
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
    bool keepAlive = true,
  }) async {
    if (items.isEmpty) return [];
    // Внутри батча — по очереди: все элементы приходят с ОДНИМ socksPort, и
    // параллельно они дрались бы за него. Параллелит вызовы PingService, он же
    // и выдаёт каждому замеру свой порт.
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
        keepAlive: keepAlive,
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
    bool keepAlive = true,
  }) async {
    if (!Platform.isWindows && !Platform.isLinux) {
      return (
        success: false,
        latencyMs: null,
        error: 'Ephemeral Xray ping is only implemented on desktop in Dart',
        httpStatus: null,
      );
    }

    final xrayBin = await _resolveXray();
    if (xrayBin == null) {
      return (
        success: false,
        latencyMs: null,
        error: 'xray not found. $_binariesHint',
        httpStatus: null,
      );
    }

    final sessionDir = await _sessionDir();
    final configFile = File(
      p.join(sessionDir.path, 'xray_ping_${DateTime.now().microsecondsSinceEpoch}.json'),
    );
    Process? process;

    try {
      await configFile.writeAsString(_coreConfig(xrayConfigJson));
      process = await Process.start(
        xrayBin,
        ['run', '-c', configFile.path],
        workingDirectory: sessionDir.path,
        mode: ProcessStartMode.normal,
      );
      unawaited(_attachCoreProcess(process.pid));

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
        keepAlive: keepAlive,
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
    if (!Platform.isWindows && !Platform.isLinux) {
      return (success: false, kbps: null, error: 'Speed test runs on desktop only');
    }

    final xrayBin = await _resolveXray();
    if (xrayBin == null) {
      return (
        success: false,
        kbps: null,
        error: 'xray not found. $_binariesHint',
      );
    }

    final sessionDir = await _sessionDir();
    final configFile = File(
      p.join(sessionDir.path,
          'xray_speed_${DateTime.now().microsecondsSinceEpoch}.json'),
    );
    Process? process;

    try {
      await configFile.writeAsString(_coreConfig(xrayConfigJson));
      process = await Process.start(
        xrayBin,
        ['run', '-c', configFile.path],
        workingDirectory: sessionDir.path,
        mode: ProcessStartMode.normal,
      );
      unawaited(_attachCoreProcess(process.pid));

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
      // HTTP proxy ('PROXY host:port'), not SOCKS: dart:io HttpClient.findProxy
      // supports only PROXY (HTTP CONNECT) and DIRECT — never SOCKS/SOCKS5. The
      // ephemeral ping config exposes an HTTP inbound on this port for exactly this
      // reason (see ConfigGeneratorV2 ping mode). The port arg is still named
      // socksPort for historical reasons.
      client.findProxy = (_) => 'PROXY 127.0.0.1:$socksPort';
      // Сертификат проверяем: с badCertificateCallback=true MITM мог
      // «нарисовать» успешный замер мёртвому/подменённому серверу.
      client.connectionTimeout = Duration(milliseconds: timeoutMs.clamp(1000, 8000));

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
    bool keepAlive = true,
  }) async {
    final uri = _ensureHttps(testUrl);

    final client = HttpClient();
    try {
      // The ephemeral core exposes an HTTP inbound on this port (see
      // ConfigGeneratorV2 ping mode). dart:io HttpClient.findProxy can only do
      // 'PROXY host:port' (HTTP CONNECT) or 'DIRECT' — it has no SOCKS support,
      // so a 'SOCKS'/'SOCKS5' directive throws "Invalid proxy configuration ...".
      client.findProxy = (_) => 'PROXY 127.0.0.1:$socksPort';
      // Сертификат проверяем: с badCertificateCallback=true MITM мог
      // «нарисовать» успешный пинг мёртвому/подменённому серверу.
      client.connectionTimeout = Duration(milliseconds: timeoutMs.clamp(1000, 6000));

      // Два запроса по одному соединению, берём лучший. Первый оплачивает DNS,
      // TLS-рукопожатие и прогрев цепочки — он меряет стоимость процедуры, а не
      // сервер. Второй идёт по уже установленному соединению и показывает
      // чистое время ответа, ради чего keep-alive и нужен: поэтому здесь
      // НЕТ `Connection: close`, он бы рвал соединение после первого же ответа.
      ({bool success, int? latencyMs, String error, int? httpStatus})? best;
      final attempts = keepAlive ? 2 : 1;
      for (var attempt = 0; attempt < attempts; attempt++) {
        final sw = Stopwatch()..start();
        // Всегда GET. Раньше на `generate_204` и `connecttest.txt` уходил HEAD —
        // то есть ровно на два пресета из трёх (gstatic-дефолт и Microsoft), и
        // именно они у пользователей не отвечали, пока Cloudflare с GET работал.
        // Экономии от HEAD тут нет: 204 без тела, connecttest.txt — 22 байта.
        final request = await client.openUrl('GET', Uri.parse(uri));
        request.headers.set('User-Agent', 'KEQDIS/1.0');
        final response = await request.close().timeout(
          Duration(milliseconds: timeoutMs.clamp(1000, 8000)),
        );
        // Тело нужно дочитать даже когда оно не нужно: недочитанный ответ
        // не отдаёт соединение обратно в пул, и второй запрос откроет новое —
        // то есть померит то же самое, что первый.
        await response.drain<void>();
        sw.stop();

        final code = response.statusCode;
        final ok = (code >= 200 && code < 400) || code == 204;
        final result = (
          success: ok,
          latencyMs: sw.elapsedMilliseconds,
          error: ok ? '' : 'HTTP $code',
          httpStatus: code,
        );
        if (!ok) return result;
        if (best == null || sw.elapsedMilliseconds < best.latencyMs!) {
          best = result;
        }
      }
      return best!;
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
