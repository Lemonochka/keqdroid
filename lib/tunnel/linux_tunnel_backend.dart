import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/app_logger.dart';
import '../core/exceptions.dart';
import '../services/ephemeral_xray_ping.dart';
import '../utils/keqrnel_config.dart';
import '../services/firefox_proxy_helper.dart';
import '../utils/wireproxy_config.dart';
import 'connection_mode.dart';
import 'linux_core_paths.dart';
import 'socks_credential_generator.dart';
import 'tunnel_backend.dart';
import 'tunnel_session_request.dart';
import 'tunnel_state.dart';
import 'vpn_backend.dart';
import 'xray_session_stats.dart';

/// Linux desktop backend (proxy + TUN).
///
/// Mirrors the proven pure-Dart pipeline of [WindowsTunnelBackend] — spawning
/// xray / sing-box / wireproxy and waiting on their local ports — without any
/// native MethodChannel.
///
/// * **Proxy mode**: xray (or wireproxy-awg) exposes a local SOCKS5/HTTP proxy,
///   applied to the desktop via GNOME `gsettings` (best effort; degrades on
///   non-GNOME — the local proxy still works and can be set manually).
/// * **TUN mode**: xray/wireproxy provide the local SOCKS5, then sing-box runs
///   a `tun` inbound that captures all traffic. Creating the TUN device and
///   editing routes needs root, so sing-box is launched via `pkexec` (a polkit
///   GUI prompt). Traffic counters are read from the tun interface sysfs stats.
class LinuxTunnelBackend implements TunnelBackend {
  static const tunInterfaceName = 'tun-keqdis';

  /// Active session — lets DebugLogService surface core logs on Linux.
  static LinuxTunnelBackend? activeInstance;

  final _stateCtrl = StreamController<VpnState>.broadcast();

  Process? _xrayProcess;
  Process? _wireproxyProcess;
  Process? _singboxProcess;
  // Sentinel the elevated TUN wrapper polls: deleting it asks the root keqrnel
  // to stop (reverts auto_route/nftables) without re-elevation. See _runKeqrnelAsRoot.
  File? _rootSentinel;
  Directory? _sessionDir;
  ({String username, String password})? _pendingCreds;
  ConnectionMode? _activeMode;
  final StringBuffer _xrayLog = StringBuffer();
  final StringBuffer _singboxLog = StringBuffer();

  int? _awgInfoPort;
  String? _xrayBinPath;
  // Порт clash_api keqrnel в proxy-режиме — из него читаем кумулятивный трафик.
  int? _keqrnelClashPort;

  // true пока идёт штатный stopSession — чтобы вотчдог не принял наш же
  // kill за внезапную смерть ядра.
  bool _stoppingSession = false;

  Timer? _statsTimer;
  DateTime? _sessionStartedAt;
  int _prevInOctets = 0;
  int _prevOutOctets = 0;
  int _totalDownload = 0;
  int _totalUpload = 0;

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

  /// Tail of xray + sing-box stdout/stderr for the debug screen.
  String exportSessionLogs({int maxLines = 400}) {
    final combined = StringBuffer()
      ..writeln('=== xray / wireproxy ===')
      ..writeln(_xrayLog)
      ..writeln('=== sing-box ===')
      ..writeln(_singboxLog);
    return _tail(combined, maxLines: maxLines);
  }

  /// Also persist the combined core logs to a stable file so they can be read
  /// after disconnect (the session dir is wiped on stop). Path is logged.
  Future<void> _dumpLogsToFile() async {
    try {
      final path = p.join(Directory.systemTemp.path, 'keqdroid_cores.log');
      await File(path).writeAsString(exportSessionLogs(maxLines: 2000));
      AppLogger.instance.info('Core logs written to $path');
    } catch (_) {}
  }

  @override
  Future<({String username, String password})> fetchSocksCredentials() async {
    _pendingCreds = SocksCredentialGenerator.generatePair();
    return _pendingCreds!;
  }

  @override
  Future<void> startSession(TunnelSessionRequest request) async {
    _emit(VpnState(status: VpnStatus.connecting, activeMode: request.mode));
    _activeMode = request.mode;
    _xrayLog.clear();
    _singboxLog.clear();

    try {
      await stopSession();
      activeInstance = this;
      _sessionDir = await LinuxCorePaths.sessionDir();

      final isAwg = request.vpnBackend == VpnBackend.awg;
      if (request.mode == ConnectionMode.tun) {
        if (isAwg) {
          await _startAwgTunSession(request);
        } else {
          await _startKeqrnelTunSession(request);
        }
      } else {
        if (isAwg) {
          await _startAwgProxySession(request);
        } else {
          await _startKeqrnelProxySession(request);
        }
      }

      _startStatsLoop(request.mode);
      _emitConnectedTelemetry(request.mode);

      // Смерть ядра посреди сессии без вотчдога оставляла UI в «Connected»,
      // а системный прокси (gsettings) — направленным на мёртвый порт.
      _watchProcessExit(_xrayProcess, 'keqrnel');
      _watchProcessExit(_singboxProcess, 'keqrnel TUN');
      _watchProcessExit(_wireproxyProcess, 'wireproxy');
    } catch (e, st) {
      AppLogger.instance.error(
        'Linux tunnel start failed',
        error: e,
        stackTrace: st,
      );
      await _dumpLogsToFile();
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

  // ---- xray ---------------------------------------------------------------

  /// proxy-режим на keqrnel: sing-box держит локальные SOCKS/HTTP и считает
  /// трафик (clash_api), внутри — встроенный xray. Root не нужен.
  Future<void> _startKeqrnelProxySession(TunnelSessionRequest request) async {
    final bin = await LinuxCorePaths.keqrnelExecutable();
    if (bin == null) {
      throw VpnStartException(
        'keqrnel not found. ${LinuxCorePaths.binariesHint}',
      );
    }
    _xrayBinPath = bin;

    final clashPort = await _freePort();
    final merged = KeqrnelConfig.proxyWithStats(
      xrayConfig: request.xrayConfig,
      socksPort: request.socksPort,
      httpPort: request.httpPort,
      clashPort: clashPort,
    );
    _keqrnelClashPort = clashPort;
    final configFile = File(p.join(_sessionDir!.path, 'keqrnel.json'));
    await configFile.writeAsString(merged);

    await _ensurePortsAvailable(request, needsHttp: request.systemProxy);

    final geoDir = await LinuxCorePaths.geoAssetDir();
    _xrayProcess = await Process.start(
      bin,
      ['run', '-c', configFile.path],
      workingDirectory: _sessionDir!.path,
      environment: _coreProcessEnvironment(geoDir),
      mode: ProcessStartMode.normal,
    );
    _pipeProcessOutput(_xrayProcess!, _xrayLog);

    final socksReady = await _waitForPort(
      '127.0.0.1',
      request.socksPort,
      process: _xrayProcess,
      log: _xrayLog,
      processLabel: 'keqrnel',
    );
    if (!socksReady) {
      throw VpnStartException(
        'keqrnel SOCKS port ${request.socksPort} did not open.\n${_tail(_xrayLog)}',
      );
    }

    if (request.systemProxy) {
      final httpReady = await _waitForPort(
        '127.0.0.1',
        request.httpPort,
        process: _xrayProcess,
        log: _xrayLog,
        processLabel: 'keqrnel HTTP',
      );
      if (!httpReady) {
        throw VpnStartException(
          'keqrnel HTTP port ${request.httpPort} did not open. '
          'System proxy needs the HTTP inbound.\n${_tail(_xrayLog)}',
        );
      }
      await _applySystemProxy(request);
    }
  }

  /// TUN-режим на keqrnel: один процесс (sing-box TUN + встроенный xray) под root.
  Future<void> _startKeqrnelTunSession(TunnelSessionRequest request) async {
    final singConfig = request.singboxConfig;
    if (singConfig == null || singConfig.isEmpty) {
      throw const VpnStartException('singboxConfig is required for TUN mode');
    }
    final merged = KeqrnelConfig.fromChain(
      singboxConfig: singConfig,
      xrayConfig: request.xrayConfig,
      windows: false,
    );
    await _runKeqrnelAsRoot(merged);
  }

  // ---- wireproxy (AmneziaWG) ----------------------------------------------

  Future<void> _startWireproxy(
    TunnelSessionRequest request, {
    required bool withHttp,
  }) async {
    final wpBin = await LinuxCorePaths.wireproxyExecutable();
    if (wpBin == null) {
      throw VpnStartException(
        'wireproxy not found. ${LinuxCorePaths.binariesHint}',
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
    final confFile = File(p.join(_sessionDir!.path, 'wireproxy.conf'));
    await confFile.writeAsString(wpConf);

    final infoPort = await _freePort();
    _awgInfoPort = infoPort;

    _wireproxyProcess = await Process.start(
      wpBin,
      ['-i', '127.0.0.1:$infoPort', '-c', confFile.path],
      workingDirectory: _sessionDir!.path,
      mode: ProcessStartMode.normal,
    );
    _pipeProcessOutput(_wireproxyProcess!, _xrayLog);

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

  Future<void> _startAwgTunSession(TunnelSessionRequest request) async {
    await _startWireproxy(request, withHttp: false);
    final singConfig = request.singboxConfig;
    if (singConfig == null || singConfig.isEmpty) {
      throw const VpnStartException('singboxConfig is required for TUN mode');
    }
    await _runKeqrnelAsRoot(singConfig);
  }

  // ---- sing-box TUN (root via pkexec) -------------------------------------

  /// Запускает keqrnel под root через pkexec (TUN нужен root). keqrnel — это
  /// sing-box host, поднимает переданный sing-box-конфиг. Заменяет прежний
  /// отдельный sing-box.exe и для xray-протоколов, и для AmneziaWG-TUN.
  Future<void> _runKeqrnelAsRoot(String config) async {
    final singBin = await LinuxCorePaths.keqrnelExecutable();
    if (singBin == null) {
      throw VpnStartException(
        'keqrnel not found (required for TUN mode). ${LinuxCorePaths.binariesHint}',
      );
    }

    final singConfigFile = File(p.join(_sessionDir!.path, 'keqrnel-tun.json'));
    await singConfigFile.writeAsString(config);
    final rootGeoDir = await _stageGeoAssetsForRoot();

    // keqrnel runs as root via pkexec. When the app ships as an AppImage the
    // bundled binary lives on a per-user FUSE mount (/tmp/.mount_*) that root
    // CANNOT read — pkexec then dies with "Permission denied" / code 127. Copy
    // it into the session dir (real /tmp) where root has access, and exec that.
    final rootSingBin = p.join(_sessionDir!.path, 'keqrnel');
    try {
      await File(singBin).copy(rootSingBin);
      await Process.run('chmod', ['0755', rootSingBin]);
    } catch (e) {
      throw VpnStartException('Could not stage keqrnel for elevation: $e');
    }

    // sing-box runs as root via pkexec. pkexec does NOT reliably forward signals
    // to its root child, and a normal user cannot signal a root process — so we
    // can't stop sing-box by killing the pkexec wrapper. Doing that orphans
    // sing-box with the TUN + routes + nftables rules still installed, which
    // breaks the network even after disconnect (and in Proxy mode afterwards).
    // Instead run a tiny root wrapper that ties sing-box's lifetime to a sentinel
    // file: while the file exists AND the app is alive it keeps running; when we
    // delete the file (on stop) — or the app dies — it SIGTERMs sing-box AS ROOT,
    // letting it revert auto_route/nftables.
    //
    // Why a sentinel file and PID poll instead of stdin: an earlier design closed
    // our stdin pipe to ask for a stop. That is fundamentally broken through
    // pkexec — once a polkit agent AUTHENTICATES, pkexec does NOT keep the
    // caller's stdin attached to the elevated child, so the child's stdin is at
    // EOF from the start. A `cat`-on-stdin watchdog then fired instantly and
    // killed keqrnel the moment it launched (symptom: "keqrnel exited with code 0
    // (TUN/elevation failed?)" with the TUN already up and the core log showing
    // `keqrnel started` immediately followed by `keqrnel shutting down`). The
    // sentinel + `kill -0` PID poll needs no stdin and no re-elevation.
    //
    // pkexec runs keqrnel as root in the background; its stdout/stderr don't
    // reliably reach our captured pipe (the process can exit before the async
    // stream drains), which left core errors invisible — only a generic "code 1"
    // surfaced. Redirect them to a stable, root-readable file so the REAL reason
    // a TUN start failed is always available. Readiness is detected via the tun
    // interface appearing, so this doesn't depend on the live pipe.
    const coreLogPath = '/tmp/keqdroid_keqrnel.log';
    final sentinelFile = File(p.join(_sessionDir!.path, 'keqrnel.run'));
    await sentinelFile.writeAsString('1');
    _rootSentinel = sentinelFile;
    // Auth-маркер: root-обёртка создаёт его сразу после успешной polkit-
    // аутентификации. По нему отличаем «пользователь ещё вводит пароль» от
    // «ядро стартовало и должно поднять TUN» (см. _waitForElevation). Session
    // dir свежий на каждую сессию — застарелый маркер исключён.
    final authMarker = File(p.join(_sessionDir!.path, 'keqrnel.auth'));
    const wrapper = r'''
SB="$1"; CFG="$2"; GEO="$3"; LOGF="$4"; SENT="$5"; APPPID="$6"; AUTHF="$7"
: >"$LOGF"
: >"$AUTHF"
echo "[wrap v3 sentinel] start SENT=$SENT exists=$([ -e "$SENT" ] && echo y || echo n) APPPID=$APPPID app=$(kill -0 "$APPPID" 2>/dev/null && echo y || echo n)" >>"$LOGF"
if [ -n "$GEO" ]; then export XRAY_LOCATION_ASSET="$GEO"; fi
"$SB" run -c "$CFG" >>"$LOGF" 2>&1 &
sb=$!
while [ -e "$SENT" ] && kill -0 "$APPPID" 2>/dev/null; do
  kill -0 "$sb" 2>/dev/null || break
  sleep 1
done
echo "[wrap v3 sentinel] stop sent=$([ -e "$SENT" ] && echo y || echo n) app=$(kill -0 "$APPPID" 2>/dev/null && echo y || echo n) sb=$(kill -0 "$sb" 2>/dev/null && echo y || echo n)" >>"$LOGF"
kill -TERM "$sb" 2>/dev/null
wait "$sb"
''';
    try {
      _singboxProcess = await Process.start(
        'pkexec',
        [
          'sh',
          '-c',
          wrapper,
          'sh',
          rootSingBin,
          singConfigFile.path,
          rootGeoDir ?? '',
          coreLogPath,
          sentinelFile.path,
          '$pid',
          authMarker.path,
        ],
        workingDirectory: _sessionDir!.path,
        mode: ProcessStartMode.normal,
      );
    } on ProcessException catch (e) {
      throw VpnStartException(
        'Could not launch keqrnel with elevated privileges. TUN mode needs '
        'pkexec (polkit). Install it, or use Proxy mode. ($e)',
      );
    }
    _pipeProcessOutput(_singboxProcess!, _singboxLog);

    // Сначала дожидаемся polkit-аутентификации, и только потом меряем
    // готовность TUN — иначе 20с бюджета _waitForSingbox тикали, пока
    // пользователь вводил пароль, и коннект падал «после запроса прав».
    await _waitForElevation(
      process: _singboxProcess!,
      authMarker: authMarker,
      log: _singboxLog,
    );

    final ready = await _waitForSingbox(
      process: _singboxProcess!,
      log: _singboxLog,
    );

    // Pull the core's own output (the file above) into the session log so the
    // debug screen and the error below show the real sing-box/xray message.
    String coreLog = '';
    try {
      coreLog = await File(coreLogPath).readAsString();
    } catch (_) {}
    if (coreLog.trim().isNotEmpty) {
      _singboxLog
        ..writeln('=== keqrnel (core) ===')
        ..writeln(coreLog);
    }

    if (!ready) {
      final tail = coreLog.trim().isEmpty
          ? _tail(_singboxLog)
          : _tail(StringBuffer(coreLog));
      throw VpnStartException('keqrnel TUN did not start.\n$tail');
    }
  }

  Future<String?> _stageGeoAssetsForRoot() async {
    final geoDir = await LinuxCorePaths.geoAssetDir();
    if (geoDir == null) return null;

    final rootGeoDir = Directory(p.join(_sessionDir!.path, 'geo'));
    if (!rootGeoDir.existsSync()) rootGeoDir.createSync(recursive: true);

    var copied = false;
    for (final name in LinuxCorePaths.geoFileNames) {
      final src = File(p.join(geoDir, name));
      if (!src.existsSync()) continue;
      await src.copy(p.join(rootGeoDir.path, name));
      copied = true;
    }
    return copied ? rootGeoDir.path : null;
  }

  /// Ждёт завершения polkit-аутентификации перед отсчётом готовности TUN.
  ///
  /// [Process.start] для pkexec возвращается сразу — ещё ДО того, как
  /// пользователь ввёл пароль в окне polkit. Раньше 20-секундный бюджет
  /// [_waitForSingbox] стартовал в этот же момент: медленный ввод пароля (или
  /// просто его хвост) съедал бюджет, tun-интерфейс не успевал появиться и
  /// коннект падал «keqrnel TUN did not start» сразу после запроса прав —
  /// гонка между скоростью набора пароля и таймаутом ядра.
  ///
  /// Root-обёртка первым действием создаёт [authMarker] — это сигнал «пароль
  /// принят, ядро запускается». До маркера ждём без TUN-бюджета (до 2 минут на
  /// ввод пароля); выход pkexec до маркера — отмена/нет агента (126/127) или
  /// реальная ошибка, обе ветки объясняет [_elevationError].
  Future<void> _waitForElevation({
    required Process process,
    required File authMarker,
    required StringBuffer log,
  }) async {
    const maxWait = Duration(minutes: 2);
    final sw = Stopwatch()..start();
    while (sw.elapsed < maxWait) {
      final code = await process.exitCode.timeout(
        const Duration(milliseconds: 1),
        onTimeout: () => -1,
      );
      if (code >= 0) {
        throw VpnStartException(_elevationError(code, log));
      }
      if (authMarker.existsSync()) return;
      // Подстраховка: ядро уже подняло TUN, а маркер не виден (экзотика ФС).
      if (await _tunInterfaceExists()) return;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    // Диалог так и висит без ответа — сворачиваем pkexec. Это безопасно:
    // auth не выдана, root-потомка ещё нет, осиротевшего TUN не будет.
    try {
      process.kill(ProcessSignal.sigterm);
    } catch (_) {}
    throw const VpnStartException(
      'Polkit authorization timed out (2 min). Approve the password prompt '
      'to start TUN mode, or use Proxy mode.',
    );
  }

  Future<bool> _waitForSingbox({
    required Process process,
    required StringBuffer log,
  }) async {
    var waited = 0;
    while (waited < 20000) {
      final code = await process.exitCode.timeout(
        const Duration(milliseconds: 1),
        onTimeout: () => -1,
      );
      if (code >= 0) {
        throw VpnStartException(_elevationError(code, log));
      }
      final text = log.toString().toLowerCase();
      if (text.contains('started') && text.contains('tun')) return true;
      if (text.contains('tun-in') &&
          (text.contains('started') || text.contains('listening'))) {
        return true;
      }
      // tun interface up is the most reliable signal across versions.
      if (await _tunInterfaceExists()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      waited += 300;
    }
    // Timed out — only treat as ready if the tun device actually appeared.
    if (await _tunInterfaceExists()) return true;

    // Pull core log one last time for the error message below.
    try {
      const coreLogPath = '/tmp/keqdroid_keqrnel.log';
      final coreLog = await File(coreLogPath).readAsString();
      if (coreLog.trim().isNotEmpty) {
        log
          ..writeln('=== keqrnel (core, timeout) ===')
          ..writeln(coreLog);
      }
    } catch (_) {}

    final stillRunning = await process.exitCode.timeout(
      const Duration(milliseconds: 1),
      onTimeout: () => -1,
    );
    if (stillRunning >= 0) {
      throw VpnStartException(_elevationError(stillRunning, log));
    }
    return false;
  }

  /// User-facing message for an elevated keqrnel exit. pkexec uses distinct
  /// codes for the two "no root granted" cases — surface them with a clear hint
  /// (and the Proxy-mode fallback) instead of a raw exit code:
  ///  * 126 — the user dismissed the polkit password dialog (cancelled).
  ///  * 127 — not authorized / no polkit agent available to prompt (common on
  ///    minimal tiling WMs that don't run polkit-gnome / lxpolkit / kde agent).
  /// Any other code is a real core failure — keep the code + log tail.
  String _elevationError(int code, StringBuffer log) {
    switch (code) {
      case 126:
        return 'Authorization cancelled. TUN mode needs root via pkexec '
            '(polkit) — approve the password prompt, or use Proxy mode.';
      case 127:
        return 'Could not get root for TUN mode: no polkit agent answered '
            '(pkexec). Install/start a polkit authentication agent, or use '
            'Proxy mode.';
      default:
        return 'keqrnel exited with code $code (TUN/elevation failed?).\n'
            '${_tail(log)}';
    }
  }

  Future<bool> _tunInterfaceExists() async {
    return Directory('/sys/class/net/$tunInterfaceName').exists();
  }

  // ---- system proxy (GNOME gsettings, best effort) ------------------------

  Future<void> _applySystemProxy(TunnelSessionRequest request) async {
    final ok = await _gsettingsProxy(
      enabled: true,
      socksPort: request.socksPort,
      httpPort: request.httpPort,
    );
    if (!ok) {
      AppLogger.instance.warn(
        'Could not set the GNOME system proxy (gsettings unavailable or '
        'non-GNOME desktop). The local proxy is up on 127.0.0.1: '
        'SOCKS ${request.socksPort} / HTTP ${request.httpPort} — configure '
        'it manually if your desktop does not honour gsettings.',
      );
    }
    // Deliberately NOT writing Firefox user.js on Linux: it forced a *manual*
    // proxy (network.proxy.type=1) that survived disconnect and our cleanup —
    // causing endless auth prompts and traffic to a dead 127.0.0.1 proxy after
    // quit. gsettings is enough; Firefox users can pick "Use system proxy
    // settings" once. We still CLEAR any stale block left by older builds.
  }

  Future<bool> _gsettingsProxy({
    required bool enabled,
    int socksPort = 0,
    int httpPort = 0,
  }) async {
    Future<bool> set(List<String> args) async {
      try {
        final r = await Process.run('gsettings', args);
        return r.exitCode == 0;
      } catch (_) {
        return false;
      }
    }

    if (!enabled) {
      return set(['set', 'org.gnome.system.proxy', 'mode', 'none']);
    }

    await set(['set', 'org.gnome.system.proxy.http', 'host', '127.0.0.1']);
    await set(['set', 'org.gnome.system.proxy.http', 'port', '$httpPort']);
    await set(['set', 'org.gnome.system.proxy.https', 'host', '127.0.0.1']);
    await set(['set', 'org.gnome.system.proxy.https', 'port', '$httpPort']);
    await set(['set', 'org.gnome.system.proxy.socks', 'host', '127.0.0.1']);
    await set(['set', 'org.gnome.system.proxy.socks', 'port', '$socksPort']);
    await set([
      'set',
      'org.gnome.system.proxy',
      'ignore-hosts',
      "['localhost', '127.0.0.0/8', '::1']",
    ]);
    // The mode switch landing is our success signal; if gsettings is missing
    // every call returns false.
    return set(['set', 'org.gnome.system.proxy', 'mode', 'manual']);
  }

  /// Best-effort cleanup of state a previous (possibly crashed) run may have
  /// left behind: a system proxy still pointing at a dead local port and a
  /// stale Firefox proxy block. Called on Linux app startup. Does not touch
  /// core processes (avoid killing unrelated xray/sing-box the user may run).
  static Future<void> cleanupStaleState() async {
    try {
      await Process.run('gsettings', [
        'set',
        'org.gnome.system.proxy',
        'mode',
        'none',
      ]);
    } catch (_) {}
    try {
      await FirefoxProxyHelper.clearProxyPref();
    } catch (_) {}
  }

  // ---- lifecycle ----------------------------------------------------------

  /// Вотчдог: ядро завершилось само (не через [stopSession]) → чистим
  /// системный прокси/состояние и эмитим error вместо вечного «Connected».
  void _watchProcessExit(Process? process, String label) {
    if (process == null) return;
    unawaited(process.exitCode.then((code) async {
      if (_stoppingSession) return;
      // Процесс уже не из активной сессии (штатный stop занулил поля).
      if (!identical(process, _xrayProcess) &&
          !identical(process, _singboxProcess) &&
          !identical(process, _wireproxyProcess)) {
        return;
      }
      AppLogger.instance.error(
        '$label exited unexpectedly with code $code; tearing the session down',
      );
      try {
        await stopSession();
      } catch (_) {}
      _emit(VpnState(
        status: VpnStatus.error,
        errorMessage:
            '$label stopped unexpectedly (exit code $code). Disconnected.',
      ));
    }));
  }

  @override
  Future<void> stopSession() async {
    _stoppingSession = true;
    try {
      await _stopSessionInner();
    } finally {
      _stoppingSession = false;
    }
  }

  Future<void> _stopSessionInner() async {
    _stopStatsLoop();
    _emit(const VpnState(status: VpnStatus.disconnecting));

    if (_singboxProcess != null ||
        _xrayProcess != null ||
        _wireproxyProcess != null) {
      await _dumpLogsToFile();
    }

    // Always reset the system proxy on stop — even if this instance did not set
    // it (left over from a previous run/crash) — otherwise the desktop keeps
    // routing to a dead 127.0.0.1 proxy.
    await _gsettingsProxy(enabled: false);
    try {
      await FirefoxProxyHelper.clearProxyPref();
    } catch (_) {}

    // sing-box first: it owns the tun device + routes, tear it down before the
    // upstream SOCKS provider so traffic fails closed, not into a dead socks.
    await _stopSingbox();
    await _killProcess(_wireproxyProcess);
    await _killProcess(_xrayProcess);
    _singboxProcess = null;
    _wireproxyProcess = null;
    _awgInfoPort = null;
    _xrayProcess = null;
    _xrayBinPath = null;
    _keqrnelClashPort = null;

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
  Future<bool> requestTunnelPermission() async => true;

  @override
  Future<VpnState> getCurrentState() async {
    if (_xrayProcess != null ||
        _wireproxyProcess != null ||
        _singboxProcess != null) {
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
    // Split tunneling matches sing-box `process_name`, which on Linux is the
    // executable basename. Enumerate running processes from /proc, de-duped by
    // that name. Kernel threads (no /exe) are skipped unless includeSystem.
    final seen = <String>{};
    final apps = <Map<String, dynamic>>[];
    try {
      await for (final entry in Directory('/proc').list(followLinks: false)) {
        final pid = p.basename(entry.path);
        if (int.tryParse(pid) == null) continue;

        String? exePath;
        try {
          exePath = await Link('${entry.path}/exe').target();
        } catch (_) {
          exePath = null; // permission denied or kernel thread
        }

        String name;
        if (exePath != null && exePath.isNotEmpty) {
          name = p.basename(exePath);
        } else {
          if (!includeSystem) continue;
          try {
            name = (await File('${entry.path}/comm').readAsString()).trim();
          } catch (_) {
            continue;
          }
        }
        if (name.isEmpty || !seen.add(name.toLowerCase())) continue;

        apps.add({
          'packageName': name,
          'appName': name,
          'isRunning': true,
          'isSystem': exePath == null,
          'installPath': ?exePath,
        });
      }
    } catch (e, st) {
      AppLogger.instance.warn(
        'listProcesses (/proc) failed',
        error: e,
        stackTrace: st,
      );
    }
    apps.sort(
      (a, b) => (a['appName'] as String).toLowerCase().compareTo(
        (b['appName'] as String).toLowerCase(),
      ),
    );
    return apps;
  }

  @override
  Future<String?> getAppIcon(String path) async => null;

  @override
  Future<
    List<
      ({String id, bool success, int? latencyMs, String error, int? httpStatus})
    >
  >
  xrayUrlTestBatch({
    required List<(String id, String xrayConfig)> items,
    required int socksPort,
    String testUrl = 'https://connectivitycheck.gstatic.com/generate_204',
    int timeoutMs = 15000,
  }) async {
    if (items.isEmpty) return [];
    // EphemeralXrayPing is Windows-only for now; on Linux this degrades to a
    // clear per-item error (TCP ping still works via getPing). Phase 1.5.
    final raw = await EphemeralXrayPing.urlTestBatch(
      items: items.map((e) => (id: e.$1, xrayConfigJson: e.$2)).toList(),
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
  Future<List<({String id, bool success, int? kbps, String error})>>
  xraySpeedTestBatch({
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

  // ---- internals ----------------------------------------------------------

  static Map<String, String>? _coreProcessEnvironment(String? geoDir) {
    if (geoDir == null) return null;
    return {...Platform.environment, 'XRAY_LOCATION_ASSET': geoDir};
  }

  void _pipeProcessOutput(Process process, StringBuffer buffer) {
    void append(String line) {
      buffer.writeln(line);
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

  /// Stops the elevated sing-box gracefully. We cannot signal the root process
  /// directly, so we delete the sentinel file the root wrapper polls — it then
  /// SIGTERMs sing-box AS ROOT, which reverts auto_route/nftables before exiting.
  Future<void> _stopSingbox() async {
    final proc = _singboxProcess;
    if (proc == null) return;
    try {
      final sentinel = _rootSentinel;
      if (sentinel != null && sentinel.existsSync()) sentinel.deleteSync();
    } catch (_) {}
    _rootSentinel = null;
    try {
      await proc.exitCode.timeout(const Duration(seconds: 8));
    } catch (_) {
      // Wrapper didn't exit in time — last resort so we never leave a root
      // sing-box holding the TUN. The elevated pkill may show a polkit prompt.
      try {
        await Process.run('pkexec', ['pkill', '-TERM', '-x', 'keqrnel']);
      } catch (_) {}
      try {
        proc.kill(ProcessSignal.sigkill);
      } catch (_) {}
    }
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

  Future<int> _freePort() async {
    final s = await ServerSocket.bind('127.0.0.1', 0);
    final port = s.port;
    await s.close();
    return port;
  }

  Future<void> _ensurePortsAvailable(
    TunnelSessionRequest request, {
    required bool needsHttp,
  }) async {
    if (!await _isPortAvailable('127.0.0.1', request.socksPort)) {
      throw VpnStartException(
        'SOCKS port ${request.socksPort} is already in use.',
      );
    }
    if (needsHttp && !await _isPortAvailable('127.0.0.1', request.httpPort)) {
      throw VpnStartException(
        'HTTP port ${request.httpPort} is already in use.',
      );
    }
  }

  Future<bool> _isPortAvailable(String host, int port) async {
    try {
      final serverSocket = await ServerSocket.bind(host, port);
      await serverSocket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  String _tail(StringBuffer buffer, {int maxLines = 12}) {
    final lines = buffer
        .toString()
        .split('\n')
        .where((l) => l.trim().isNotEmpty);
    final tail = lines.length > maxLines
        ? lines.skip(lines.length - maxLines)
        : lines;
    final text = tail.join('\n');
    return text.isEmpty ? '(no process output)' : text;
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
    if (_xrayProcess == null &&
        _wireproxyProcess == null &&
        _singboxProcess == null) {
      return;
    }
    try {
      final int inOctets;
      final int outOctets;

      if (mode == ConnectionMode.tun) {
        // tun interface stats: kernel writes the app's egress to the device
        // (tx) and reads sing-box's downloaded replies from it (rx).
        final c = await _queryTunCounters();
        if (c == null) {
          _emitConnectedTelemetry(mode);
          return;
        }
        inOctets = c.rx;
        outOctets = c.tx;
      } else if (_wireproxyProcess != null && _awgInfoPort != null) {
        final m = await _queryWireproxyMetrics(_awgInfoPort!);
        if (m == null) {
          _emitConnectedTelemetry(mode);
          return;
        }
        inOctets = m.rx;
        outOctets = m.tx;
      } else if (_keqrnelClashPort != null) {
        // keqrnel proxy: кумулятивный трафик из clash_api sing-box.
        final t = await _queryClashTraffic(_keqrnelClashPort!);
        if (t == null) {
          _emitConnectedTelemetry(mode);
          return;
        }
        inOctets = t.down;
        outOctets = t.up;
      } else if (_xrayProcess != null) {
        final xrayBin = _xrayBinPath;
        if (xrayBin == null) return;
        final counters = await XraySessionStats.queryInboundCounters(
          xrayExecutable: xrayBin,
        );
        if (counters == null) return;
        inOctets = counters.download;
        outOctets = counters.upload;
      } else {
        return;
      }

      if (_prevInOctets == 0 && _prevOutOctets == 0) {
        _prevInOctets = inOctets;
        _prevOutOctets = outOctets;
        _emitConnectedTelemetry(mode);
        return;
      }

      final deltaIn = inOctets >= _prevInOctets ? inOctets - _prevInOctets : 0;
      final deltaOut = outOctets >= _prevOutOctets
          ? outOctets - _prevOutOctets
          : 0;
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
      AppLogger.instance.debug('Linux getTrafficStats failed: $e');
    }
  }

  /// Кумулятивный трафик из clash_api keqrnel (proxy-режим): GET /connections →
  /// downloadTotal/uploadTotal. down = принято, up = отправлено.
  Future<({int down, int up})?> _queryClashTraffic(int port) async {
    final client = HttpClient();
    try {
      final req = await client
          .get('127.0.0.1', port, '/connections')
          .timeout(const Duration(seconds: 2));
      final resp = await req.close().timeout(const Duration(seconds: 2));
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final down = (json['downloadTotal'] as num?)?.toInt() ?? 0;
      final up = (json['uploadTotal'] as num?)?.toInt() ?? 0;
      return (down: down, up: up);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Cumulative tun interface counters from sysfs (download = rx, upload = tx).
  Future<({int rx, int tx})?> _queryTunCounters() async {
    try {
      final base = '/sys/class/net/$tunInterfaceName/statistics';
      final rx = int.parse(
        (await File('$base/rx_bytes').readAsString()).trim(),
      );
      final tx = int.parse(
        (await File('$base/tx_bytes').readAsString()).trim(),
      );
      return (rx: rx, tx: tx);
    } catch (_) {
      return null;
    }
  }

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
    _emit(
      _buildConnectedState(
        mode,
        downloadSpeed: downloadSpeed,
        uploadSpeed: uploadSpeed,
      ),
    );
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
}
