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
    final uri = Uri.parse(_ensureHttps(testUrl));
    final host = uri.host;
    final port = uri.hasPort ? uri.port : 443;
    final path = uri.path.isEmpty ? '/' : uri.path;
    final connectTimeout = Duration(milliseconds: timeoutMs.clamp(1000, 6000));
    final readTimeout = Duration(milliseconds: timeoutMs.clamp(1000, 8000));

    Socket? raw;
    _HttpResponseReader? reader;
    try {
      // Соединение ведём РУКАМИ, а не через HttpClient, и это не вкусовщина.
      //
      // `HttpClient` не переиспользует туннель CONNECT: замерено — три запроса
      // подряд открывают три туннеля, тогда как без прокси тот же клиент
      // обходится одним. То есть «второй запрос по тёплому соединению»,
      // которым здесь меряется чистое время ответа, на десктопе не наступал
      // никогда: каждая попытка платила заново TCP, CONNECT и TLS-рукопожатие.
      // Четыре-пять RTT вместо одного — сервер с честными 50 мс показывал 200,
      // и пороги цвета красили здоровое в красное. На Android этой беды нет:
      // там `HttpURLConnection` держит пул как положено.
      //
      // Своими руками мы получаем ровно ту же семантику, что у Android:
      // рукопожатие один раз, дальше GET'ы по одному и тому же TLS-сокету.
      raw = await Socket.connect(
        InternetAddress.loopbackIPv4,
        socksPort,
        timeout: connectTimeout,
      );
      raw.setOption(SocketOption.tcpNoDelay, true);
      reader = _HttpResponseReader(raw);

      // Эфемерное ядро поднимает на этом порту HTTP-инбаунд (см. режим пинга в
      // ConfigGeneratorV2), поэтому туннель просим методом CONNECT.
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

      // Сертификат проверяем: без проверки MITM «нарисовал» бы успешный пинг
      // мёртвому или подменённому серверу.
      final tls = await SecureSocket.secure(raw, host: host)
          .timeout(connectTimeout);
      raw = tls;
      reader = _HttpResponseReader(tls);

      // Первая попытка оплачивает рукопожатие и прогрев цепочки — она меряет
      // стоимость процедуры, а не сервер. Вторая идёт по уже поднятому TLS и
      // показывает чистое время ответа; ради неё всё это и затевалось.
      ({bool success, int? latencyMs, String error, int? httpStatus})? best;
      final attempts = keepAlive ? 2 : 1;
      for (var attempt = 0; attempt < attempts; attempt++) {
        final sw = Stopwatch()..start();
        // Всегда GET. Раньше на `generate_204` и `connecttest.txt` уходил HEAD —
        // то есть ровно на два пресета из трёх (gstatic-дефолт и Microsoft), и
        // именно они у пользователей не отвечали, пока Cloudflare с GET работал.
        // Экономии от HEAD тут нет: 204 без тела, connecttest.txt — 22 байта.
        tls.write(
          'GET $path HTTP/1.1\r\n'
          'Host: $host\r\n'
          'User-Agent: KEQDIS/1.0\r\n'
          'Accept: */*\r\n'
          'Connection: keep-alive\r\n\r\n',
        );
        await tls.flush();
        // Срок у каждой попытки свой: медленная первая не должна съедать время
        // второй, ради которой всё и делается.
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
        // Сервер попрощался — второй замер по этому сокету уже не сделать, а
        // открывать новый бессмысленно: он померил бы то же, что и первый.
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

/// Читает ответы HTTP/1.1 из одного сокета подряд.
///
/// Своё чтение нужно потому, что замер ведётся по ОДНОМУ соединению: тело
/// каждого ответа обязано быть дочитано ровно до конца, иначе следующий GET
/// прочитает хвост предыдущего вместо своего статуса. `HttpClient` это делал бы
/// сам, но он не переиспользует туннель CONNECT — см. комментарий в
/// `_httpProbeViaSocks`, ради чего всё и написано руками.
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

  /// Ждёт следующую порцию байт. Срок общий на весь ответ, а не на порцию:
  /// иначе медленный сервер, отдающий по чуть-чуть, никогда не упрётся в
  /// таймаут.
  Future<void> _more(DateTime deadline) {
    if (_error != null) throw _error!;
    if (_done) throw const SocketException('connection closed by peer');
    final left = deadline.difference(DateTime.now());
    if (left <= Duration.zero) throw TimeoutException('read');
    return (_waiter ??= Completer<void>()).future.timeout(left);
  }

  /// Читает один ответ целиком и возвращает его статус.
  ///
  /// [headOnly] — для ответа на CONNECT: у него тела нет по определению, а
  /// дальше по этому же сокету пойдёт уже TLS, и лишний байт из него читать
  /// нельзя.
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

    // 1xx — промежуточный ответ, настоящий придёт следом.
    if (status >= 100 && status < 200) {
      return readResponse(deadline, headOnly: headOnly);
    }
    // 204 и 304 по спецификации без тела, длину при них слать не обязаны.
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
        // Ни длины, ни кусков, но соединение закрывается — тело кончается
        // вместе с ним. Второй попытки по этому сокету всё равно не будет.
        while (!_done) {
          await _more(deadline);
        }
        _buffer.clear();
      }
      // Ни длины, ни chunked, ни close — тела нет.
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
        // Нулевой кусок, за ним возможные трейлеры и пустая строка.
        while (true) {
          var tail = -1;
          while ((tail = _indexOf(13, 10)) < 0) {
            await _more(deadline);
          }
          _buffer.removeRange(0, tail + 2);
          if (tail == 0) return;
        }
      }
      // Кусок и завершающий его CRLF.
      await _drainExactly(size + 2, deadline);
    }
  }

  /// Смещение первой встречи последовательности байт, иначе -1.
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
    } catch (_) {
      // Подписку мог уже забрать TLS-слой при апгрейде сокета.
    }
  }
}
