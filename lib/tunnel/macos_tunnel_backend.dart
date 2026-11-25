import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/app_logger.dart';
import '../core/exceptions.dart';
import '../platform/vpn_native_bridge.dart';
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

  static const _runRootDir = '/var/run/keqdroid';
  static const _rootXrayName = 'keqdroid-xray';
  static const coresLogName = 'keqdroid_cores.log';

  static String get _rootRunDir => '$_runRootDir/${macosRealUid()}';
  String get _coreLogPath => p.join(_rootRunDir, 'core.log');

  DateTime? _rootCoreLaunchedAt;

  static MacosTunnelBackend? activeInstance;

  final _stateCtrl = StreamController<VpnState>.broadcast();

  Process? _xrayProcess;
  Process? _rootXrayProcess;
  Process? _mihomoProcess;
  bool _mihomoRunsAsRoot = false;
  File? _rootSentinel;
  Directory? _sessionDir;
  ConnectionMode? _activeMode;
  int? _xrayMetricsPort;

  final StringBuffer _xrayLog = StringBuffer();
  final StringBuffer _rootLog = StringBuffer();

  Timer? _rootLogTimer;
  int _rootLogOffset = 0;
  String _rootLogPending = '';
  bool _rootLogReading = false;

  @override
  ConnectionMode? get activeMode => _activeMode;

  int? get clashApiPort =>
      _mihomoProcess != null ? MihomoApiSession().port : null;

  String get clashApiSecret => MihomoApiSession().secret;

  Map<String, int> get activeCorePids => {
    if (_xrayProcess != null) 'xray': _xrayProcess!.pid,
    if (_mihomoProcess != null)
      _mihomoRunsAsRoot ? 'mihomo (root, TUN)' : 'mihomo': _mihomoProcess!.pid,
    if (_rootXrayProcess != null) 'xray (root, TUN)': _rootXrayProcess!.pid,
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

  String exportSessionLogs({int maxLines = 400}) {
    final combined = StringBuffer()
      ..writeln('=== core ===')
      ..writeln(_xrayLog)
      ..writeln('=== root ===')
      ..writeln(_rootLog);
    return coreLogTail(combined, maxLines: maxLines);
  }

  Future<void> _dumpLogsToFile() async {
    try {
      final dir = (await getApplicationSupportDirectory()).path;
      final path = p.join(dir, coresLogName);
      await File(path).writeAsString(exportSessionLogs(maxLines: 2000));
      await Process.run('/bin/chmod', ['600', path]);
      AppLogger.instance.info('Core logs written to $path');
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
    _rootLog.clear();
    connectionLines.clear();
    XrayRouteDecisions.reset();

    try {
      await cleanupForRestart();
      activeInstance = this;
      _activeMode = request.mode;
      _sessionDir = await MacosCorePaths.sessionDir();

      final isTun = request.mode == ConnectionMode.tun;
      switch (request.vpnBackend) {
        case VpnBackend.mihomo:
          await _startMihomoSession(request);
        case VpnBackend.xray:
          await (isTun
              ? _startXrayTunSession(request)
              : _startXrayProxySession(request));
      }

      startStatsLoop(request.mode);
      emitConnectedTelemetry(request.mode);

      unawaited(_verifyChainReachable(request));

      watchCoreExit(_xrayProcess, 'xray');
      watchCoreExit(_mihomoProcess, 'mihomo');
      watchCoreExit(_rootXrayProcess, 'xray TUN');
    } catch (e, st) {
      AppLogger.instance.error(
        'macOS tunnel start failed',
        error: e,
        stackTrace: st,
      );
      await _dumpLogsToFile();
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

  Future<void> _startXrayProxySession(TunnelSessionRequest request) async {
    final bin = await MacosCorePaths.xrayExecutable();
    if (bin == null) {
      throw VpnStartException('xray not found. ${MacosCorePaths.binariesHint}');
    }

    final metricsPort = await freeLoopbackPort();
    final xrayLog = XraySessionLog.raise(request.xrayConfig);
    xrayLogThreshold = xrayLog.threshold;
    final configFile = File(p.join(_sessionDir!.path, 'xray.json'));
    await configFile.writeAsString(
      withXrayDesktopSession(
        xrayLog.config,
        metricsPort: metricsPort,
        processLog: request.debugMode,
      ),
    );
    _xrayMetricsPort = metricsPort;

    await ensureLocalPortsFree(request);

    final geoDir = await MacosCorePaths.geoAssetDir();
    _xrayProcess = await Process.start(
      bin,
      ['run', '-c', configFile.path],
      workingDirectory: _sessionDir!.path,
      environment: {'XRAY_LOCATION_ASSET': ?geoDir},
      mode: ProcessStartMode.normal,
    );
    listenCoreOutput(_xrayProcess!, _xrayLog);

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

  Future<void> _startXrayTunSession(TunnelSessionRequest request) async {
    await ensureLocalPortsFree(request);

    final metricsPort = await freeLoopbackPort();
    final xrayLog = XraySessionLog.raise(request.xrayConfig);
    xrayLogThreshold = xrayLog.threshold;
    _xrayMetricsPort = metricsPort;
    await _runXrayAsRoot(
      withXrayDesktopSession(
        xrayLog.config,
        metricsPort: metricsPort,
        tunName: tunInterfaceName,
      ),
    );
  }

  Future<void> _startMihomoSession(TunnelSessionRequest request) async {
    final bin = await MacosCorePaths.mihomoExecutable();
    if (bin == null) {
      throw VpnStartException(
        'mihomo not found. ${MacosCorePaths.binariesHint}',
      );
    }
    final config = request.mihomoConfig;
    if (config == null || config.isEmpty) {
      throw const VpnStartException('mihomoConfig is required for mihomo');
    }

    final isTun = request.mode == ConnectionMode.tun;
    await ensureLocalPortsFree(request);

    final configFile = File(p.join(_sessionDir!.path, 'mihomo.yaml'));
    await configFile.writeAsString(config);

    if (isTun) {
      _mihomoRunsAsRoot = true;
      final home = await _stageGeoAssetsForRoot() ?? _sessionDir!.path;
      final rootBin = await _stageBinaryForRoot(bin, 'mihomo');

      _mihomoProcess = await _startElevatedCore(
        binPath: rootBin,
        configPath: configFile.path,
        geoOrHomeDir: home,
        kind: 'mihomo',
        label: 'mihomo',
        log: _rootLog,
        onStarted: (proc) => _mihomoProcess = proc,
      );

      final ready = await _waitForTunCore(
        process: _mihomoProcess!,
        log: _rootLog,
      );
      final coreLog = await _readRootCoreLog();
      if (coreLog.trim().isNotEmpty) {
        _rootLog
          ..writeln('=== mihomo (core) ===')
          ..writeln(coreLog);
      }
      if (!ready) {
        final tail = coreLog.trim().isEmpty
            ? coreLogTail(_rootLog)
            : coreLogTail(StringBuffer(coreLog));
        throw VpnStartException(
          tunStartFailureMessage(
            fallback: 'The mihomo TUN tunnel did not start.',
            coreOutput: coreLog.trim().isEmpty ? _rootLog.toString() : coreLog,
            windows: false,
            macos: true,
            tail: tail,
          ),
        );
      }
      return;
    }

    _mihomoRunsAsRoot = false;
    _mihomoProcess = await Process.start(
      bin,
      ['-d', await MacosCorePaths.mihomoHomeDir(), '-f', configFile.path],
      workingDirectory: _sessionDir!.path,
      mode: ProcessStartMode.normal,
    );
    listenCoreOutput(_mihomoProcess!, _xrayLog);

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

  // Конфиг пользователя исполняет ядро с правами root, поэтому без NOPASSWD-helper:
  // каждый запуск подтверждает администратор. Root пишет только в /var/run/keqdroid/<uid>.
  static const _tunWrapperBody =
      r'''PATH="/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/bin:/opt/homebrew/bin"; export PATH
umask 027
SB="$1"; CFG="$2"; GEO="$3"; SENT="$4"; APPPID="$5"; KIND="$6"; CALLER_UID="$7"
case "$KIND" in xray) EXT=json ;; mihomo) EXT=yaml ;; *) exit 5 ;; esac
case "$APPPID" in ''|*[!0-9]*) exit 5 ;; esac
OWNER="${SUDO_UID:-$CALLER_UID}"
[ -z "$OWNER" ] && OWNER=$(id -u)
case "$OWNER" in ''|*[!0-9]*) exit 5 ;; esac
as_owner() {
  if [ "$OWNER" = "0" ]; then
    "$@"
  else
    /usr/bin/sudo -u "#$OWNER" -- "$@"
  fi
}
RUN=/var/run/keqdroid/$OWNER
mkdir -p /var/run/keqdroid && rm -rf "$RUN" && mkdir -m 0755 "$RUN" "$RUN/home" || exit 5
LOGF=$RUN/core.log
: >"$LOGF" && chown "$OWNER" "$LOGF" && chmod 0600 "$LOGF" || exit 5
CONF=$RUN/config.$EXT
as_owner /bin/cat -- "$CFG" >"$CONF" && chmod 0600 "$CONF" || exit 5
for f in geoip.dat geosite.dat; do
  [ -n "$GEO" ] && as_owner test -f "$GEO/$f" && as_owner /bin/cat -- "$GEO/$f" >"$RUN/home/$f"
done
: >"$RUN/core.auth"
echo "[wrap mac v2] start KIND=$KIND app=$(kill -0 "$APPPID" 2>/dev/null && echo y || echo n)" >>"$LOGF"
if [ "$KIND" = mihomo ]; then
  set -- "$SB" -d "$RUN/home" -f "$CONF"
else
  set -- "$SB" run -c "$CONF"
fi
XRAY_LOCATION_ASSET="$RUN/home" "$@" >>"$LOGF" 2>&1 &
sb=$!
while [ -e "$SENT" ] && kill -0 "$APPPID" 2>/dev/null; do
  kill -0 "$sb" 2>/dev/null || break
  sleep 1
done
echo "[wrap mac v2] stop sent=$([ -e "$SENT" ] && echo y || echo n) app=$(kill -0 "$APPPID" 2>/dev/null && echo y || echo n) core=$(kill -0 "$sb" 2>/dev/null && echo y || echo n)" >>"$LOGF"
kill -TERM "$sb" 2>/dev/null
wait "$sb"
''';

  @visibleForTesting
  static String get tunWrapperBodyForTest => _tunWrapperBody;

  Future<void> _runXrayAsRoot(String config) async {
    final bin = await MacosCorePaths.xrayExecutable();
    if (bin == null) {
      throw VpnStartException(
        'xray not found (required for TUN mode). ${MacosCorePaths.binariesHint}',
      );
    }

    final configFile = File(p.join(_sessionDir!.path, 'xray-tun.json'));
    await configFile.writeAsString(config);
    final rootGeoDir = await _stageGeoAssetsForRoot();
    final rootBin = await _stageBinaryForRoot(bin, _rootXrayName);

    xrayStarted = false;
    _rootXrayProcess = await _startElevatedCore(
      binPath: rootBin,
      configPath: configFile.path,
      geoOrHomeDir: rootGeoDir ?? '',
      kind: 'xray',
      label: 'xray',
      log: _rootLog,
      onStarted: (proc) => _rootXrayProcess = proc,
    );
    _startRootLogTail();

    final ready = await _waitForTunCore(
      process: _rootXrayProcess!,
      log: _rootLog,
      started: () => xrayStarted,
    );

    if (!ready) {
      final coreLog = await _readRootCoreLog();
      final tail = coreLog.trim().isEmpty
          ? coreLogTail(_rootLog)
          : coreLogTail(StringBuffer(coreLog));
      throw VpnStartException(
        tunStartFailureMessage(
          fallback: 'The TUN tunnel did not start.',
          coreOutput: coreLog.trim().isEmpty ? _rootLog.toString() : coreLog,
          windows: false,
          macos: true,
          tail: tail,
        ),
      );
    }
  }

  void _startRootLogTail() {
    _stopRootLogTail();
    _rootLogOffset = 0;
    _rootLogPending = '';
    _rootLogTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => unawaited(_readRootLogTail()),
    );
  }

  void _stopRootLogTail() {
    _rootLogTimer?.cancel();
    _rootLogTimer = null;
  }

  Future<void> _readRootLogTail() async {
    final path = _coreLogPath;
    if (_rootLogReading || path.isEmpty) return;
    _rootLogReading = true;
    RandomAccessFile? file;
    try {
      final length = await File(path).length();
      if (length < _rootLogOffset) {
        _rootLogOffset = 0;
        _rootLogPending = '';
      }
      if (length == _rootLogOffset) return;
      file = await File(path).open();
      await file.setPosition(_rootLogOffset);
      final bytes = await file.read(length - _rootLogOffset);
      _rootLogOffset += bytes.length;
      final lines =
          (_rootLogPending +
                  const Utf8Decoder(allowMalformed: true).convert(bytes))
              .split('\n');
      _rootLogPending = lines.removeLast();
      for (final line in lines) {
        appendCoreLine(_xrayLog, line.trimRight());
      }
    } catch (_) {
    } finally {
      await file?.close();
      _rootLogReading = false;
    }
  }

  Future<String> _stageBinaryForRoot(String binPath, String name) async {
    final staged = p.join(_sessionDir!.path, name);
    try {
      await File(binPath).copy(staged);
      await Process.run('/bin/chmod', ['0755', staged]);
    } catch (e) {
      throw VpnStartException('Could not stage $name for elevation: $e');
    }
    return staged;
  }

  Future<String?> _stageGeoAssetsForRoot() async {
    final geoDir = await MacosCorePaths.geoAssetDir();
    if (geoDir == null) return null;

    final rootGeoDir = Directory(p.join(_sessionDir!.path, 'geo'));
    if (!rootGeoDir.existsSync()) rootGeoDir.createSync(recursive: true);

    var copied = false;
    for (final name in MacosCorePaths.geoFileNames) {
      final src = File(p.join(geoDir, name));
      if (!src.existsSync()) continue;
      await src.copy(p.join(rootGeoDir.path, name));
      copied = true;
    }
    return copied ? rootGeoDir.path : null;
  }

  Future<String> _readRootCoreLog() async {
    try {
      return await File(_coreLogPath).readAsString();
    } catch (_) {
      return '';
    }
  }

  Future<Process> _startElevatedCore({
    required String binPath,
    required String configPath,
    required String geoOrHomeDir,
    required String kind,
    required String label,
    required StringBuffer log,
    required void Function(Process) onStarted,
  }) async {
    // Чужой интерфейс с этим именем не должен стать признаком готовности.
    if (await _tunInterfaceExists()) {
      throw VpnStartException(
        'The macOS interface $tunInterfaceName already exists. Disconnect '
        'the other tunnel or wait for the previous keqdroid core to stop.',
      );
    }

    final sentinelFile = File(p.join(_sessionDir!.path, 'core.run'));
    await sentinelFile.writeAsString('1');
    _rootSentinel = sentinelFile;

    final authMarker = File(p.join(_rootRunDir, 'core.auth'));
    _rootCoreLaunchedAt = DateTime.now();

    final coreArgs = <String>[
      binPath,
      configPath,
      geoOrHomeDir,
      sentinelFile.path,
      '$pid',
      kind,
      '${macosRealUid()}',
    ];

    final wrapperFile = File(p.join(_sessionDir!.path, 'tun_wrap.sh'));
    await wrapperFile.writeAsString('#!/bin/sh\n$_tunWrapperBody');
    await Process.run('/bin/chmod', ['0700', wrapperFile.path]);

    final launch = planMacosElevation(
      coreArgs: coreArgs,
      wrapperScriptPath: wrapperFile.path,
      asRoot: macosRunningAsRoot(),
    );

    final Process process;
    try {
      process = await Process.start(
        launch.executable,
        launch.args,
        workingDirectory: _sessionDir!.path,
        mode: ProcessStartMode.normal,
      );
    } on ProcessException catch (e) {
      throw VpnStartException(
        'Could not launch $label with elevated privileges through '
        '${launch.executable}: ${e.message}',
      );
    }
    onStarted(process);
    listenCoreOutput(process, log);

    await _waitForElevation(process: process, authMarker: authMarker, log: log);
    return process;
  }

  Future<void> _waitForElevation({
    required Process process,
    required File authMarker,
    required StringBuffer log,
  }) async {
    const maxWait = Duration(minutes: 2);
    final sw = Stopwatch()..start();
    while (sw.elapsed < maxWait) {
      final code = await exitCodeOrNull(process);
      if (code != null) {
        throw VpnStartException(_elevationError(code, log));
      }
      if (_freshSince(authMarker, _rootCoreLaunchedAt)) return;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    try {
      process.kill(ProcessSignal.sigterm);
    } catch (_) {}
    throw const VpnStartException(
      'Administrator authorization timed out (2 min). Approve the password '
      'prompt to start TUN mode, or use Proxy mode.',
    );
  }

  Future<bool> _waitForTunCore({
    required Process process,
    required StringBuffer log,
    bool Function()? started,
  }) async {
    var waited = 0;
    while (waited < 20000) {
      final code = await exitCodeOrNull(process);
      if (code != null) {
        throw VpnStartException(_elevationError(code, log));
      }
      if (started != null) {
        if (started()) return true;
      } else if (await _tunInterfaceExists()) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      waited += 300;
    }
    if (await _tunInterfaceExists()) return true;

    final coreLog = await _readRootCoreLog();
    if (coreLog.trim().isNotEmpty) {
      log
        ..writeln('=== core log (timeout) ===')
        ..writeln(coreLog);
    }

    final stillRunning = await exitCodeOrNull(process);
    if (stillRunning != null) {
      throw VpnStartException(_elevationError(stillRunning, log));
    }
    return false;
  }

  String _elevationError(int code, StringBuffer log) {
    final text = log.toString().toLowerCase();
    if (text.contains('user canceled') || text.contains('-128')) {
      return 'Authorization cancelled. TUN mode needs administrator '
          'privileges — approve the password prompt, or use Proxy mode.';
    }
    var coreTail = '';
    try {
      final coreLog = File(_coreLogPath);
      final launchedAt = _rootCoreLaunchedAt;
      if (launchedAt != null &&
          !coreLog.lastModifiedSync().isBefore(launchedAt)) {
        coreTail = coreLog.readAsStringSync().trim();
      }
    } catch (_) {}
    final detail = coreTail.isNotEmpty
        ? coreLogTail(StringBuffer(coreTail))
        : coreLogTail(log);
    final hint = tunFailureHint(
      coreTail.isNotEmpty ? coreTail : log.toString(),
      windows: false,
      macos: true,
    );
    if (hint != null) {
      return 'The tunnel core exited with code $code.\n'
          '${hint.message}\n$detail';
    }
    return 'The tunnel core exited with code $code (TUN/elevation failed?).\n'
        '$detail';
  }

  static bool _freshSince(File file, DateTime? since) {
    try {
      if (!file.existsSync()) return false;
      if (since == null) return true;
      return !file.lastModifiedSync().isBefore(
        since.subtract(const Duration(seconds: 1)),
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> _tunInterfaceExists() async {
    try {
      final r = await Process.run('/sbin/ifconfig', [tunInterfaceName]);
      return r.exitCode == 0;
    } catch (_) {
      return false;
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
  Iterable<Process?> get sessionCores => [
    _xrayProcess,
    _rootXrayProcess,
    _mihomoProcess,
  ];

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
    stopStatsLoop();
    if (emitStates) emit(const VpnState(status: VpnStatus.disconnecting));

    if (_rootXrayProcess != null ||
        _xrayProcess != null ||
        _mihomoProcess != null) {
      await _dumpLogsToFile();
    }

    await _restoreSystemProxy();

    await _stopRootCore(_rootXrayProcess);
    _stopRootLogTail();
    if (_mihomoRunsAsRoot) {
      await _stopRootCore(_mihomoProcess);
    } else {
      await stopCoreProcess(_mihomoProcess);
    }
    await stopCoreProcess(_xrayProcess);
    _rootXrayProcess = null;
    _mihomoProcess = null;
    _mihomoRunsAsRoot = false;
    _xrayProcess = null;
    _xrayMetricsPort = null;

    final dir = _sessionDir;
    _sessionDir = null;
    await deleteSessionDir(dir);

    _activeMode = null;
    if (identical(activeInstance, this)) activeInstance = null;
    if (emitStates) emit(VpnState.disconnected);
  }

  Future<void> _stopRootCore(Process? proc) async {
    if (proc == null) return;
    try {
      final sentinel = _rootSentinel;
      if (sentinel != null && sentinel.existsSync()) sentinel.deleteSync();
    } catch (e) {
      AppLogger.instance.warn('Root core sentinel not removed', error: e);
    }
    _rootSentinel = null;
    try {
      await proc.exitCode.timeout(const Duration(seconds: 8));
    } catch (_) {
      try {
        proc.kill(ProcessSignal.sigterm);
      } catch (_) {}
      try {
        await proc.exitCode.timeout(const Duration(seconds: 2));
      } catch (_) {
        try {
          proc.kill(ProcessSignal.sigkill);
        } catch (_) {}
      }
    }

    // XNU detaches utun interfaces asynchronously after fd close; wait before allowing a reconnect.
    const budgetMs = 6000;
    var waited = 0;
    while (waited < budgetMs && await _tunInterfaceExists()) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      waited += 250;
    }
    if (waited >= budgetMs) {
      AppLogger.instance.warn(
        'TUN interface $tunInterfaceName is still present '
        '${budgetMs ~/ 1000}s after the core was stopped.',
      );
    }
  }

  @override
  Future<bool> requestTunnelPermission() async => true;

  @override
  Future<VpnState> getCurrentState() async {
    if (_xrayProcess != null ||
        _mihomoProcess != null ||
        _rootXrayProcess != null) {
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
      if (home != null && home.isNotEmpty) p.join(home, 'Applications'),
      if (includeSystem) '/System/Applications',
    ];

    for (final root in appDirs) {
      final dir = Directory(root);
      if (!dir.existsSync()) continue;
      try {
        await for (final entity in dir.list(followLinks: false)) {
          if (!entity.path.endsWith('.app')) continue;
          final displayName = p.basenameWithoutExtension(entity.path);
          final exeName =
              await _bundleExecutableName(entity.path) ?? displayName;
          if (exeName.isEmpty || !seen.add(exeName.toLowerCase())) continue;
          apps.add({
            'packageName': exeName,
            'appName': displayName,
            'isRunning': false,
            'isSystem': root.startsWith('/System'),
            'installPath': entity.path,
          });
        }
      } catch (e) {
        AppLogger.instance.debug('Could not scan $root', error: e);
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

  static Future<String?> _bundleExecutableName(String appBundlePath) =>
      MacosAppBundle.executableName(appBundlePath);

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
    return port == null ? null : queryXrayTraffic(port);
  }

  @override
  Future<void> pollTrafficStats(
    ConnectionMode mode, {
    bool force = false,
  }) async {
    if (!statsPollingEnabled && !force) return;
    if (_xrayProcess == null &&
        _mihomoProcess == null &&
        _rootXrayProcess == null) {
      return;
    }
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
