import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../core/app_logger.dart';
import '../platform/windows_cert_trust.dart';
import '../tunnel/linux_core_paths.dart';
import '../tunnel/windows_core_paths.dart';
import '../tunnel/vpn_backend.dart';
import '../utils/pooled.dart';
import 'windows_desktop_service.dart';

final _ansiEscape = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');

@visibleForTesting
String stripAnsi(String value) => value.replaceAll(_ansiEscape, '');

// трубы обязаны вычитываться: ядро, наговорившее больше буфера, встаёт на записи навсегда
class _CoreLog {
  _CoreLog(Process process) {
    for (final stream in [process.stdout, process.stderr]) {
      stream
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(_add, onError: (Object _) {}, cancelOnError: false);
    }
  }

  static const _keep = 6;
  final _lines = <String>[];

  void _add(String line) {
    final trimmed = stripAnsi(line).trim();
    if (trimmed.isEmpty) return;
    _lines.add(trimmed);
    if (_lines.length > _keep) _lines.removeAt(0);
  }

  String get tail => _lines.isEmpty ? '' : ': ${_lines.join(' | ')}';
}

class EphemeralXrayPing {
  EphemeralXrayPing._();

  static Future<String?> _resolveXray() {
    if (Platform.isWindows) return WindowsCorePaths.xrayExecutable();
    if (Platform.isLinux) return LinuxCorePaths.xrayExecutable();
    return Future<String?>.value(null);
  }

  static Future<String?> _resolveMihomo() {
    if (Platform.isWindows) return WindowsCorePaths.mihomoExecutable();
    if (Platform.isLinux) return LinuxCorePaths.mihomoExecutable();
    return Future<String?>.value(null);
  }

  @visibleForTesting
  static Future<String?> Function(VpnBackend core)? debugResolveCore;

  static Future<String?> _resolveCore(VpnBackend core) =>
      debugResolveCore?.call(core) ??
      (core == VpnBackend.mihomo ? _resolveMihomo() : _resolveXray());

  // свой каталог: mihomo держит cache.db через bbolt с секундным таймаутом на захват
  static List<String> _coreArgs(
    VpnBackend core,
    String configPath,
    String sessionDirPath,
  ) =>
      core == VpnBackend.mihomo
          ? ['-d', sessionDirPath, '-f', configPath]
          : ['run', '-c', configPath];

  static String _coreConfig(String configJson, int port, VpnBackend core) {
    if (core == VpnBackend.mihomo) return _mihomoConfig(configJson, port);
    final config = jsonDecode(configJson) as Map<String, dynamic>;
    final inbounds = config['inbounds'];
    if (inbounds is List) {
      for (final inbound in inbounds) {
        if (inbound is Map<String, dynamic>) inbound['port'] = port;
      }
    }
    return jsonEncode(config);
  }

  static String _mihomoConfig(String configJson, int port) {
    final config = jsonDecode(configJson) as Map<String, dynamic>;
    for (final key in const ['port', 'socks-port', 'mixed-port']) {
      if (config.containsKey(key)) config[key] = port;
    }
    return jsonEncode(config);
  }

  static Future<int> _freeLoopbackPort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  static Future<Directory> _sessionDir() {
    if (Platform.isLinux) return LinuxCorePaths.sessionDir();
    return WindowsCorePaths.sessionDir();
  }

  static String get _binariesHint =>
      Platform.isLinux ? LinuxCorePaths.binariesHint : WindowsCorePaths.binariesHint;

  static Future<void> _attachCoreProcess(int pid) async {
    if (Platform.isWindows) {
      await WindowsDesktopService.attachCoreProcess(pid);
    }
  }

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
    VpnBackend core = VpnBackend.xray,
  }) async {
    return _runSingle(
      xrayConfigJson: xrayConfigJson,
      socksPort: socksPort,
      core: core,
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
    VpnBackend core = VpnBackend.xray,
    bool keepAlive = true,
  }) async {
    if (items.isEmpty) return [];
    // по очереди: у всех элементов батча один socksPort
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
        core: core,
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

  // не поднялось ядро, значит null: по нему PingService делит пачку пополам, а список отказов
  // той же длины он принял бы за ответ, и живые соседи негодного сервера ушли бы в красные
  static Future<
      List<
          ({
            String id,
            bool success,
            int? latencyMs,
            String error,
            int? httpStatus,
          })>?> urlTestMulti({
    required String configJson,
    required List<(String id, int port)> probes,
    required String testUrl,
    required int timeoutMs,
    VpnBackend core = VpnBackend.xray,
    bool keepAlive = true,
    int concurrency = 16,
    void Function(
      ({String id, bool success, int? latencyMs, String error, int? httpStatus})
          item,
    )? onEach,
  }) async {
    if (probes.isEmpty) return const [];
    if (!Platform.isWindows && !Platform.isLinux) return null;

    final coreBin = await _resolveCore(core);
    if (coreBin == null) {
      final error = '${core.wireValue} not found. $_binariesHint';
      return [
        for (final (id, _) in probes)
          (id: id, success: false, latencyMs: null, error: error, httpStatus: null),
      ];
    }

    final sessionDir = await _sessionDir();
    final configFile = File(p.join(sessionDir.path, '${core.wireValue}_ping_multi.json'));
    Process? process;
    try {
      await configFile.writeAsString(configJson);
      process = await Process.start(
        coreBin,
        _coreArgs(core, configFile.path, sessionDir.path),
        workingDirectory: sessionDir.path,
        mode: ProcessStartMode.normal,
      );
      unawaited(_attachCoreProcess(process.pid));
      final log = _CoreLog(process);
      final coreLife = Stopwatch()..start();

      for (var i = 0; i < probes.length; i++) {
        final port = probes[i].$2;
        final left = coreStartupBudget - coreLife.elapsed;
        final startup = await _waitForPort(
          '127.0.0.1',
          port,
          left > _laterPortWait ? left : _laterPortWait,
          process: process,
        );
        if (startup.ready) continue;
        final error = _startupError(startup.exitCode, port, log);
        // живое ядро без единого порта медленное, а не придирчивое: деление пополам
        // стоило бы по сроку старта на каждую половину. mihomo с занятым портом не выходит,
        // но остальные его порты открыты, и такую пачку делим
        final slowCore = startup.exitCode == null &&
            i == 0 &&
            !await _anyPortOpen([for (final probe in probes.skip(1)) probe.$2]);
        if (slowCore) {
          return [
            for (final (id, _) in probes)
              (id: id, success: false, latencyMs: null, error: error, httpStatus: null),
          ];
        }
        AppLogger.instance.debug(
          'EphemeralXrayPing: ${probes.length} probes on one ${core.wireValue}, splitting: $error',
        );
        return null;
      }

      // первая удачная проба значит, что ядро дочитало конфиг: остальным отказам верим сразу
      var coreAwake = false;
      return await mapPooled(probes, concurrency, (probe) async {
        while (true) {
          final result = await httpProbeViaSocks(
            testUrl: testUrl,
            socksPort: probe.$2,
            timeoutMs: timeoutMs,
            keepAlive: keepAlive,
          );
          if (result.success) coreAwake = true;
          if (result.success ||
              coreAwake ||
              !retryProbeWhileCoreWakesUp(
                core: core,
                sinceCoreStart: coreLife.elapsed,
              )) {
            final item = (
              id: probe.$1,
              success: result.success,
              latencyMs: result.latencyMs,
              error: result.error,
              httpStatus: result.httpStatus,
            );
            onEach?.call(item);
            return item;
          }
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      });
    } catch (e) {
      AppLogger.instance.debug('EphemeralXrayPing multi failed: $e');
      return null;
    } finally {
      await _killProcess(process);
      try {
        await sessionDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  static const _laterPortWait = Duration(seconds: 1);

  static Future<bool> _anyPortOpen(List<int> ports) async {
    for (final port in ports) {
      try {
        final socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: const Duration(milliseconds: 200),
        );
        socket.destroy();
        return true;
      } catch (_) {}
    }
    return false;
  }

  static Future<
      List<({String id, bool success, int? kbps, String error})>> speedTestBatch({
    required List<({String id, String xrayConfigJson})> items,
    required int socksPort,
    required String downloadUrl,
    required int timeoutMs,
    VpnBackend core = VpnBackend.xray,
  }) async {
    if (items.isEmpty) return [];
    return _runSerial(() async {
      final out = <({String id, bool success, int? kbps, String error})>[];
      for (final item in items) {
        final r = await _runSpeedSingle(
          xrayConfigJson: item.xrayConfigJson,
          socksPort: socksPort,
          core: core,
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

  // открытый порт у mihomo ещё не готовность: до Running он молча закрывает соединения.
  // на Pixel 6a при живом туннеле это 1.3-1.8 с
  static const coreWakeupGrace = Duration(seconds: 3);

  @visibleForTesting
  static bool retryProbeWhileCoreWakesUp({
    required VpnBackend core,
    required Duration sinceCoreStart,
  }) =>
      core == VpnBackend.mihomo && sinceCoreStart < coreWakeupGrace;

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
    VpnBackend core = VpnBackend.xray,
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

    final coreBin = await _resolveCore(core);
    if (coreBin == null) {
      return (
        success: false,
        latencyMs: null,
        error: '${core.wireValue} not found. $_binariesHint',
        httpStatus: null,
      );
    }

    final sessionDir = await _sessionDir();
    final configFile = File(
      p.join(
        sessionDir.path,
        '${core.wireValue}_ping_${DateTime.now().microsecondsSinceEpoch}.json',
      ),
    );
    Process? process;
    var port = socksPort;

    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        await configFile.writeAsString(_coreConfig(xrayConfigJson, port, core));
        process = await Process.start(
          coreBin,
          _coreArgs(core, configFile.path, sessionDir.path),
          workingDirectory: sessionDir.path,
          mode: ProcessStartMode.normal,
        );
        unawaited(_attachCoreProcess(process.pid));
        final log = _CoreLog(process);

        final startup = await _waitForPort(
          '127.0.0.1',
          port,
          coreStartupBudget,
          process: process,
        );
        if (startup.ready) break;

        // в TUN свободный порт уводит чужое исходящее соединение, пока ядро стартует, отсюда address already in use
        await _killProcess(process);
        process = null;
        if (startup.exitCode == null || attempt == 1) {
          return (
            success: false,
            latencyMs: null,
            error: _startupError(startup.exitCode, port, log),
            httpStatus: null,
          );
        }
        port = await _freeLoopbackPort();
      }

      final coreLife = Stopwatch()..start();
      while (true) {
        final probe = await httpProbeViaSocks(
          testUrl: testUrl,
          socksPort: port,
          timeoutMs: timeoutMs,
          keepAlive: keepAlive,
        );
        if (probe.success ||
            !retryProbeWhileCoreWakesUp(
              core: core,
              sinceCoreStart: coreLife.elapsed,
            )) {
          return probe;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
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
    VpnBackend core = VpnBackend.xray,
  }) async {
    if (!Platform.isWindows && !Platform.isLinux) {
      return (success: false, kbps: null, error: 'Speed test runs on desktop only');
    }

    final coreBin = await _resolveCore(core);
    if (coreBin == null) {
      return (
        success: false,
        kbps: null,
        error: '${core.wireValue} not found. $_binariesHint',
      );
    }

    final sessionDir = await _sessionDir();
    final configFile = File(
      p.join(sessionDir.path,
          '${core.wireValue}_speed_${DateTime.now().microsecondsSinceEpoch}.json'),
    );
    Process? process;

    try {
      await configFile
          .writeAsString(_coreConfig(xrayConfigJson, socksPort, core));
      process = await Process.start(
        coreBin,
        _coreArgs(core, configFile.path, sessionDir.path),
        workingDirectory: sessionDir.path,
        mode: ProcessStartMode.normal,
      );
      unawaited(_attachCoreProcess(process.pid));
      final log = _CoreLog(process);

      final startup = await _waitForPort(
        '127.0.0.1',
        socksPort,
        coreStartupBudget,
        process: process,
      );
      if (!startup.ready) {
        return (
          success: false,
          kbps: null,
          error: _startupError(startup.exitCode, socksPort, log),
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

  static Future<({bool success, int? kbps, String error})> _downloadProbeViaSocks({
    required String downloadUrl,
    required int socksPort,
    required int timeoutMs,
  }) async {
    final client = HttpClient();
    try {
      // dart:io HttpClient умеет только PROXY и DIRECT, поэтому у ядра замера HTTP-инбаунд
      client.findProxy = (_) => 'PROXY 127.0.0.1:$socksPort';
      // сертификат проверяем: иначе MITM нарисует успешный замер мёртвому серверу
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

  @visibleForTesting
  static Future<
      ({
        bool success,
        int? latencyMs,
        String error,
        int? httpStatus,
      })> httpProbeViaSocks({
    required String testUrl,
    required int socksPort,
    required int timeoutMs,
    bool keepAlive = true,
  }) async {
    final uri = Uri.parse(_ensureHttps(testUrl));
    final host = uri.host;
    final port = uri.hasPort ? uri.port : 443;
    final path = uri.path.isEmpty ? '/' : uri.path;
    final connectTimeout = Duration(milliseconds: timeoutMs.clamp(1000, 6000));
    final readTimeout = Duration(milliseconds: timeoutMs.clamp(1000, 8000));

    Socket? raw;
    _HttpResponseReader? reader;
    try {
      // HttpClient не переиспользует туннель CONNECT: каждый запрос платил заново TCP, CONNECT и TLS,
      // и сервер с честными 50 мс показывал 200
      raw = await Socket.connect(
        InternetAddress.loopbackIPv4,
        socksPort,
        timeout: connectTimeout,
      );
      raw.setOption(SocketOption.tcpNoDelay, true);
      reader = _HttpResponseReader(raw);

      raw.write('CONNECT $host:$port HTTP/1.1\r\nHost: $host:$port\r\n\r\n');
      await raw.flush();
      final tunnel = await reader.readResponse(
        DateTime.now().add(readTimeout),
        headOnly: true,
      );
      if (tunnel.status < 200 || tunnel.status > 299) {
        return (
          success: false,
          latencyMs: null,
          error: 'proxy CONNECT ${tunnel.status}',
          httpStatus: tunnel.status,
        );
      }

      // сырой сокет не проходит через WindowsSystemTrust: без этого на свежей Windows пинг давал N/A всему списку
      final tls = await SecureSocket.secure(
        raw,
        host: host,
        onBadCertificate: Platform.isWindows
            ? (cert) => windowsTrustsCertificate(cert.der, host)
            : null,
      ).timeout(connectTimeout);
      raw = tls;
      reader = _HttpResponseReader(tls);

      // первая попытка платит за рукопожатие, вторая меряет чистое время ответа
      ({bool success, int? latencyMs, String error, int? httpStatus})? best;
      final attempts = keepAlive ? 2 : 1;
      for (var attempt = 0; attempt < attempts; attempt++) {
        final sw = Stopwatch()..start();
        // всегда GET: на HEAD не отвечали как раз gstatic и Microsoft
        tls.write(
          'GET $path HTTP/1.1\r\n'
          'Host: $host\r\n'
          'User-Agent: KEQDIS/1.0\r\n'
          'Accept: */*\r\n'
          'Connection: keep-alive\r\n\r\n',
        );
        await tls.flush();
        final res = await reader.readResponse(DateTime.now().add(readTimeout));
        sw.stop();

        final ok = (res.status >= 200 && res.status < 400);
        final result = (
          success: ok,
          latencyMs: sw.elapsedMilliseconds,
          error: ok ? '' : 'HTTP ${res.status}',
          httpStatus: res.status,
        );
        if (!ok) return result;
        if (best == null || sw.elapsedMilliseconds < best.latencyMs!) {
          best = result;
        }
        if (res.closing) break;
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
      await reader?.cancel();
      raw?.destroy();
    }
  }

  static String _ensureHttps(String url) {
    final trimmed = url.trim();
    if (trimmed.toLowerCase().startsWith('http://')) {
      return 'https://${trimmed.substring(7)}';
    }
    return trimmed;
  }

  // ядра стартуют пачкой и делят диск с антивирусом, 5 с не хватало. таймаут пробы сюда не годится:
  // он обрезал срок до 8 с у пинга и до 4 у автовыбора, #18
  static const coreStartupBudget = Duration(seconds: 12);

  static Future<({bool ready, int? exitCode})> _waitForPort(
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
        if (code >= 0) return (ready: false, exitCode: code);
      }
      try {
        final s = await Socket.connect(
          host,
          port,
          timeout: const Duration(milliseconds: 200),
        );
        await s.close();
        return (ready: true, exitCode: null);
      } catch (_) {
        await Future<void>.delayed(delay);
        if (delay.inMilliseconds < 80) {
          delay = Duration(milliseconds: delay.inMilliseconds + 15);
        }
      }
    }
    return (ready: false, exitCode: null);
  }

  static String _startupError(int? exitCode, int port, _CoreLog log) =>
      exitCode != null
          ? 'Core exited with code $exitCode before opening port $port${log.tail}'
          : 'Core did not open port $port in time${log.tail}';

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

// тело каждого ответа дочитываем до конца, иначе следующий GET прочитает хвост предыдущего
class _HttpResponseReader {
  _HttpResponseReader(Stream<List<int>> socket) {
    _sub = socket.listen(
      (data) {
        _buffer.addAll(data);
        _wake();
      },
      onDone: () {
        _done = true;
        _wake();
      },
      onError: (Object e) {
        _error = e;
        _wake();
      },
      cancelOnError: false,
    );
  }

  late final StreamSubscription<List<int>> _sub;
  final List<int> _buffer = [];
  bool _done = false;
  Object? _error;
  Completer<void>? _waiter;

  void _wake() {
    final waiter = _waiter;
    _waiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  Future<void> _more(DateTime deadline) {
    if (_error != null) throw _error!;
    if (_done) throw const SocketException('connection closed by peer');
    final left = deadline.difference(DateTime.now());
    if (left <= Duration.zero) throw TimeoutException('read');
    return (_waiter ??= Completer<void>()).future.timeout(left);
  }

  // после CONNECT по сокету пойдёт TLS, лишний байт читать нельзя
  Future<({int status, bool closing})> readResponse(
    DateTime deadline, {
    bool headOnly = false,
  }) async {
    var end = -1;
    while ((end = _indexOf(13, 10, 13, 10)) < 0) {
      await _more(deadline);
    }
    final head = String.fromCharCodes(_buffer.sublist(0, end));
    _buffer.removeRange(0, end + 4);

    final lines = head.split('\r\n');
    final status = _parseStatus(lines.isEmpty ? '' : lines.first);
    final headers = <String, String>{};
    for (final line in lines.skip(1)) {
      final i = line.indexOf(':');
      if (i > 0) {
        headers[line.substring(0, i).trim().toLowerCase()] =
            line.substring(i + 1).trim();
      }
    }
    final closing =
        (headers['connection'] ?? '').toLowerCase().contains('close');

    if (status >= 100 && status < 200) {
      return readResponse(deadline, headOnly: headOnly);
    }
    if (headOnly || status == 204 || status == 304) {
      return (status: status, closing: closing);
    }

    final chunked =
        (headers['transfer-encoding'] ?? '').toLowerCase().contains('chunked');
    if (chunked) {
      await _drainChunked(deadline);
    } else {
      final length = int.tryParse(headers['content-length'] ?? '');
      if (length != null) {
        await _drainExactly(length, deadline);
      } else if (closing) {
        while (!_done) {
          await _more(deadline);
        }
        _buffer.clear();
      }
    }
    return (status: status, closing: closing);
  }

  Future<void> _drainExactly(int count, DateTime deadline) async {
    while (_buffer.length < count) {
      await _more(deadline);
    }
    _buffer.removeRange(0, count);
  }

  Future<void> _drainChunked(DateTime deadline) async {
    while (true) {
      var nl = -1;
      while ((nl = _indexOf(13, 10)) < 0) {
        await _more(deadline);
      }
      final sizeLine = String.fromCharCodes(_buffer.sublist(0, nl));
      _buffer.removeRange(0, nl + 2);
      final size =
          int.tryParse(sizeLine.split(';').first.trim(), radix: 16) ?? 0;
      if (size == 0) {
        while (true) {
          var tail = -1;
          while ((tail = _indexOf(13, 10)) < 0) {
            await _more(deadline);
          }
          _buffer.removeRange(0, tail + 2);
          if (tail == 0) return;
        }
      }
      await _drainExactly(size + 2, deadline);
    }
  }

  int _indexOf(int a, int b, [int? c, int? d]) {
    final len = c == null ? 2 : 4;
    for (var i = 0; i + len - 1 < _buffer.length; i++) {
      if (_buffer[i] != a || _buffer[i + 1] != b) continue;
      if (c == null) return i;
      if (_buffer[i + 2] == c && _buffer[i + 3] == d) return i;
    }
    return -1;
  }

  static int _parseStatus(String line) {
    final parts = line.split(' ');
    if (parts.length < 2) return 0;
    return int.tryParse(parts[1]) ?? 0;
  }

  Future<void> cancel() async {
    try {
      await _sub.cancel();
    } catch (_) {}
  }
}
