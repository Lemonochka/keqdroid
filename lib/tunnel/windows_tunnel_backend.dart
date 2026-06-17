import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../core/app_logger.dart';
import '../core/exceptions.dart';
import '../services/debug_log_service.dart';
import '../services/ephemeral_xray_ping.dart';
import '../services/firefox_proxy_helper.dart';
import '../services/windows_desktop_service.dart';
import '../utils/wireproxy_config.dart';
import 'connection_mode.dart';
import 'socks_credential_generator.dart';
import 'tunnel_backend.dart';
import 'tunnel_session_request.dart';
import 'tunnel_state.dart';
import 'vpn_backend.dart';
import 'windows_core_paths.dart';
import 'xray_session_stats.dart';

/// windows: xray всегда + sing-box только для tun, системный прокси через wininet
class WindowsTunnelBackend implements TunnelBackend {
  static const _method = MethodChannel('keqdis_vpn_channel');

  /// Active session backend — for Xray log export on desktop.
  static WindowsTunnelBackend? activeInstance;

  final _stateCtrl = StreamController<VpnState>.broadcast();
  Process? _xrayProcess;
  Process? _singboxProcess;
  Directory? _sessionDir;
  ({String username, String password})? _pendingCreds;
  ConnectionMode? _activeMode;
  final StringBuffer _xrayLog = StringBuffer();
  final StringBuffer _singboxLog = StringBuffer();

  // AmneziaWG: процесс wireproxy-awg (SOCKS5[/HTTP]); используется и для proxy-,
  // и для TUN-режима (в TUN дополнительно поднимается sing-box). null когда неактивен.
  Process? _wireproxyProcess;
  // Порт info/metrics эндпоинта wireproxy (`-i`) для подсчёта трафика в proxy-режиме.
  int? _awgInfoPort;

  Timer? _statsTimer;
  DateTime? _sessionStartedAt;
  int _prevInOctets = 0;
  int _prevOutOctets = 0;
  int _totalDownload = 0;
  int _totalUpload = 0;
  String? _xrayBinPath;

  @override
  Stream<VpnState> get stateStream => _stateCtrl.stream;

  @override
  void init() {}

  @override
  void dispose() {
    if (identical(activeInstance, this)) activeInstance = null;
    unawaited(stopSession());
    _stateCtrl.close();
  }

  /// Tail of Xray (+ sing-box in TUN) stdout/stderr for the debug screen.
  String exportSessionLogs({int maxLines = 400}) {
    final combined = StringBuffer()
      ..writeln(_xrayLog)
      ..writeln(_singboxLog);
    return _tail(combined, maxLines: maxLines);
  }

  @override
  Future<({String username, String password})> fetchSocksCredentials() async {
    _pendingCreds = SocksCredentialGenerator.generatePair();
    return _pendingCreds!;
  }

  @override
  Future<void> startSession(TunnelSessionRequest request) async {
    final creds = _pendingCreds;
    if (creds == null || creds.username.isEmpty || creds.password.isEmpty) {
      throw const VpnException(
        'Call fetchSocksCredentials before startSession on Windows',
      );
    }

    _emit(VpnState(status: VpnStatus.connecting, activeMode: request.mode));
    _activeMode = request.mode;
    _xrayLog.clear();
    _singboxLog.clear();

    try {
      await stopSession();
      activeInstance = this;

      _sessionDir = await WindowsCorePaths.sessionDir();

      if (request.vpnBackend == VpnBackend.awg) {
        await _startAwgSession(request);
      } else {
        await _startXraySession(request);
        await WindowsDesktopService.registerSessionCoreProcesses(
          xrayPid: _xrayProcess?.pid ?? 0,
          singboxPid: _singboxProcess?.pid ?? 0,
        );
      }

      _startStatsLoop(request.mode);
      _emitConnectedTelemetry(request.mode);
    } catch (e, st) {
      AppLogger.instance.error('Windows tunnel start failed', error: e, stackTrace: st);
      await stopSession();
      _emit(
        VpnState(
          status: VpnStatus.error,
          errorMessage: e.toString(),
          activeMode: request.mode,
        ),
      );
      if (e is AppException) rethrow;
      throw VpnStartException(e.toString(), cause: e);
    }
  }

  Future<void> _startXraySession(TunnelSessionRequest request) async {
    final xrayBin = await WindowsCorePaths.xrayExecutable();
    if (xrayBin == null) {
      throw VpnStartException(
        'xray.exe not found. ${WindowsCorePaths.binariesHint}',
      );
    }

    final xrayConfigFile = File('${_sessionDir!.path}/xray.json');
    _xrayBinPath = xrayBin;

    var xrayConfigBody = request.xrayConfig;
    if (request.mode == ConnectionMode.proxy) {
      final decoded = jsonDecode(request.xrayConfig) as Map<String, dynamic>;
      xrayConfigBody = jsonEncode(
        XraySessionStats.augmentConfig(
          decoded,
          apiPort: XraySessionStats.defaultApiPort,
        ),
      );
    }
    await xrayConfigFile.writeAsString(xrayConfigBody);

    await _ensurePortsAvailable(request, needsHttpFromXray: true);

    // point xray at geoip.dat / geosite.dat so geoip:/geosite: rules resolve
    // even though the working dir is a temp session dir.
    final geoDir = await WindowsCorePaths.geoAssetDir();

    _xrayProcess = await Process.start(
      xrayBin,
      ['run', '-c', xrayConfigFile.path],
      workingDirectory: _sessionDir!.path,
      environment: geoDir != null ? {'XRAY_LOCATION_ASSET': geoDir} : null,
      mode: ProcessStartMode.normal,
    );
    _pipeProcessOutput(_xrayProcess!, _xrayLog, 'xray');

    final socksReady = await _waitForPort(
      '127.0.0.1',
      request.socksPort,
      process: _xrayProcess,
      log: _xrayLog,
      processLabel: 'Xray',
    );
    if (!socksReady) {
      throw VpnStartException(
        'Xray SOCKS port ${request.socksPort} did not open.\n${_tail(_xrayLog)}',
      );
    }

    if (request.mode == ConnectionMode.proxy && request.systemProxy) {
      final httpReady = await _waitForPort(
        '127.0.0.1',
        request.httpPort,
        process: _xrayProcess,
        log: _xrayLog,
        processLabel: 'Xray HTTP',
      );
      if (!httpReady) {
        throw VpnStartException(
          'Xray HTTP port ${request.httpPort} did not open. '
          'System proxy needs the HTTP inbound.\n${_tail(_xrayLog)}',
        );
      }
    }

    if (request.mode == ConnectionMode.tun) {
      await _startSingboxSession(request);
    }

    if (request.mode == ConnectionMode.proxy && request.systemProxy) {
      await _applySystemProxy(request);
    }
  }

  /// AmneziaWG (оба режима на базе wireproxy-awg, который встраивает amneziawg-go):
  ///  - proxy: wireproxy → локальные SOCKS5/HTTP → системный прокси Windows (без админа);
  ///  - tun:   wireproxy → локальный SOCKS5 → sing-box TUN (как xray-TUN; нужен админ).
  Future<void> _startAwgSession(TunnelSessionRequest request) async {
    if (request.mode == ConnectionMode.proxy) {
      await _startAwgProxySession(request);
    } else {
      await _startAwgTunSession(request);
    }
  }

  /// Запускает wireproxy-awg. [withHttp] — поднимать ли HTTP-прокси (для proxy-режима).
  /// info-эндпоинт (`-i`) поднимаем всегда — из него читаем счётчики трафика.
  Future<void> _startWireproxy(
    TunnelSessionRequest request, {
    required bool withHttp,
  }) async {
    final wpBin = await WindowsCorePaths.wireproxyExecutable();
    if (wpBin == null) {
      throw VpnStartException(
        'wireproxy.exe not found. ${WindowsCorePaths.binariesHint}',
      );
    }
    final conf = request.awgConfig;
    if (conf == null || conf.isEmpty) {
      throw const VpnStartException('awgConfig is required for AmneziaWG');
    }

    final wpConf = WireproxyConfigGen.generate(
      conf,
      socksPort: request.socksPort,
      httpPort: request.httpPort,
      withHttp: withHttp,
    );
    final confFile = File('${_sessionDir!.path}/wireproxy.conf');
    await confFile.writeAsString(wpConf);

    final infoPort = await _freePort();
    _awgInfoPort = infoPort;

    _wireproxyProcess = await Process.start(
      wpBin,
      ['-i', '127.0.0.1:$infoPort', '-c', confFile.path],
      workingDirectory: _sessionDir!.path,
      mode: ProcessStartMode.normal,
    );
    _pipeProcessOutput(_wireproxyProcess!, _xrayLog, 'wireproxy');

    final socksReady = await _waitForPort(
      '127.0.0.1',
      request.socksPort,
      process: _wireproxyProcess,
      log: _xrayLog,
      processLabel: 'wireproxy',
    );
    if (!socksReady) {
      throw VpnStartException(
        'wireproxy SOCKS port ${request.socksPort} did not open.\n${_tail(_xrayLog)}',
      );
    }
  }

  Future<void> _startAwgProxySession(TunnelSessionRequest request) async {
    await _startWireproxy(request, withHttp: true);

    await WindowsDesktopService.registerSessionCoreProcesses(
      xrayPid: _wireproxyProcess?.pid ?? 0,
      singboxPid: 0,
    );

    if (request.systemProxy) {
      final httpReady = await _waitForPort(
        '127.0.0.1',
        request.httpPort,
        process: _wireproxyProcess,
        log: _xrayLog,
        processLabel: 'wireproxy HTTP',
      );
      if (!httpReady) {
        throw VpnStartException(
          'wireproxy HTTP port ${request.httpPort} did not open.\n${_tail(_xrayLog)}',
        );
      }
      await _applySystemProxy(request);
    }
  }

  /// TUN: wireproxy отдаёт локальный SOCKS5, sing-box заворачивает в него tun.
  /// Переиспользует проверенный xray-TUN пайплайн (роутинг/split/kill-switch).
  Future<void> _startAwgTunSession(TunnelSessionRequest request) async {
    await _startWireproxy(request, withHttp: false);
    await _startSingboxSession(request);

    await WindowsDesktopService.registerSessionCoreProcesses(
      xrayPid: _wireproxyProcess?.pid ?? 0,
      singboxPid: _singboxProcess?.pid ?? 0,
    );
  }

  /// Свободный TCP-порт на loopback (для info-эндпоинта wireproxy).
  Future<int> _freePort() async {
    final s = await ServerSocket.bind('127.0.0.1', 0);
    final port = s.port;
    await s.close();
    return port;
  }

  Future<void> _startSingboxSession(TunnelSessionRequest request) async {
    final singBin = await WindowsCorePaths.singboxExecutable();
    if (singBin == null) {
      throw VpnStartException(
        'sing-box.exe not found. ${WindowsCorePaths.binariesHint}',
      );
    }
    final singConfig = request.singboxConfig;
    if (singConfig == null || singConfig.isEmpty) {
      throw const VpnStartException('singboxConfig is required');
    }

    final singConfigFile = File('${_sessionDir!.path}/sing-box.json');
    await singConfigFile.writeAsString(singConfig);

    final singWorkDir = p.dirname(singBin);
    _singboxProcess = await Process.start(
      singBin,
      ['run', '-c', singConfigFile.path],
      workingDirectory: singWorkDir,
      mode: ProcessStartMode.normal,
    );
    _pipeProcessOutput(_singboxProcess!, _singboxLog, 'sing-box');

    if (request.mode == ConnectionMode.tun) {
      final singReady = await _waitForSingbox(
        process: _singboxProcess!,
        log: _singboxLog,
      );
      if (!singReady) {
        throw VpnStartException(
          'sing-box TUN did not start. Run as Administrator and ensure '
          'wintun.dll is next to sing-box.exe if required.\n${_tail(_singboxLog)}',
        );
      }
    }
  }

  Future<void> _ensurePortsAvailable(
    TunnelSessionRequest request, {
    required bool needsHttpFromXray,
  }) async {
    final portAvailable = await _isPortAvailable('127.0.0.1', request.socksPort);
    if (!portAvailable) {
      throw VpnStartException(
        'SOCKS port ${request.socksPort} is already in use.',
      );
    }
    if (needsHttpFromXray &&
        request.mode == ConnectionMode.proxy &&
        request.systemProxy &&
        !await _isPortAvailable('127.0.0.1', request.httpPort)) {
      throw VpnStartException(
        'HTTP port ${request.httpPort} is already in use.',
      );
    }
  }

  Future<void> _applySystemProxy(TunnelSessionRequest request) async {
    AppLogger.instance.info(
      'setSystemProxy: socks=${request.socksPort} http=${request.httpPort}',
    );
    try {
      final proxyResult = await _method.invokeMethod<Map<Object?, Object?>>(
        'setSystemProxy',
        {
          'enabled': true,
          'host': '127.0.0.1',
          'socksPort': request.socksPort,
          'httpPort': request.httpPort,
          'probe': false,
        },
      );
      final registryEnabled = proxyResult?['registryEnabled'] == true;
      final registryServer = proxyResult?['registryServer']?.toString() ?? '';
      final logFile = proxyResult?['logFile']?.toString() ?? '';
      AppLogger.instance.info(
        'System proxy OK: registry enabled=$registryEnabled '
        'server=$registryServer logFile=$logFile',
      );
      unawaited(_logProxyProbesInBackground(request.httpPort));
      if (!registryEnabled ||
          !_registryProxyMatchesHttp(registryServer, request.httpPort)) {
        await _appendProxyDebugLogs('validation failed');
        throw VpnStartException(
          'System proxy was not applied (enabled=$registryEnabled, '
          'server="$registryServer", expected HTTP on 127.0.0.1:${request.httpPort}). '
          'Check Windows proxy settings (Settings → Network → Proxy).',
        );
      }
    } on PlatformException catch (e) {
      await _appendProxyDebugLogs('setSystemProxy PlatformException');
      final details = e.details;
      final detailLogs = details is Map ? details['logs']?.toString() : null;
      final logFile = details is Map ? details['logFile']?.toString() : null;
      final buffer = StringBuffer(e.message ?? e.code);
      if (logFile != null && logFile.isNotEmpty) {
        buffer.writeln();
        buffer.writeln('Log file: $logFile');
      }
      if (detailLogs != null && detailLogs.isNotEmpty) {
        buffer.writeln();
        buffer.writeln('--- Proxy debug (native) ---');
        buffer.writeln(detailLogs);
      }
      throw VpnStartException(buffer.toString(), cause: e);
    }

    unawaited(_applyFirefoxProxyAfterConnect(request.httpPort));
  }

  @override
  Future<void> stopSession() async {
    _stopStatsLoop();
    _emit(const VpnState(status: VpnStatus.disconnecting));

    try {
      await _method.invokeMethod<void>('setSystemProxy', {'enabled': false});
    } catch (_) {}

    final cleared = await FirefoxProxyHelper.clearManualHttpProxy();
    if (cleared.isNotEmpty) {
      AppLogger.instance.info(
        'Firefox: removed KeqDroid proxy block from ${cleared.length} profile(s). '
        'Restart Firefox if it was running.',
      );
    }

    await _killProcess(_wireproxyProcess);
    await _killProcess(_singboxProcess);
    await _killProcess(_xrayProcess);
    _wireproxyProcess = null;
    _awgInfoPort = null;
    _singboxProcess = null;
    _xrayProcess = null;
    _xrayBinPath = null;

    await WindowsDesktopService.clearSessionCoreProcesses();

    final dir = _sessionDir;
    _sessionDir = null;
    if (dir != null && dir.existsSync()) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }

    _activeMode = null;
    if (identical(activeInstance, this)) activeInstance = null;
    _emit(VpnState.disconnected);
  }

  @override
  Future<bool> requestTunnelPermission() async {
    try {
      final ok = await _method.invokeMethod<bool>('requestTunnelPermission');
      return ok ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<VpnState> getCurrentState() async {
    if (_xrayProcess != null || _wireproxyProcess != null) {
      return _buildConnectedState(_activeMode);
    }
    return VpnState.disconnected;
  }

  @override
  Future<int?> getPing(String address, int port) async {
    final sw = Stopwatch()..start();
    try {
      final s = await Socket.connect(
        address,
        port,
        timeout: const Duration(seconds: 5),
      );
      sw.stop();
      await s.close();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getInstalledApps({
    bool includeSystem = false,
  }) async {
    try {
      final result = await _method.invokeMethod<List<dynamic>>(
        'listProcesses',
        <String, dynamic>{'includeSystem': includeSystem},
      );
      return result
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
    } on PlatformException catch (e) {
      AppLogger.instance.warn('listProcesses failed: ${e.message}');
      return [];
    } catch (e, st) {
      AppLogger.instance.error('listProcesses failed', error: e, stackTrace: st);
      return [];
    }
  }

  @override
  Future<String?> getAppIcon(String path) async {
    if (path.isEmpty) return null;
    try {
      final result = await _method.invokeMethod<String>(
        'getAppIcon',
        <String, dynamic>{'path': path},
      );
      if (result == null || result.isEmpty) return null;
      return result;
    } on PlatformException catch (e) {
      AppLogger.instance.debug('getAppIcon failed: ${e.message}');
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<
      List<({
        String id,
        bool success,
        int? latencyMs,
        String error,
        int? httpStatus,
      })>> xrayUrlTestBatch({
    required List<(String id, String xrayConfig)> items,
    required int socksPort,
    String testUrl = 'https://connectivitycheck.gstatic.com/generate_204',
    int timeoutMs = 15000,
  }) async {
    if (items.isEmpty) return [];
    final raw = await EphemeralXrayPing.urlTestBatch(
      items: items
          .map((e) => (id: e.$1, xrayConfigJson: e.$2))
          .toList(),
      socksPort: socksPort,
      testUrl: testUrl,
      timeoutMs: timeoutMs,
    );
    return raw
        .map(
          (r) => (
            id: r.id,
            success: r.success,
            latencyMs: r.latencyMs,
            error: r.error,
            httpStatus: r.httpStatus,
          ),
        )
        .toList();
  }

  @override
  Future<
      List<({
        String id,
        bool success,
        int? kbps,
        String error,
      })>> xraySpeedTestBatch({
    required List<(String id, String xrayConfig)> items,
    required int socksPort,
    String downloadUrl = kDefaultSpeedTestUrl,
    int timeoutMs = 20000,
  }) async {
    if (items.isEmpty) return [];
    return EphemeralXrayPing.speedTestBatch(
      items: items.map((e) => (id: e.$1, xrayConfigJson: e.$2)).toList(),
      socksPort: socksPort,
      downloadUrl: downloadUrl,
      timeoutMs: timeoutMs,
    );
  }

  void _pipeProcessOutput(Process process, StringBuffer buffer, String tag) {
    // just buffer for the debug log screen. logging per line here janks the ui
    // on connect, since xray/sing-box spam lines and developer.log runs on the ui isolate.
    void append(String line) {
      buffer.writeln(line);
      // keep only the tail so the buffer doesn't grow unbounded
      if (buffer.length > 64 * 1024) {
        final trimmed = _tail(buffer, maxLines: 200);
        buffer
          ..clear()
          ..writeln(trimmed);
      }
    }

    void handle(String chunk) {
      for (final line in const LineSplitter().convert(chunk)) {
        append(line);
      }
    }

    process.stderr.transform(utf8.decoder).listen(handle);
    process.stdout.transform(utf8.decoder).listen(handle);
  }

  Future<void> _killProcess(Process? process) async {
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
  }

  Future<bool> _waitForSingbox({
    required Process process,
    StringBuffer? log,
  }) async {
    var waited = 0;
    while (waited < 15000) {
      final code = await process.exitCode.timeout(
        const Duration(milliseconds: 1),
        onTimeout: () => -1,
      );
      if (code >= 0) {
        throw VpnStartException(
          'sing-box exited with code $code.\n${_tail(log ?? StringBuffer())}',
        );
      }
      final text = (log ?? StringBuffer()).toString().toLowerCase();
      if (text.contains('started') && text.contains('tun')) {
        return true;
      }
      if (text.contains('tun-in') &&
          (text.contains('started') || text.contains('listening'))) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      waited += 300;
    }
    // some builds never print "started", so a still-running process counts as ok
    final stillRunning = await process.exitCode.timeout(
      const Duration(milliseconds: 1),
      onTimeout: () => -1,
    );
    return stillRunning < 0;
  }

  Future<bool> _waitForPort(
    String host,
    int port, {
    Process? process,
    StringBuffer? log,
    String processLabel = 'Process',
  }) async {
    var waited = 0;
    while (waited < 20000) {
      if (process != null) {
        final code = await process.exitCode.timeout(
          const Duration(milliseconds: 1),
          onTimeout: () => -1,
        );
        if (code >= 0) {
          if (code != 0) {
            throw VpnStartException(
              '$processLabel exited with code $code.\n${_tail(log ?? StringBuffer())}',
            );
          }
          return false;
        }
      }
      try {
        final s = await Socket.connect(
          host,
          port,
          timeout: const Duration(milliseconds: 400),
        );
        await s.close();
        return true;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        waited += 300;
      }
    }
    return false;
  }

  String _tail(StringBuffer buffer, {int maxLines = 12}) {
    final lines = buffer.toString().split('\n').where((l) => l.trim().isNotEmpty);
    final tail = lines.length > maxLines
        ? lines.skip(lines.length - maxLines)
        : lines;
    final text = tail.join('\n');
    return text.isEmpty ? '(no process output)' : text;
  }

  /// true if we can bind the port, i.e. it's free
  Future<bool> _isPortAvailable(String host, int port) async {
    try {
      final serverSocket = await ServerSocket.bind(host, port);
      await serverSocket.close();
      return true;
    } catch (e) {
      AppLogger.instance.debug(
        'Port $host:$port not available: $e',
      );
      return false;
    }
  }

  void _emit(VpnState state) {
    if (!_stateCtrl.isClosed) _stateCtrl.add(state);
  }

  void _startStatsLoop(ConnectionMode mode) {
    _stopStatsLoop();
    _sessionStartedAt = DateTime.now();
    _prevInOctets = 0;
    _prevOutOctets = 0;
    _totalDownload = 0;
    _totalUpload = 0;
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_pollTrafficStats(mode));
    });
    unawaited(_pollTrafficStats(mode));
  }

  void _stopStatsLoop() {
    _statsTimer?.cancel();
    _statsTimer = null;
    _sessionStartedAt = null;
    _prevInOctets = 0;
    _prevOutOctets = 0;
    _totalDownload = 0;
    _totalUpload = 0;
  }

  Future<void> _pollTrafficStats(ConnectionMode mode) async {
    if (_xrayProcess == null && _wireproxyProcess == null) return;
    try {
      final int inOctets;
      final int outOctets;

      if (_wireproxyProcess != null && _awgInfoPort != null && mode == ConnectionMode.proxy) {
        // AmneziaWG proxy: кумулятивные rx/tx из wireproxy /metrics.
        final m = await _queryWireproxyMetrics(_awgInfoPort!);
        if (m == null) {
          // метрики недоступны — хотя бы тикаем длительность сессии
          _emitConnectedTelemetry(mode);
          return;
        }
        inOctets = m.rx;
        outOctets = m.tx;
      } else if (mode == ConnectionMode.proxy && _xrayProcess != null) {
        final xrayBin = _xrayBinPath;
        if (xrayBin == null) return;
        final counters = await XraySessionStats.queryInboundCounters(
          xrayExecutable: xrayBin,
        );
        if (counters == null) return;
        inOctets = counters.download;
        outOctets = counters.upload;
      } else if (mode == ConnectionMode.tun) {
        final result = await _method.invokeMethod<Map<Object?, Object?>>(
          'getTrafficStats',
          {'mode': 'tun'},
        );
        if (result == null || result['ok'] != true) return;
        inOctets = (result['inOctets'] as num?)?.toInt() ?? 0;
        outOctets = (result['outOctets'] as num?)?.toInt() ?? 0;
      } else {
        return;
      }

      if (_prevInOctets == 0 && _prevOutOctets == 0) {
        _prevInOctets = inOctets;
        _prevOutOctets = outOctets;
        _emitConnectedTelemetry(mode);
        return;
      }

      final deltaIn =
          inOctets >= _prevInOctets ? inOctets - _prevInOctets : 0;
      final deltaOut =
          outOctets >= _prevOutOctets ? outOctets - _prevOutOctets : 0;
      _prevInOctets = inOctets;
      _prevOutOctets = outOctets;
      _totalDownload += deltaIn;
      _totalUpload += deltaOut;

      _emitConnectedTelemetry(
        mode,
        downloadSpeed: deltaIn,
        uploadSpeed: deltaOut,
      );
    } catch (e) {
      AppLogger.instance.debug('getTrafficStats failed: $e');
    }
  }

  /// Читает кумулятивные rx/tx из wireproxy `/metrics` (UAPI dump).
  /// rx_bytes = принято (download), tx_bytes = отправлено (upload), сумма по пирам.
  Future<({int rx, int tx})?> _queryWireproxyMetrics(int port) async {
    final client = HttpClient();
    try {
      final req = await client
          .get('127.0.0.1', port, '/metrics')
          .timeout(const Duration(seconds: 2));
      final resp = await req.close().timeout(const Duration(seconds: 2));
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join();
      var rx = 0;
      var tx = 0;
      for (final line in const LineSplitter().convert(body)) {
        final i = line.indexOf('=');
        if (i < 0) continue;
        final key = line.substring(0, i).trim();
        final value = int.tryParse(line.substring(i + 1).trim());
        if (value == null) continue;
        if (key == 'rx_bytes') {
          rx += value;
        } else if (key == 'tx_bytes') {
          tx += value;
        }
      }
      return (rx: rx, tx: tx);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  void _emitConnectedTelemetry(
    ConnectionMode? mode, {
    int? downloadSpeed,
    int? uploadSpeed,
  }) {
    _emit(_buildConnectedState(
      mode,
      downloadSpeed: downloadSpeed,
      uploadSpeed: uploadSpeed,
    ));
  }

  VpnState _buildConnectedState(
    ConnectionMode? mode, {
    int? downloadSpeed,
    int? uploadSpeed,
  }) {
    final started = _sessionStartedAt;
    return VpnState(
      status: VpnStatus.connected,
      activeMode: mode,
      downloadSpeed: downloadSpeed,
      uploadSpeed: uploadSpeed,
      totalDownload: _totalDownload > 0 ? _totalDownload : null,
      totalUpload: _totalUpload > 0 ? _totalUpload : null,
      duration: started != null ? DateTime.now().difference(started) : null,
    );
  }

  Future<void> _logProxyProbesInBackground(int httpPort) async {
    try {
      final localProbe = await _probeLocalHttpProxy(httpPort);
      await _proxyDebugLogViaChannel('Background local HTTP probe: $localProbe');
      final result = await _method.invokeMethod<Map<Object?, Object?>>(
        'testSystemProxyHttp',
      );
      final winInet = result?['winInet'];
      final winHttp = result?['winHttp'];
      AppLogger.instance.info(
        'System proxy probes (background): winInet=$winInet winHttp=$winHttp',
      );
      await _proxyDebugLogViaChannel(
        'Background OS probes: winInet=$winInet winHttp=$winHttp '
        '(204=system proxy works like Chrome)',
      );
      if (winInet != 204 && winHttp != 204) {
        AppLogger.instance.warn(
          'System proxy registry is set but OS HTTP probes did not return 204. '
          'Fully quit and restart the browser. Firefox: enable system proxy.',
        );
      }
    } catch (e) {
      AppLogger.instance.debug('Background proxy probes failed: $e');
    }
  }

  Future<void> _applyFirefoxProxyAfterConnect(int httpPort) async {
    try {
      final profiles = await FirefoxProxyHelper.applyManualHttpProxy(httpPort);
      if (profiles.isNotEmpty) {
        await _proxyDebugLogViaChannel(
          'Firefox user.js updated (${profiles.length} profile(s)): '
          'HTTP 127.0.0.1:$httpPort. Restart Firefox.',
        );
      }
    } catch (e, st) {
      AppLogger.instance.warn(
        'Firefox proxy update failed',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<String> _probeLocalHttpProxy(int httpPort) async {
    final client = HttpClient();
    try {
      client.findProxy = (uri) => 'PROXY 127.0.0.1:$httpPort';
      final request = await client
          .getUrl(
            Uri.parse('http://connectivitycheck.gstatic.com/generate_204'),
          )
          .timeout(const Duration(seconds: 10));
      final response =
          await request.close().timeout(const Duration(seconds: 10));
      final body = await response.toList();
      return 'status=${response.statusCode} bytes=${body.length}';
    } catch (e) {
      return 'FAILED ($e) — Xray HTTP inbound on 127.0.0.1:$httpPort may be down '
          'or routing blocks the test URL';
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _proxyDebugLogViaChannel(String message) async {
    try {
      await _method.invokeMethod<void>('appendProxyDebugLog', {
        'message': message,
      });
    } catch (_) {}
  }

  Future<void> _appendProxyDebugLogs(String reason) async {
    try {
      final path = await DebugLogService.getProxyDebugLogPath();
      final logs = await DebugLogService.getProxyDebugLogs(maxLines: 200);
      AppLogger.instance.error(
        'Proxy debug ($reason)\nFile: $path\n$logs',
      );
    } catch (e) {
      AppLogger.instance.warn('Proxy debug logs unavailable: $e');
    }
  }

  /// Accepts `127.0.0.1:2081` or `http=127.0.0.1:2081;https=127.0.0.1:2081;...`.
  static bool _registryProxyMatchesHttp(String registryServer, int httpPort) {
    if (registryServer.isEmpty) return false;
    final hostPort = '127.0.0.1:$httpPort';
    if (registryServer == hostPort) return true;
    return registryServer.contains('http=$hostPort') &&
        registryServer.contains('https=$hostPort');
  }
}
