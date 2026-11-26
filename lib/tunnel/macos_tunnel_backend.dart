import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/app_logger.dart';
import '../core/exceptions.dart';
import '../platform/vpn_native_bridge.dart';
import '../services/macos_tun_service.dart';
import '../services/xray_route_decisions.dart';
import '../utils/desktop_tun.dart';
import '../utils/macos_app_bundle.dart';
import '../utils/mihomo_api_session.dart';
import '../utils/xray_session_log.dart';
import 'connection_mode.dart';
import 'desktop_core_session.dart';
import 'desktop_traffic_stats.dart';
import 'local_proxy_probe.dart';
import 'macos_core_paths.dart';
import 'macos_elevation.dart';
import 'macos_system_proxy.dart';
import 'mihomo_hot_reload.dart';
import 'mihomo_tun_ready.dart';
import 'socks_credential_generator.dart';
import 'tun_failure_hints.dart';
import 'tunnel_backend.dart';
import 'tunnel_session_request.dart';
import 'tunnel_state.dart';
import 'vpn_backend.dart';
import 'xray_desktop_config.dart';

class MacosTunnelBackend
    with DesktopTrafficStats, DesktopCoreSession
    implements TunnelBackend {
  static const tunInterfaceName = kMacosTunInterfaceName;
  static const coresLogName = 'keqdroid_cores.log';
  static const _tunStartBudgetMs = 20000;

  static MacosTunnelBackend? activeInstance;
  static String lastSessionLogs = '';

  final _stateCtrl = StreamController<VpnState>.broadcast();
  final StringBuffer _xrayLog = StringBuffer();

  Process? _xrayProcess;
  Process? _mihomoProcess;
  Directory? _sessionDir;
  ConnectionMode? _activeMode;
  int? _xrayMetricsPort;
  bool _viaService = false;
  bool _systemProxyApplied = false;
  Future<void>? _coreOutputDone;

  @override
  ConnectionMode? get activeMode => _activeMode;

  int? get clashApiPort =>
      _mihomoProcess != null ? MihomoApiSession().port : null;

  String get clashApiSecret => MihomoApiSession().secret;

  Map<String, int> get activeCorePids => {
    if (_mihomoProcess != null) 'mihomo': _mihomoProcess!.pid,
    if (_xrayProcess != null) 'xray': _xrayProcess!.pid,
  };

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

  String exportSessionLogs({int maxLines = 400}) =>
      coreLogTail(_xrayLog, maxLines: maxLines);

  String _sessionLogTail({int maxLines = 10}) {
    final text = exportSessionLogs(maxLines: maxLines).trim();
    return text == '(no process output)' ? '' : text;
  }

  Future<void> _dumpLogsToFile(String logs) async {
    try {
      final dir = (await getApplicationSupportDirectory()).path;
      final path = p.join(dir, coresLogName);
      await File(path).writeAsString(logs);
      await Process.run('/bin/chmod', ['600', path]);
    } catch (e) {
      AppLogger.instance.debug('Core logs not written', error: e);
    }
  }

  @override
  Future<({String username, String password})?>
  fetchActiveSocksCredentials() async => null;

  @override
  Future<({String username, String password})> fetchSocksCredentials() async =>
      SocksCredentialGenerator.generatePair();

  @override
  Future<void> startSession(TunnelSessionRequest request) async {
    emit(VpnState(status: VpnStatus.connecting, activeMode: request.mode));
    _activeMode = request.mode;
    _xrayLog.clear();
    connectionLines.clear();
    XrayRouteDecisions.reset();

    try {
      await cleanupForRestart();
      activeInstance = this;
      _activeMode = request.mode;

      _viaService = false;
      if (request.mode == ConnectionMode.tun && !macosRunningAsRoot()) {
        if (await MacosTunService.state() != TunServiceState.ready) {
          throw const VpnStartException(
            'TUN mode needs administrator rights: the utun interface and the '
            'system route table cannot be set up without them. Turn TUN on '
            'again in the app to install the keqdroid service, or use Proxy '
            'mode.',
          );
        }
        _viaService = true;
      }

      if (request.mode == ConnectionMode.tun && await _tunInterfaceExists()) {
        throw VpnStartException(
          'The macOS interface $tunInterfaceName already exists. Disconnect '
          'the other tunnel or wait for the previous keqdroid core to stop.',
        );
      }

      _sessionDir = await MacosCorePaths.sessionDir();

      switch (request.vpnBackend) {
        case VpnBackend.mihomo:
          await _startMihomoSession(request);
        case VpnBackend.xray:
          await _startXraySession(request);
      }

      startStatsLoop(request.mode);
      emitConnectedTelemetry(request.mode);

      unawaited(_verifyChainReachable(request));

      watchCoreExit(_mihomoProcess, 'mihomo');
      watchCoreExit(_xrayProcess, 'xray');
    } catch (e, st) {
      AppLogger.instance.error(
        'macOS tunnel start failed',
        error: e,
        stackTrace: st,
      );
      await cleanupForRestart();
      emit(
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
    final isTun = request.mode == ConnectionMode.tun;
    final bin = _viaService && isTun
        ? MacosCorePaths.bundledCorePath('xray')
        : await MacosCorePaths.xrayExecutable();
    if (bin == null) {
      throw VpnStartException('xray not found. ${MacosCorePaths.binariesHint}');
    }

    await ensureLocalPortsFree(request);

    final metricsPort = await freeLoopbackPort();
    final xrayLog = XraySessionLog.raise(request.xrayConfig);
    xrayLogThreshold = xrayLog.threshold;
    final sessionConfig = withXrayDesktopSession(
      xrayLog.config,
      metricsPort: metricsPort,
      processLog: !isTun && request.processLog,
      tunName: isTun ? tunInterfaceName : null,
    );
    final configFile = File(p.join(_sessionDir!.path, 'xray.json'));
    await configFile.writeAsString(sessionConfig);
    _xrayMetricsPort = metricsPort;
    xrayStarted = false;

    final geoDir = await MacosCorePaths.geoAssetDir();
    if (_viaService && isTun) {
      _xrayProcess = await MacosTunService.startCore(
        kind: 'xray',
        config: MacosTunService.xrayForService(sessionConfig),
        geoDir: geoDir,
      );
    } else {
      _xrayProcess = await Process.start(
        bin,
        ['run', '-c', configFile.path],
        workingDirectory: _sessionDir!.path,
        environment: {'XRAY_LOCATION_ASSET': ?geoDir, kXrayStopOnStdinEof: '1'},
        mode: ProcessStartMode.normal,
      );
    }
    _coreOutputDone = _pipeProcessOutput(_xrayProcess!);

    if (isTun) {
      final ready = await _waitForXrayTun(_xrayProcess!);
      if (!ready) throw VpnStartException(_tunStartError(_xrayLog));
      return;
    }

    final socksReady = await waitForLocalPort(
      request.socksPort,
      process: _xrayProcess,
      log: _xrayLog,
      processLabel: 'xray',
    );
    if (!socksReady) {
      throw VpnStartException(
        'xray SOCKS port ${request.socksPort} did not open.\n'
        '${coreLogTail(_xrayLog)}',
      );
    }

    if (request.systemProxy) {
      final httpReady = await waitForLocalPort(
        request.httpPort,
        process: _xrayProcess,
        log: _xrayLog,
        processLabel: 'xray HTTP',
      );
      if (!httpReady) {
        throw VpnStartException(
          'xray HTTP port ${request.httpPort} did not open. '
          'System proxy needs the HTTP inbound.\n${coreLogTail(_xrayLog)}',
        );
      }
      await _applySystemProxy(request);
    }
  }

  Future<void> _startMihomoSession(TunnelSessionRequest request) async {
    final isTun = request.mode == ConnectionMode.tun;
    final bin = _viaService && isTun
        ? MacosCorePaths.bundledCorePath('mihomo')
        : await MacosCorePaths.mihomoExecutable();
    if (bin == null) {
      throw VpnStartException(
        'mihomo not found. ${MacosCorePaths.binariesHint}',
      );
    }
    final config = request.mihomoConfig;
    if (config == null || config.isEmpty) {
      throw const VpnStartException('mihomoConfig is required for mihomo');
    }

    await ensureLocalPortsFree(request);

    final configFile = File(p.join(_sessionDir!.path, 'mihomo.yaml'));
    await configFile.writeAsString(config);

    if (_viaService && isTun) {
      _mihomoProcess = await MacosTunService.startCore(
        kind: 'mihomo',
        config: config,
        geoDir: await MacosCorePaths.geoAssetDir(),
      );
    } else {
      _mihomoProcess = await Process.start(
        bin,
        ['-d', await MacosCorePaths.mihomoHomeDir(), '-f', configFile.path],
        workingDirectory: _sessionDir!.path,
        mode: ProcessStartMode.normal,
      );
    }
    _coreOutputDone = _pipeProcessOutput(_mihomoProcess!);

    if (isTun) {
      final ready = await _waitForMihomoTun(
        process: _mihomoProcess!,
        log: _xrayLog,
      );
      if (!ready) {
        throw VpnStartException(_tunStartError(_xrayLog, core: 'mihomo'));
      }
      return;
    }

    final socksReady = await waitForLocalPort(
      request.socksPort,
      process: _mihomoProcess,
      log: _xrayLog,
      processLabel: 'mihomo',
    );
    if (!socksReady) {
      throw VpnStartException(
        'mihomo SOCKS port ${request.socksPort} did not open.\n'
        '${coreLogTail(_xrayLog)}',
      );
    }

    if (request.systemProxy) {
      final httpReady = await waitForLocalPort(
        request.httpPort,
        process: _mihomoProcess,
        log: _xrayLog,
        processLabel: 'mihomo HTTP',
      );
      if (!httpReady) {
        throw VpnStartException(
          'mihomo HTTP port ${request.httpPort} did not open. '
          'System proxy needs the HTTP inbound.\n${coreLogTail(_xrayLog)}',
        );
      }
      await _applySystemProxy(request);
    }
  }

  Future<void> _pipeProcessOutput(Process process) => Future.wait([
    for (final lines in listenCoreOutput(process, _xrayLog))
      lines.asFuture<void>().catchError((Object _) {}),
  ]);

  Future<void> _coreOutputDrained() async {
    await _coreOutputDone?.timeout(
      const Duration(seconds: 2),
      onTimeout: () {},
    );
  }

  Future<bool> _waitForXrayTun(Process process) async {
    var waited = 0;
    while (waited < _tunStartBudgetMs) {
      final code = await exitCodeOrNull(process);
      if (code != null) {
        await _coreOutputDrained();
        throw VpnStartException(
          'xray exited with code $code before the tunnel came up.\n'
          '${_tunStartError(_xrayLog)}',
        );
      }
      if (xrayStarted) return true;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      waited += 250;
    }
    return false;
  }

  Future<bool> _waitForMihomoTun({
    required Process process,
    required StringBuffer log,
  }) async {
    final api = MihomoApiSession();
    final clock = Stopwatch()..start();
    while (clock.elapsedMilliseconds < _tunStartBudgetMs) {
      final code = await exitCodeOrNull(process);
      if (code != null) {
        await _coreOutputDrained();
        throw VpnStartException(
          'mihomo exited with code $code before the tunnel came up.\n'
          '${_tunStartError(log, core: 'mihomo')}',
        );
      }
      final port = api.port;
      final state = mihomoTunState(
        coreOutput: log.toString(),
        configs: port == null
            ? null
            : await fetchMihomoConfigs(port, api.secret),
      );
      if (state != MihomoTunState.pending) return state == MihomoTunState.up;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }

  String _tunStartError(StringBuffer log, {String core = 'xray'}) =>
      tunStartFailureMessage(
        fallback: 'The $core TUN tunnel did not start.',
        coreOutput: log.toString(),
        windows: false,
        macos: true,
        tail: coreLogTail(log),
      );

  Future<bool> _tunInterfaceExists() async {
    try {
      final r = await Process.run('/sbin/ifconfig', [tunInterfaceName]);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> _awaitTunInterfaceGone() async {
    const budgetMs = 4000;
    var waited = 0;
    while (waited < budgetMs && await _tunInterfaceExists()) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      waited += 150;
    }
  }

  Future<void> _verifyChainReachable(TunnelSessionRequest request) async {
    await Future<void>.delayed(const Duration(seconds: 3));
    if (_activeMode == null) return;
    final result = await probeLocalHttpProxy(request.httpPort);
    if (probeWentThrough(result)) return;
    final outcome = result.status != null
        ? 'status=${result.status}'
        : 'failed (${result.error})';
    if (_activeMode == null) return;
    AppLogger.instance.warn(
      'The tunnel is up, but a test request through the core did not go '
      'through ($outcome). Nothing will load until this is fixed — the usual '
      'reasons are an unreachable or expired server, wrong server settings, or '
      'a routing rule that blocks the test address.',
    );
  }

  Future<void> _applySystemProxy(TunnelSessionRequest request) async {
    _systemProxyApplied = true;
    final ok = await (await MacosSystemProxy.system()).enable(
      httpPort: request.httpPort,
      socksPort: request.socksPort,
    );
    if (!ok) {
      AppLogger.instance.warn(
        'Could not set the macOS system proxy via networksetup. '
        'The local proxy is up on 127.0.0.1: '
        'SOCKS ${request.socksPort} / HTTP ${request.httpPort}.',
      );
    }
  }

  static Future<void> _restoreSystemProxy() async {
    try {
      await (await MacosSystemProxy.system()).disable();
    } catch (e) {
      AppLogger.instance.warn('Could not restore the system proxy', error: e);
    }
  }

  static Future<void> cleanupStaleState() => _restoreSystemProxy();

  @override
  Iterable<Process?> get sessionCores => [_mihomoProcess, _xrayProcess];

  @override
  String? coreExitHint(String coreOutput) =>
      tunFailureHint(coreOutput, windows: false, macos: true)?.message;

  @override
  String coreExitDetails() {
    final details = _sessionLogTail();
    final hint = coreExitHint(exportSessionLogs());
    return '${hint == null ? '' : '\n$hint'}'
        '${details.isEmpty ? '' : '\n$details'}';
  }

  @override
  Future<bool> reloadMihomoConfig(TunnelSessionRequest request) async {
    final config = request.mihomoConfig;
    final dir = _sessionDir;
    final api = MihomoApiSession();
    final port = api.port;
    if (_mihomoProcess == null ||
        stoppingSession ||
        dir == null ||
        port == null ||
        config == null ||
        config.isEmpty ||
        request.mode != _activeMode) {
      return false;
    }
    if (!await putMihomoConfig(
      port: port,
      secret: api.secret,
      config: config,
    )) {
      return false;
    }
    await File(p.join(dir.path, 'mihomo.yaml')).writeAsString(config);
    return true;
  }

  @override
  Future<void> stopSessionInner({bool emitStates = true}) async {
    final wasTun = _activeMode == ConnectionMode.tun;
    stopStatsLoop();
    final logs = exportSessionLogs(maxLines: 2000);
    if (logs.trim().isNotEmpty && logs.trim() != '(no process output)') {
      lastSessionLogs = logs;
      unawaited(_dumpLogsToFile(logs));
    }
    if (emitStates) emit(const VpnState(status: VpnStatus.disconnecting));

    if (_systemProxyApplied) {
      await _restoreSystemProxy();
      _systemProxyApplied = false;
    }

    await stopCoreProcess(_xrayProcess, graceful: true);
    await stopCoreProcess(_mihomoProcess, graceful: true);
    _xrayProcess = null;
    _mihomoProcess = null;
    _xrayMetricsPort = null;
    _coreOutputDone = null;

    if (wasTun) await _awaitTunInterfaceGone();

    final dir = _sessionDir;
    _sessionDir = null;
    await deleteSessionDir(dir);

    _activeMode = null;
    if (identical(activeInstance, this)) activeInstance = null;
    if (emitStates) emit(VpnState.disconnected);
  }

  @override
  Future<bool> requestTunnelPermission() async => macosRunningAsRoot();

  @override
  Future<VpnState> getCurrentState() async {
    if (_xrayProcess != null || _mihomoProcess != null) {
      return buildConnectedState(_activeMode);
    }
    return VpnState.disconnected;
  }

  @override
  Future<List<Map<String, dynamic>>> getInstalledApps({
    bool includeSystem = false,
  }) async {
    final seen = <String>{};
    final apps = <Map<String, dynamic>>[];

    final home = Platform.environment['HOME'];
    final appDirs = <String>[
      '/Applications',
      '/Applications/Utilities',
      if (home != null && home.isNotEmpty) p.join(home, 'Applications'),
      if (includeSystem) '/System/Applications',
      if (includeSystem) '/System/Applications/Utilities',
    ];

    final bundleEntries = <({String path, bool isSystem})>[];
    for (final root in appDirs) {
      final dir = Directory(root);
      if (!dir.existsSync()) continue;
      final isSystem = root.startsWith('/System');
      try {
        await for (final entity in dir.list(followLinks: false)) {
          if (!entity.path.endsWith('.app')) continue;
          bundleEntries.add((path: entity.path, isSystem: isSystem));
        }
      } catch (e) {
        AppLogger.instance.debug('Could not scan $root', error: e);
      }
    }

    const batchSize = 8;
    for (var i = 0; i < bundleEntries.length; i += batchSize) {
      final end = (i + batchSize < bundleEntries.length)
          ? i + batchSize
          : bundleEntries.length;
      final batch = bundleEntries.sublist(i, end);
      final exeNames = await Future.wait(
        batch.map((e) => MacosAppBundle.executableName(e.path)),
      );
      for (var j = 0; j < batch.length; j++) {
        final entry = batch[j];
        final displayName = p.basenameWithoutExtension(entry.path);
        final exeName = exeNames[j] ?? displayName;
        if (exeName.isEmpty || !seen.add(exeName.toLowerCase())) continue;
        apps.add({
          'packageName': exeName,
          'appName': displayName,
          'isRunning': false,
          'isSystem': entry.isSystem,
          'installPath': entry.path,
        });
      }
    }

    try {
      final r = await Process.run('/bin/ps', const ['-axo', 'comm=']);
      if (r.exitCode == 0) {
        final runningLower = <String>{};
        for (final raw in '${r.stdout}'.split('\n')) {
          final comm = raw.trim();
          if (comm.isEmpty) continue;
          final base = p.basename(comm);
          if (base.isEmpty) continue;
          runningLower.add(base.toLowerCase());
          if (includeSystem && seen.add(base.toLowerCase())) {
            apps.add({
              'packageName': base,
              'appName': base,
              'isRunning': true,
              'isSystem': true,
              'installPath': comm,
            });
          }
        }
        for (final app in apps) {
          final pkg = (app['packageName'] as String).toLowerCase();
          if (runningLower.contains(pkg)) app['isRunning'] = true;
        }
      }
    } catch (e) {
      AppLogger.instance.debug('ps failed when listing apps', error: e);
    }

    apps.sort(
      (a, b) => (a['appName'] as String).toLowerCase().compareTo(
        (b['appName'] as String).toLowerCase(),
      ),
    );
    return apps;
  }

  @override
  Future<String?> getAppIcon(String path) async {
    if (path.isEmpty) return null;
    try {
      return await VpnNativeBridge.channel.invokeMethod<String>('getAppIcon', {
        'path': path,
      });
    } catch (_) {
      return null;
    }
  }

  @override
  void emit(VpnState state) {
    if (!_stateCtrl.isClosed) _stateCtrl.add(state);
  }

  @override
  Future<({int down, int up})?> sessionTrafficCounters() async {
    if (_mihomoProcess != null) {
      final api = MihomoApiSession();
      final port = api.port;
      return port == null ? null : queryClashTraffic(port, secret: api.secret);
    }
    final port = _xrayMetricsPort;
    if (_xrayProcess == null || port == null) return null;
    return queryXrayTraffic(port);
  }

  @override
  Future<void> pollTrafficStats(
    ConnectionMode mode, {
    bool force = false,
  }) async {
    if (!statsPollingEnabled && !force) return;
    if (_xrayProcess == null && _mihomoProcess == null) return;
    try {
      final counters = await sessionTrafficCounters();
      if (counters == null) {
        emitConnectedTelemetry(mode);
        return;
      }
      final inOctets = counters.down;
      final outOctets = counters.up;

      if (!statsBaselineTaken) {
        statsBaselineTaken = true;
        prevInOctets = inOctets;
        prevOutOctets = outOctets;
        resumeBaselinePending = false;
        emitConnectedTelemetry(mode);
        return;
      }

      final deltaIn = inOctets >= prevInOctets ? inOctets - prevInOctets : 0;
      final deltaOut = outOctets >= prevOutOctets
          ? outOctets - prevOutOctets
          : 0;
      prevInOctets = inOctets;
      prevOutOctets = outOctets;
      totalDownload += deltaIn;
      totalUpload += deltaOut;

      final suppressSpeed = resumeBaselinePending;
      resumeBaselinePending = false;
      emitConnectedTelemetry(
        mode,
        downloadSpeed: suppressSpeed ? null : deltaIn,
        uploadSpeed: suppressSpeed ? null : deltaOut,
      );
    } catch (e) {
      AppLogger.instance.debug('macOS getTrafficStats failed: $e');
    }
  }
}
