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
  static const _helperPath = '/usr/local/libexec/keqdroid/core-tun-root';
  static const _trustedCoresDir = '/usr/local/libexec/keqdroid/cores';
  static const _sudoersPath = '/etc/sudoers.d/keqdroid-tun';
  static const _helperVersionMark = '[wrap mac v1';
  static const _untrustedCoreExit = 4;
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

  // Positional arguments form a versioned contract with the installed sudoers helper.
  // Caller-supplied paths are read as the invoking user; root writes only under /var/run/keqdroid/<uid>.
  static const _tunWrapperBody =
      r'''PATH="/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/bin:/opt/homebrew/bin"; export PATH
umask 022
SB="$1"; CFG="$2"; GEO="$3"; SENT="$4"; APPPID="$5"; KIND="$6"; CALLER_UID="$7"
HELPER=/usr/local/libexec/keqdroid/core-tun-root
CORES=/usr/local/libexec/keqdroid/cores
case "$KIND" in xray) NAME=xray; EXT=json ;; mihomo) NAME=mihomo; EXT=yaml ;; *) exit 5 ;; esac
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
if [ "$0" = "$HELPER" ]; then
  CALLER_HASH=$(as_owner /usr/bin/shasum -a 256 -- "$SB" | /usr/bin/awk '{print $1}')
  TRUSTED_HASH=$(/usr/bin/shasum -a 256 -- "$CORES/$NAME" | /usr/bin/awk '{print $1}')
  [ -n "$CALLER_HASH" ] && [ "$CALLER_HASH" = "$TRUSTED_HASH" ] || exit 4
  SB=$CORES/$NAME
fi
CONF=$RUN/config.$EXT
as_owner /bin/cat -- "$CFG" >"$CONF" || exit 5
for f in geoip.dat geosite.dat; do
  [ -n "$GEO" ] && as_owner test -f "$GEO/$f" && as_owner /bin/cat -- "$GEO/$f" >"$RUN/home/$f"
done
: >"$RUN/core.auth"
echo "[wrap mac v1] start KIND=$KIND app=$(kill -0 "$APPPID" 2>/dev/null && echo y || echo n)" >>"$LOGF"
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
echo "[wrap mac v1] stop sent=$([ -e "$SENT" ] && echo y || echo n) app=$(kill -0 "$APPPID" 2>/dev/null && echo y || echo n) core=$(kill -0 "$sb" 2>/dev/null && echo y || echo n)" >>"$LOGF"
kill -TERM "$sb" 2>/dev/null
wait "$sb"
''';

  static const _sudoersContent =
      '# keqdroid: passwordless authorization for TUN mode.\n'
      '# Removing this file restores the password prompt on every TUN connect.\n'
      '%admin ALL=(root) NOPASSWD: $_helperPath *\n';

  @visibleForTesting
  static String get tunWrapperBodyForTest => _tunWrapperBody;

  @visibleForTesting
  static String get sudoersRuleForTest => _sudoersContent;

  @visibleForTesting
  static const helperPathForTest = _helperPath;

  @visibleForTesting
  static const helperVersionMarkForTest = _helperVersionMark;

  static bool isPasswordlessTunInstalled() {
    if (!Platform.isMacOS) return false;
    try {
      final helper = File(_helperPath);
      return helper.existsSync() &&
          helper.readAsStringSync().contains(_helperVersionMark);
    } catch (_) {
      return false;
    }
  }

  static Future<File> _passwordlessOffMarker() async => File(
    p.join(
      (await getApplicationSupportDirectory()).path,
      'tun_password_always',
    ),
  );

  static Future<bool> passwordlessTunDeclined() async {
    if (!Platform.isMacOS) return false;
    try {
      return (await _passwordlessOffMarker()).existsSync();
    } catch (_) {
      return false;
    }
  }

  static Future<String> _installScript({required bool runAfter}) async {
    final helper = '#!/bin/sh\n$_tunWrapperBody';
    final cores = <String, String?>{
      'xray': await MacosCorePaths.xrayExecutable(),
      'mihomo': await MacosCorePaths.mihomoExecutable(),
    };
    final installCores = [
      for (final MapEntry(:key, :value) in cores.entries)
        if (value != null)
          "/usr/bin/install -m 0755 ${posixShellQuote(value)} '$_trustedCoresDir/$key'",
    ].join('\n');
    final run = runAfter ? "set +e\nexec '$_helperPath' \"\$@\"\n" : '';
    return '''
set -e
/bin/mkdir -p /usr/local/libexec/keqdroid '$_trustedCoresDir' /etc/sudoers.d
$installCores
/bin/cat > '$_helperPath' <<'KEQDROID_HELPER_EOF'
$helper
KEQDROID_HELPER_EOF
/bin/chmod 0755 '$_helperPath'
/usr/sbin/chown root:wheel '$_helperPath'
TMP_SUDOERS=\$(/usr/bin/mktemp /tmp/keqdroid-sudoers.XXXXXX)
/bin/cat > "\$TMP_SUDOERS" <<'KEQDROID_SUDOERS_EOF'
$_sudoersContent
KEQDROID_SUDOERS_EOF
/bin/chmod 0440 "\$TMP_SUDOERS"
/usr/sbin/chown root:wheel "\$TMP_SUDOERS"
/usr/sbin/visudo -cf "\$TMP_SUDOERS"
/bin/mv -f "\$TMP_SUDOERS" '$_sudoersPath'
$run''';
  }

  @visibleForTesting
  static Future<String> installScriptForTest({required bool runAfter}) =>
      _installScript(runAfter: runAfter);

  static String get _removeScript =>
      "/bin/rm -f '$_helperPath' '$_sudoersPath'; /bin/rm -rf '$_trustedCoresDir'";

  @visibleForTesting
  static String get removeScriptForTest => _removeScript;

  static Future<bool> installPasswordlessTun() async {
    if (!Platform.isMacOS) return false;
    Directory? tmp;
    try {
      tmp = await Directory.systemTemp.createTemp('keqdroid_tun_install_');
      final scriptFile = File(p.join(tmp.path, 'install.sh'));
      await scriptFile.writeAsString(await _installScript(runAfter: false));
      await Process.run('/bin/chmod', ['0700', scriptFile.path]);
      final res = await Process.run('/usr/bin/osascript', [
        '-e',
        appleScriptAdminCommand(['/bin/sh', scriptFile.path]),
      ]);
      if (res.exitCode != 0) {
        AppLogger.instance.warn(
          'installPasswordlessTun failed: code=${res.exitCode} err=${res.stderr}',
        );
        return false;
      }
      final marker = await _passwordlessOffMarker();
      if (marker.existsSync()) await marker.delete();
      return true;
    } catch (e, st) {
      AppLogger.instance.error(
        'installPasswordlessTun error',
        error: e,
        stackTrace: st,
      );
      return false;
    } finally {
      await deleteSessionDir(tmp);
    }
  }

  static Future<bool> removePasswordlessTun() async {
    if (!Platform.isMacOS) return false;
    Directory? tmp;
    try {
      tmp = await Directory.systemTemp.createTemp('keqdroid_tun_remove_');
      final scriptFile = File(p.join(tmp.path, 'remove.sh'));
      await scriptFile.writeAsString('#!/bin/sh\n$_removeScript\n');
      await Process.run('/bin/chmod', ['0700', scriptFile.path]);
      final res = await Process.run('/usr/bin/osascript', [
        '-e',
        appleScriptAdminCommand(['/bin/sh', scriptFile.path]),
      ]);
      if (res.exitCode != 0) return false;
      final marker = await _passwordlessOffMarker();
      await marker.parent.create(recursive: true);
      await marker.writeAsString('1');
      return true;
    } catch (e, st) {
      AppLogger.instance.error(
        'removePasswordlessTun error',
        error: e,
        stackTrace: st,
      );
      return false;
    } finally {
      await deleteSessionDir(tmp);
    }
  }

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
    bool allowPasswordless = true,
  }) async {
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
    final asRoot = macosRunningAsRoot();
    final usePasswordless = allowPasswordless && isPasswordlessTunInstalled();
    final installNow =
        !asRoot && !usePasswordless && !await passwordlessTunDeclined();

    final wrapperFile = File(p.join(_sessionDir!.path, 'tun_wrap.sh'));
    await wrapperFile.writeAsString(
      '#!/bin/sh\n${installNow ? await _installScript(runAfter: true) : _tunWrapperBody}',
    );
    await Process.run('/bin/chmod', ['0700', wrapperFile.path]);

    final launch = planMacosElevation(
      coreArgs: coreArgs,
      wrapperScriptPath: wrapperFile.path,
      helperPath: _helperPath,
      asRoot: asRoot,
      passwordless: usePasswordless,
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

    final authorized = await _waitForElevation(
      process: process,
      authMarker: authMarker,
      log: log,
      untrustedCoreExit: usePasswordless ? _untrustedCoreExit : null,
      viaSudo: launch.viaSudo,
    );
    if (!authorized) {
      AppLogger.instance.info(
        '$label changed since passwordless TUN was set up; asking for the '
        'administrator password once to trust the new one',
      );
      return _startElevatedCore(
        binPath: binPath,
        configPath: configPath,
        geoOrHomeDir: geoOrHomeDir,
        kind: kind,
        label: label,
        log: log,
        onStarted: onStarted,
        allowPasswordless: false,
      );
    }
    return process;
  }

  Future<bool> _waitForElevation({
    required Process process,
    required File authMarker,
    required StringBuffer log,
    int? untrustedCoreExit,
    required bool viaSudo,
  }) async {
    const maxWait = Duration(minutes: 2);
    final sw = Stopwatch()..start();
    while (sw.elapsed < maxWait) {
      final code = await exitCodeOrNull(process);
      if (code != null) {
        if (code == untrustedCoreExit) return false;
        // sudo -n exits with 1 if sudoers rule was removed externally; fall back to prompt once.
        if (viaSudo &&
            code == 1 &&
            log.toString().toLowerCase().contains('a password is required')) {
          return false;
        }
        throw VpnStartException(_elevationError(code, log));
      }
      if (_freshSince(authMarker, _rootCoreLaunchedAt)) return true;
      if (await _tunInterfaceExists()) return true;
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
          final exeName = await _bundleExecutableName(entity.path) ?? displayName;
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

  static Future<String?> _bundleExecutableName(String appBundlePath) async {
    final plist = p.join(appBundlePath, 'Contents', 'Info.plist');
    if (!File(plist).existsSync()) return null;
    try {
      final r = await Process.run('/usr/bin/defaults', [
        'read',
        plist,
        'CFBundleExecutable',
      ]);
      if (r.exitCode == 0) {
        final name = '${r.stdout}'.trim();
        if (name.isNotEmpty) return name;
      }
    } catch (_) {}
    return null;
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
