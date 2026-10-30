import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/app_logger.dart';
import '../core/exceptions.dart';
import '../services/core_dial_failures.dart';
import '../services/xray_route_decisions.dart';
import '../utils/xray_session_log.dart';
import '../services/ephemeral_xray_ping.dart';
import '../utils/mihomo_api_session.dart';
import 'connection_mode.dart';
import 'desktop_traffic_stats.dart';
import 'linux_core_paths.dart';
import 'linux_elevation.dart';
import 'linux_system_proxy.dart';
import 'local_port_plan.dart';
import 'local_proxy_probe.dart';
import 'socks_credential_generator.dart';
import 'tun_failure_hints.dart';
import 'tunnel_backend.dart';
import 'tunnel_session_request.dart';
import 'tunnel_state.dart';
import 'vpn_backend.dart';
import 'xray_desktop_config.dart';

class LinuxTunnelBackend with DesktopTrafficStats implements TunnelBackend {
  static const tunInterfaceName = 'tun-keqdis';

  // pkexec не держит наш pipe, причину падения ядра видно только из файла.
  // root пишет только в свой каталог: в нашем каталоге сессии ссылка вместо файла увела бы запись куда угодно
  static String get _rootRunDir => '$_runRootDir/${linuxRealUid()}';

  String get _coreLogPath => p.join(_rootRunDir, 'core.log');

  // по mtime отличаем свежий лог от прошлой сессии: при падении самого pkexec файл не обнулён
  DateTime? _rootCoreLaunchedAt;

  static LinuxTunnelBackend? activeInstance;

  final _stateCtrl = StreamController<VpnState>.broadcast();

  Process? _xrayProcess;
  Process? _rootXrayProcess;
  File? _rootSentinel;
  Directory? _sessionDir;
  ConnectionMode? _activeMode;

  @override
  ConnectionMode? get activeMode => _activeMode;
  final StringBuffer _xrayLog = StringBuffer();
  final StringBuffer _rootLog = StringBuffer();

  int? _xrayMetricsPort;

  // до фильтра уровня: при loglevel error строка Warning в буфер не попадает
  bool _xrayStarted = false;

  Timer? _rootLogTimer;
  int _rootLogOffset = 0;
  String _rootLogPending = '';
  bool _rootLogReading = false;

  int _xrayLogThreshold = 0;

  Process? _mihomoProcess;

  int? get clashApiPort =>
      _mihomoProcess != null ? MihomoApiSession().port : null;

  String get clashApiSecret => MihomoApiSession().secret;

  Map<String, int> get activeCorePids => {
    if (_xrayProcess != null) 'xray': _xrayProcess!.pid,
    if (_mihomoProcess != null)
      _mihomoRunsAsRoot ? 'mihomo (root, TUN)' : 'mihomo': _mihomoProcess!.pid,
    if (_rootXrayProcess != null) 'xray (root, TUN)': _rootXrayProcess!.pid,
  };

  // root-процессу обычный пользователь сигнал не пошлёт, останавливаем удалением сентинела
  bool _mihomoRunsAsRoot = false;

  // пока идёт штатный стоп, вотчдог не должен принять наш kill за смерть ядра
  bool _stoppingSession = false;


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
    return _tail(combined, maxLines: maxLines);
  }

  // не в общий /tmp: там адреса серверов и посещённые сайты
  Future<void> _dumpLogsToFile() async {
    try {
      final runtime = Platform.environment['XDG_RUNTIME_DIR'];
      final private = runtime != null && Directory(runtime).existsSync();
      final dir = private
          ? runtime
          : (await getApplicationSupportDirectory()).path;
      final path = p.join(dir, coresLogName);
      await File(path).writeAsString(exportSessionLogs(maxLines: 2000));
      if (!private) await Process.run('chmod', ['600', path]);
      AppLogger.instance.info('Core logs written to $path');
    } catch (_) {}
  }

  static const coresLogName = 'keqdroid_cores.log';

  @override
  Future<({String username, String password})> fetchSocksCredentials() async {
    return SocksCredentialGenerator.generatePair();
  }

  @override
  Future<void> startSession(TunnelSessionRequest request) async {
    emit(VpnState(status: VpnStatus.connecting, activeMode: request.mode));
    _activeMode = request.mode;
    _xrayLog.clear();
    _rootLog.clear();
    XrayRouteDecisions.reset();

    try {
      await _cleanupForRestart();
      activeInstance = this;
      // _cleanupForRestart обнуляет режим, без возврата опрос счётчиков после трея не перезапустится
      _activeMode = request.mode;
      _sessionDir = await LinuxCorePaths.sessionDir();

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

      // без вотчдога смерть ядра оставляла UI в Connected, а системный прокси на мёртвом порту
      _watchProcessExit(_xrayProcess, 'xray');
      _watchProcessExit(_mihomoProcess, 'mihomo');
      _watchProcessExit(_rootXrayProcess, 'xray TUN');
    } catch (e, st) {
      AppLogger.instance.error(
        'Linux tunnel start failed',
        error: e,
        stackTrace: st,
      );
      await _dumpLogsToFile();
      await _cleanupForRestart();
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
    final bin = await LinuxCorePaths.xrayExecutable();
    if (bin == null) {
      throw VpnStartException(
        'xray not found. ${LinuxCorePaths.binariesHint}',
      );
    }

    final metricsPort = await _freePort();
    final xrayLog = XraySessionLog.raise(request.xrayConfig);
    _xrayLogThreshold = xrayLog.threshold;
    final configFile = File(p.join(_sessionDir!.path, 'xray.json'));
    await configFile.writeAsString(withXrayDesktopSession(
      xrayLog.config,
      metricsPort: metricsPort,
      processLog: request.debugMode,
    ));
    _xrayMetricsPort = metricsPort;

    // HTTP-инбаунд ядро поднимает всегда (через него ходит апдейтер), занятый порт роняет всё
    await _ensurePortsAvailable(request, needsHttp: true);

    final geoDir = await LinuxCorePaths.geoAssetDir();
    _xrayProcess = await Process.start(
      bin,
      ['run', '-c', configFile.path],
      workingDirectory: _sessionDir!.path,
      environment: {'XRAY_LOCATION_ASSET': ?geoDir},
      mode: ProcessStartMode.normal,
    );
    _pipeProcessOutput(_xrayProcess!, _xrayLog);

    final socksReady = await _waitForPort(
      '127.0.0.1',
      request.socksPort,
      process: _xrayProcess,
      log: _xrayLog,
      processLabel: 'xray',
    );
    if (!socksReady) {
      throw VpnStartException(
        'xray SOCKS port ${request.socksPort} did not open.\n${_tail(_xrayLog)}',
      );
    }

    if (request.systemProxy) {
      final httpReady = await _waitForPort(
        '127.0.0.1',
        request.httpPort,
        process: _xrayProcess,
        log: _xrayLog,
        processLabel: 'xray HTTP',
      );
      if (!httpReady) {
        throw VpnStartException(
          'xray HTTP port ${request.httpPort} did not open. '
          'System proxy needs the HTTP inbound.\n${_tail(_xrayLog)}',
        );
      }
      await _applySystemProxy(request);
    }
  }

  Future<void> _startXrayTunSession(TunnelSessionRequest request) async {
    await _ensurePortsAvailable(request, needsHttp: true);

    final metricsPort = await _freePort();
    final xrayLog = XraySessionLog.raise(request.xrayConfig);
    _xrayLogThreshold = xrayLog.threshold;
    _xrayMetricsPort = metricsPort;
    await _runXrayAsRoot(withXrayDesktopSession(
      xrayLog.config,
      metricsPort: metricsPort,
    ));
  }

  Future<void> _startMihomoSession(TunnelSessionRequest request) async {
    final bin = await LinuxCorePaths.mihomoExecutable();
    if (bin == null) {
      throw VpnStartException(
        'mihomo not found. ${LinuxCorePaths.binariesHint}',
      );
    }
    final config = request.mihomoConfig;
    if (config == null || config.isEmpty) {
      throw const VpnStartException('mihomoConfig is required for mihomo');
    }

    final isTun = request.mode == ConnectionMode.tun;
    await _ensurePortsAvailable(request, needsHttp: true);

    // ядро ждёт .yaml, а JSON для YAML 1.2 подмножество
    final configFile = File(p.join(_sessionDir!.path, 'mihomo.yaml'));
    await configFile.writeAsString(config);

    if (isTun) {
      _mihomoRunsAsRoot = true;
      // дом в каталоге сессии: иначе root наплодил бы в кэше файлов, которые обычный запуск не перепишет
      final home = await _stageGeoAssetsForRoot() ?? _sessionDir!.path;
      final rootBin = await _stageBinaryForRoot(bin, 'mihomo');

      _mihomoProcess = await _startElevatedCore(
        binPath: rootBin,
        configPath: configFile.path,
        geoOrHomeDir: home,
        kind: 'mihomo',
        label: 'mihomo',
        log: _rootLog,
        onStarted: (p) => _mihomoProcess = p,
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
            ? _tail(_rootLog)
            : _tail(StringBuffer(coreLog));
        throw VpnStartException(tunStartFailureMessage(
          fallback: 'The mihomo TUN tunnel did not start.',
          coreOutput: coreLog.trim().isEmpty ? _rootLog.toString() : coreLog,
          windows: false,
          tail: tail,
        ));
      }
      return;
    }

    _mihomoRunsAsRoot = false;
    _mihomoProcess = await Process.start(
      bin,
      ['-d', await LinuxCorePaths.mihomoHomeDir(), '-f', configFile.path],
      workingDirectory: _sessionDir!.path,
      mode: ProcessStartMode.normal,
    );
    _pipeProcessOutput(_mihomoProcess!, _xrayLog);

    final socksReady = await _waitForPort(
      '127.0.0.1',
      request.socksPort,
      process: _mihomoProcess,
      log: _xrayLog,
      processLabel: 'mihomo',
    );
    if (!socksReady) {
      throw VpnStartException(
        'mihomo SOCKS port ${request.socksPort} did not open.\n'
        '${_tail(_xrayLog)}',
      );
    }

    if (request.systemProxy) {
      final httpReady = await _waitForPort(
        '127.0.0.1',
        request.httpPort,
        process: _mihomoProcess,
        log: _xrayLog,
        processLabel: 'mihomo HTTP',
      );
      if (!httpReady) {
        throw VpnStartException(
          'mihomo HTTP port ${request.httpPort} did not open. '
          'System proxy needs the HTTP inbound.\n${_tail(_xrayLog)}',
        );
      }
      await _applySystemProxy(request);
    }
  }

  // путь версионирован: тело обёртки это контракт по позициям аргументов, и со старым путём
  // у тех, кто уже поставил правило, mihomo запускался бы командой keqrnel

  static const _polkitHelperPath = '/usr/local/lib/keqdroid/core-tun-root';

  // старый хелпер сносим, иначе он остался бы разрешён в polkit навсегда
  static const _legacyPolkitHelperPath =
      '/usr/local/lib/keqdroid/keqrnel-tun-root';

  static const _polkitRulePath = '/etc/polkit-1/rules.d/49-keqdroid-tun.rules';

  static const _trustedCoresDir = '/usr/local/lib/keqdroid/cores';

  static const _runRootDir = '/run/keqdroid';

  // v5 и старше обнуляли от root любой файл из аргумента, поэтому такой хелпер считается неустановленным
  static const _helperVersionMark = '[wrap v6';

  static const _untrustedCoreExit = 4;

  @visibleForTesting
  static String get tunWrapperBodyForTest => _tunWrapperBody;

  @visibleForTesting
  static String get polkitRuleForTest => _polkitRuleContent;

  @visibleForTesting
  static const polkitHelperPathForTest = _polkitHelperPath;

  @visibleForTesting
  static const helperVersionMarkForTest = _helperVersionMark;

  // беспарольный хелпер может позвать любая программа пользователя, поэтому названное в аргументах читается его правами,
  // а root пишет только в свой /run/keqdroid/<uid>. журнал отдан владельцу 0600: в нём адреса серверов.
  // ядро без пароля только доверенная копия и под systemd с ProtectSystem=strict: подсунутый конфиг не допишет файлы мимо RUN
  static const _tunWrapperBody = r'''umask 022
SB="$1"; CFG="$2"; GEO="$3"; SENT="$4"; APPPID="$5"; KIND="$6"
HELPER=/usr/local/lib/keqdroid/core-tun-root
CORES=/usr/local/lib/keqdroid/cores
case "$KIND" in xray) NAME=keqrnel; EXT=json ;; mihomo) NAME=mihomo; EXT=yaml ;; *) exit 5 ;; esac
case "$APPPID" in ''|*[!0-9]*) exit 5 ;; esac
OWNER="${PKEXEC_UID:-$(id -u)}"
case "$OWNER" in ''|*[!0-9]*) exit 5 ;; esac
if command -v setpriv >/dev/null 2>&1; then
  GID=$(getent passwd "$OWNER" | cut -d: -f4)
  case "$GID" in ''|*[!0-9]*) exit 5 ;; esac
  as_owner() { setpriv --reuid="$OWNER" --regid="$GID" --clear-groups "$@"; }
elif [ "$0" = "$HELPER" ]; then
  exit 5
else
  as_owner() { "$@"; }
fi
if [ "$0" != "$HELPER" ] && [ -f "$HELPER" ] && ! grep -q '\[wrap v6' "$HELPER"; then
  rm -f "$HELPER" /usr/local/lib/keqdroid/keqrnel-tun-root /etc/polkit-1/rules.d/49-keqdroid-tun.rules
fi
RUN=/run/keqdroid/$OWNER
UNIT=keqdroid-core-$OWNER
SANDBOX=
[ -d /run/systemd/system ] && command -v systemd-run >/dev/null 2>&1 && SANDBOX=1
[ -n "$SANDBOX" ] && { systemctl stop "$UNIT"; systemctl reset-failed "$UNIT"; } >/dev/null 2>&1
mkdir -p /run/keqdroid && rm -rf "$RUN" && mkdir -m 0755 "$RUN" "$RUN/home" || exit 5
LOGF=$RUN/core.log
: >"$LOGF" && chown "$OWNER" "$LOGF" && chmod 0600 "$LOGF" || exit 5
if [ "$0" = "$HELPER" ]; then
  [ "$(as_owner cat -- "$SB" | sha256sum)" = "$(sha256sum <"$CORES/$NAME")" ] || exit 4
  SB=$CORES/$NAME
fi
CONF=$RUN/config.$EXT
as_owner cat -- "$CFG" >"$CONF" || exit 5
for f in geoip.dat geosite.dat; do
  [ -n "$GEO" ] && as_owner test -f "$GEO/$f" && as_owner cat -- "$GEO/$f" >"$RUN/home/$f"
done
: >"$RUN/core.auth"
echo "[wrap v6] start KIND=$KIND sandbox=${SANDBOX:-no} app=$(kill -0 "$APPPID" 2>/dev/null && echo y || echo n)" >>"$LOGF"
if [ ! -e /dev/net/tun ]; then
  echo "[wrap] /dev/net/tun missing, loading module" >>"$LOGF"
  modprobe tun >>"$LOGF" 2>&1 || echo "[wrap] modprobe tun failed" >>"$LOGF"
fi
if [ "$KIND" = mihomo ]; then
  set -- "$SB" -d "$RUN/home" -f "$CONF"
else
  set -- "$SB" run -c "$CONF"
fi
if [ -n "$SANDBOX" ]; then
  systemd-run --quiet --collect --wait --pipe --unit="$UNIT" -p ProtectSystem=strict -p ProtectHome=read-only -p ReadWritePaths="$RUN" --setenv=XRAY_LOCATION_ASSET="$RUN/home" "$@" >>"$LOGF" 2>&1 &
else
  XRAY_LOCATION_ASSET="$RUN/home" "$@" >>"$LOGF" 2>&1 &
fi
sb=$!
while [ -e "$SENT" ] && kill -0 "$APPPID" 2>/dev/null; do
  kill -0 "$sb" 2>/dev/null || break
  sleep 1
done
echo "[wrap v6] stop sent=$([ -e "$SENT" ] && echo y || echo n) app=$(kill -0 "$APPPID" 2>/dev/null && echo y || echo n) core=$(kill -0 "$sb" 2>/dev/null && echo y || echo n)" >>"$LOGF"
[ -n "$SANDBOX" ] && systemctl stop "$UNIT" >/dev/null 2>&1
kill -TERM "$sb" 2>/dev/null
wait "$sb"
''';

  static const _polkitRuleContent =
      '''// keqdroid: passwordless authorization for TUN mode.
// Removing this file restores the password prompt on every TUN connect.
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.policykit.exec" &&
        action.lookup("program") == "$_polkitHelperPath" &&
        subject.local && subject.active) {
        return polkit.Result.YES;
    }
});
''';

  // правило не статим: /etc/polkit-1/rules.d с правами 0700, existsSync оттуда всегда false. признак это хелпер
  static bool isPasswordlessTunInstalled() {
    if (!Platform.isLinux) return false;
    try {
      final helper = File(_polkitHelperPath);
      return helper.existsSync() &&
          helper.readAsStringSync().contains(_helperVersionMark);
    } catch (_) {
      return false;
    }
  }

  // отказ хранится файлом у данных приложения: он про эту машину, в резервную копию на другой компьютер ехать не должен
  static Future<File> _passwordlessOffMarker() async => File(p.join(
      (await getApplicationSupportDirectory()).path, 'tun_password_always'));

  static Future<bool> passwordlessTunDeclined() async {
    if (!Platform.isLinux) return false;
    try {
      return (await _passwordlessOffMarker()).existsSync();
    } catch (_) {
      return false;
    }
  }

  // с runAfter тот же root сразу запускает ядро через новый хелпер: один пароль на установку и подключение
  static Future<String> _installScript({required bool runAfter}) async {
    final helper = '#!/bin/sh\n$_tunWrapperBody';
    final cores = <String, String?>{
      'keqrnel': await LinuxCorePaths.xrayExecutable(),
      'mihomo': await LinuxCorePaths.mihomoExecutable(),
    };
    final installCores = [
      for (final MapEntry(:key, :value) in cores.entries)
        if (value != null)
          "install -m 0755 ${_shellQuote(value)} '$_trustedCoresDir/$key'",
    ].join('\n');
    final run = runAfter ? "set +e\nexec '$_polkitHelperPath' \"\$@\"\n" : '';
    // <<'EOF' в кавычках: $1 и $(...) пишутся в файл буквально
    return '''
set -e
mkdir -p /usr/local/lib/keqdroid '$_trustedCoresDir'
rm -f '$_legacyPolkitHelperPath'
$installCores
cat > '$_polkitHelperPath' <<'KEQDROID_HELPER_EOF'
$helper
KEQDROID_HELPER_EOF
chmod 0755 '$_polkitHelperPath'
chown root:root '$_polkitHelperPath' 2>/dev/null || true
mkdir -p /etc/polkit-1/rules.d
cat > '$_polkitRulePath' <<'KEQDROID_RULE_EOF'
$_polkitRuleContent
KEQDROID_RULE_EOF
chmod 0644 '$_polkitRulePath'
chown root:root '$_polkitRulePath' 2>/dev/null || true
$run''';
  }

  @visibleForTesting
  static Future<String> installScriptForTest({required bool runAfter}) =>
      _installScript(runAfter: runAfter);

  static Future<bool> installPasswordlessTun() async {
    if (!Platform.isLinux) return false;
    try {
      final res = await Process.run(
        'pkexec',
        ['sh', '-c', await _installScript(runAfter: false)],
      );
      if (res.exitCode != 0) {
        AppLogger.instance.warn(
          'installPasswordlessTun failed: code=${res.exitCode} '
          'err=${res.stderr}',
        );
        return false;
      }
      final marker = await _passwordlessOffMarker();
      if (marker.existsSync()) await marker.delete();
      return true;
    } catch (e, st) {
      AppLogger.instance
          .error('installPasswordlessTun error', error: e, stackTrace: st);
      return false;
    }
  }

  static Future<bool> removePasswordlessTun() async {
    if (!Platform.isLinux) return false;
    final script =
        "rm -f '$_polkitHelperPath' '$_legacyPolkitHelperPath' '$_polkitRulePath'; "
        "rm -rf '$_trustedCoresDir'";
    try {
      final res = await Process.run('pkexec', ['sh', '-c', script]);
      if (res.exitCode != 0) return false;
      final marker = await _passwordlessOffMarker();
      await marker.parent.create(recursive: true);
      await marker.writeAsString('1');
      return true;
    } catch (e, st) {
      AppLogger.instance
          .error('removePasswordlessTun error', error: e, stackTrace: st);
      return false;
    }
  }

  static String _shellQuote(String value) =>
      "'${value.replaceAll("'", r"'\''")}'";

  // своё имя, а не xray: pkill -x в _stopRootCore иначе задел бы чужие xray в системе
  static const _rootXrayName = 'keqdroid-xray';

  Future<void> _runXrayAsRoot(String config) async {
    final bin = await LinuxCorePaths.xrayExecutable();
    if (bin == null) {
      throw VpnStartException(
        'xray not found (required for TUN mode). ${LinuxCorePaths.binariesHint}',
      );
    }

    final configFile = File(p.join(_sessionDir!.path, 'xray-tun.json'));
    await configFile.writeAsString(config);
    final rootGeoDir = await _stageGeoAssetsForRoot();
    final rootBin = await _stageBinaryForRoot(bin, _rootXrayName);

    _xrayStarted = false;
    _rootXrayProcess = await _startElevatedCore(
      binPath: rootBin,
      configPath: configFile.path,
      geoOrHomeDir: rootGeoDir ?? '',
      kind: 'xray',
      label: 'xray',
      log: _rootLog,
      onStarted: (p) => _rootXrayProcess = p,
    );
    _startRootLogTail();

    final ready = await _waitForTunCore(
      process: _rootXrayProcess!,
      log: _rootLog,
      started: () => _xrayStarted,
    );

    if (!ready) {
      final coreLog = await _readRootCoreLog();
      final tail = coreLog.trim().isEmpty
          ? _tail(_rootLog)
          : _tail(StringBuffer(coreLog));
      throw VpnStartException(tunStartFailureMessage(
        fallback: 'The TUN tunnel did not start.',
        coreOutput: coreLog.trim().isEmpty ? _rootLog.toString() : coreLog,
        windows: false,
        tail: tail,
      ));
    }
  }

  // вывод root-ядра обёртка пишет в файл, а не в наш pipe, а по его строкам работают Соединения и счётчик отказов
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
      final lines = (_rootLogPending +
              const Utf8Decoder(allowMalformed: true).convert(bytes))
          .split('\n');
      _rootLogPending = lines.removeLast();
      for (final line in lines) {
        _appendCoreLine(_xrayLog, line.trimRight());
      }
    } catch (_) {
    } finally {
      await file?.close();
      _rootLogReading = false;
    }
  }

  // монт AppImage root не видит, pkexec падает с Permission denied, поэтому копия в каталоге сессии
  Future<String> _stageBinaryForRoot(String binPath, String name) async {
    final staged = p.join(_sessionDir!.path, name);
    try {
      await File(binPath).copy(staged);
      await Process.run('chmod', ['0755', staged]);
    } catch (e) {
      throw VpnStartException('Could not stage $name for elevation: $e');
    }
    return staged;
  }

  Future<String> _readRootCoreLog() async {
    try {
      return await File(_coreLogPath).readAsString();
    } catch (_) {
      return '';
    }
  }

  // onStarted сразу после запуска: стоп в этом окне обязан найти процесс и снять сентинел,
  // иначе root-ядро останется с поднятым TUN
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
    // pkexec не пробрасывает сигналы root-потомку, а stdin у него сразу на EOF,
    // поэтому жизнь ядра привязана к файлу-сентинелу и kill -0 по pid приложения
    final sentinelFile = File(p.join(_sessionDir!.path, 'core.run'));
    await sentinelFile.writeAsString('1');
    _rootSentinel = sentinelFile;
    // маркер создаёт обёртка сразу после polkit: по нему отличаем ввод пароля от старта ядра.
    // каталог переживает сессию, поэтому маркер прошлой отсекаем по времени
    final authMarker = File(p.join(_rootRunDir, 'core.auth'));
    _rootCoreLaunchedAt = DateTime.now();

    // позиции аргументов это контракт с телом обёртки, менять только вместе с меткой версии хелпера
    final coreArgs = <String>[
      binPath,
      configPath,
      geoOrHomeDir,
      sentinelFile.path,
      '$pid',
      kind,
    ];
    final asRoot = runningAsRoot();
    final usePasswordless = allowPasswordless && isPasswordlessTunInstalled();
    final installNow =
        !asRoot && !usePasswordless && !await passwordlessTunDeclined();
    final launch = planElevation(
      coreArgs: coreArgs,
      wrapperBody: installNow
          ? await _installScript(runAfter: true)
          : _tunWrapperBody,
      helperPath: _polkitHelperPath,
      asRoot: asRoot,
      passwordless: usePasswordless,
    );
    if (launch.viaPkexec && LinuxCorePaths.findPkexec() == null) {
      throw const VpnStartException(
        'TUN mode needs root through pkexec, and polkit is not installed. '
        'Install polkit with an authentication agent, run the app as root '
        '(sudo), or use Proxy mode.',
      );
    }
    final Process process;
    try {
      process = await Process.start(
        launch.executable,
        launch.args,
        workingDirectory: _sessionDir!.path,
        mode: ProcessStartMode.normal,
      );
    } on ProcessException catch (e) {
      // только message: $e затащил бы сюда команду целиком
      throw VpnStartException(
        'Could not launch $label with elevated privileges through '
        '${launch.executable}: ${e.message}',
      );
    }
    onStarted(process);
    _pipeProcessOutput(process, log);

    // сначала ждём polkit: иначе бюджет готовности TUN тикал, пока человек вводил пароль
    final authorized = await _waitForElevation(
      process: process,
      authMarker: authMarker,
      log: log,
      untrustedCoreExit: usePasswordless ? _untrustedCoreExit : null,
    );
    if (!authorized) {
      AppLogger.instance.info(
        '$label changed since passwordless TUN was set up; asking for the '
        'password once to trust the new one',
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

  Future<bool> _waitForElevation({
    required Process process,
    required File authMarker,
    required StringBuffer log,
    int? untrustedCoreExit,
  }) async {
    const maxWait = Duration(minutes: 2);
    final sw = Stopwatch()..start();
    while (sw.elapsed < maxWait) {
      final code = await _exitCodeOrNull(process);
      if (code != null) {
        if (code == untrustedCoreExit) return false;
        throw VpnStartException(_elevationError(code, log));
      }
      if (_freshSince(authMarker, _rootCoreLaunchedAt)) return true;
      if (await _tunInterfaceExists()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    // auth не выдана и root-потомка ещё нет, сворачивать pkexec безопасно
    try {
      process.kill(ProcessSignal.sigterm);
    } catch (_) {}
    throw const VpnStartException(
      'Polkit authorization timed out (2 min). Approve the password prompt '
      'to start TUN mode, or use Proxy mode.',
    );
  }

  // у xray устройство появляется раньше маршрутов, готовность по его строке started
  Future<bool> _waitForTunCore({
    required Process process,
    required StringBuffer log,
    bool Function()? started,
  }) async {
    var waited = 0;
    while (waited < 20000) {
      final code = await _exitCodeOrNull(process);
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

    try {
      final coreLog = await File(_coreLogPath).readAsString();
      if (coreLog.trim().isNotEmpty) {
        log
          ..writeln('=== core log (timeout) ===')
          ..writeln(coreLog);
      }
    } catch (_) {}

    final stillRunning = await _exitCodeOrNull(process);
    if (stillRunning != null) {
      throw VpnStartException(_elevationError(stillRunning, log));
    }
    return false;
  }

  // 126 значит окно пароля закрыли, 127 не авторизовано или нет агента polkit
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
        var coreTail = '';
        try {
          final coreLog = File(_coreLogPath);
          final launchedAt = _rootCoreLaunchedAt;
          if (launchedAt != null &&
              !coreLog.lastModifiedSync().isBefore(launchedAt)) {
            coreTail = coreLog.readAsStringSync().trim();
          }
        } catch (_) {}
        final detail =
            coreTail.isNotEmpty ? _tail(StringBuffer(coreTail)) : _tail(log);
        final hint = tunFailureHint(
          coreTail.isNotEmpty ? coreTail : log.toString(),
          windows: false,
        );
        if (hint != null) {
          return 'The tunnel core exited with code $code.\n'
              '${hint.message}\n$detail';
        }
        return 'The tunnel core exited with code $code (TUN/elevation failed?).\n'
            '$detail';
    }
  }

  // секунда запаса: у tmpfs время файла и наши часы могут разойтись на доли секунды
  static bool _freshSince(File file, DateTime? since) {
    try {
      if (!file.existsSync()) return false;
      if (since == null) return true;
      return !file
          .lastModifiedSync()
          .isBefore(since.subtract(const Duration(seconds: 1)));
    } catch (_) {
      return false;
    }
  }

  Future<bool> _tunInterfaceExists() async {
    return Directory('/sys/class/net/$tunInterfaceName').exists();
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
    final ok = await (await LinuxSystemProxy.system()).enable(
      httpPort: request.httpPort,
      socksPort: request.socksPort,
    );
    if (!ok) {
      AppLogger.instance.warn(
        'Could not set the system proxy (neither gsettings nor KDE settings '
        'are available). The local proxy is up on 127.0.0.1: '
        'SOCKS ${request.socksPort} / HTTP ${request.httpPort}.',
      );
    }
  }

  static Future<void> _restoreSystemProxy() async {
    try {
      await (await LinuxSystemProxy.system()).disable();
    } catch (e) {
      AppLogger.instance.warn('Could not restore the system proxy', error: e);
    }
  }

  static Future<void> cleanupStaleState() => _restoreSystemProxy();

  void _watchProcessExit(Process? process, String label) {
    if (process == null) return;
    unawaited(process.exitCode.then((code) async {
      if (_stoppingSession) return;
      if (!identical(process, _xrayProcess) &&
          !identical(process, _rootXrayProcess) &&
          !identical(process, _mihomoProcess)) {
        return;
      }
      AppLogger.instance.error(
        '$label exited unexpectedly with code $code; tearing the session down',
      );
      try {
        await stopSession();
      } catch (_) {}
      emit(VpnState(
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

  // без эмитов: disconnected из стрима проходит в UI и при connect-in-flight, кнопка проваливалась в серое
  Future<void> _cleanupForRestart() async {
    _stoppingSession = true;
    try {
      await _stopSessionInner(emitStates: false);
    } finally {
      _stoppingSession = false;
    }
  }

  Future<void> _stopSessionInner({bool emitStates = true}) async {
    stopStatsLoop();
    if (emitStates) emit(const VpnState(status: VpnStatus.disconnecting));

    if (_rootXrayProcess != null ||
        _xrayProcess != null ||
        _mihomoProcess != null) {
      await _dumpLogsToFile();
    }

    // прокси возвращаем всегда, даже если ставил не этот экземпляр (прошлое падение)
    await _restoreSystemProxy();

    // сначала ядро с TUN: трафик должен падать закрытым, а не в мёртвый socks
    await _stopRootCore(_rootXrayProcess, 'keqrnel|$_rootXrayName');
    _stopRootLogTail();
    if (_mihomoRunsAsRoot) {
      await _stopRootCore(_mihomoProcess, 'mihomo');
    } else {
      await _killProcess(_mihomoProcess);
    }
    await _killProcess(_xrayProcess);
    _rootXrayProcess = null;
    _mihomoProcess = null;
    _mihomoRunsAsRoot = false;
    _xrayProcess = null;
    _xrayMetricsPort = null;

    final dir = _sessionDir;
    _sessionDir = null;
    if (dir != null && dir.existsSync()) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }

    _activeMode = null;
    if (identical(activeInstance, this)) activeInstance = null;
    if (emitStates) emit(VpnState.disconnected);
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
          exePath = null;
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
    >?
  >
  xrayUrlTestMulti({
    required String config,
    required List<(String id, int port)> probes,
    VpnBackend core = VpnBackend.xray,
    String testUrl = 'https://connectivitycheck.gstatic.com/generate_204',
    int timeoutMs = 15000,
    bool keepAlive = true,
    int concurrency = 16,
    UrlTestProgress? onEach,
  }) async =>
      null;

  @override
  Future<
    List<
      ({String id, bool success, int? latencyMs, String error, int? httpStatus})
    >
  >
  xrayUrlTestBatch({
    required List<(String id, String xrayConfig)> items,
    required int socksPort,
    VpnBackend core = VpnBackend.xray,
    String testUrl = 'https://connectivitycheck.gstatic.com/generate_204',
    int timeoutMs = 15000,
    bool keepAlive = true,
  }) async {
    if (items.isEmpty) return [];
    final raw = await EphemeralXrayPing.urlTestBatch(
      items: items.map((e) => (id: e.$1, xrayConfigJson: e.$2)).toList(),
      socksPort: socksPort,
      core: core,
      testUrl: testUrl,
      timeoutMs: timeoutMs,
      keepAlive: keepAlive,
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
    VpnBackend core = VpnBackend.xray,
    String downloadUrl = kDefaultSpeedTestUrl,
    int timeoutMs = 20000,
  }) async {
    if (items.isEmpty) return [];
    return EphemeralXrayPing.speedTestBatch(
      items: items.map((e) => (id: e.$1, xrayConfigJson: e.$2)).toList(),
      socksPort: socksPort,
      core: core,
      downloadUrl: downloadUrl,
      timeoutMs: timeoutMs,
    );
  }

  static final _xrayStartedLine = RegExp(r'\bXray \S+ started\b');

  void _appendCoreLine(StringBuffer buffer, String line) {
    if (!_xrayStarted && _xrayStartedLine.hasMatch(line)) _xrayStarted = true;
    CoreDialFailures.observe(line);
    XrayRouteDecisions.observe(line);
    if (!XraySessionLog.keep(line, _xrayLogThreshold)) return;
    buffer.writeln(line);
    if (buffer.length > 64 * 1024) {
      final trimmed = _tail(buffer, maxLines: 200);
      buffer
        ..clear()
        ..writeln(trimmed);
    }
  }

  void _pipeProcessOutput(Process process, StringBuffer buffer) {
    void append(String line) => _appendCoreLine(buffer, line);

    // allowMalformed: строка ядра не в UTF-8 иначе роняет весь пайп лога
    const decoder = Utf8Decoder(allowMalformed: true);
    // строки режем по всему потоку: кусок пайпа обрывается где попало
    process.stderr
        .transform(decoder)
        .transform(const LineSplitter())
        .listen(append);
    process.stdout
        .transform(decoder)
        .transform(const LineSplitter())
        .listen(append);
  }

  // убитый сигналом процесс на Linux даёт отрицательный код, поэтому вышел значит не null
  static Future<int?> _exitCodeOrNull(Process process) => process.exitCode
      .then<int?>((c) => c)
      .timeout(const Duration(milliseconds: 1), onTimeout: () => null);

  Future<void> _stopRootCore(Process? proc, String coreName) async {
    if (proc == null) return;
    try {
      final sentinel = _rootSentinel;
      if (sentinel != null && sentinel.existsSync()) sentinel.deleteSync();
    } catch (_) {}
    _rootSentinel = null;
    try {
      await proc.exitCode.timeout(const Duration(seconds: 8));
    } catch (_) {
      // обёртка не вышла вовремя: добиваем, чтобы root-ядро не держало TUN (может спросить пароль)
      try {
        await Process.run('pkexec', ['pkill', '-TERM', '-x', coreName]);
      } catch (_) {}
      try {
        proc.kill(ProcessSignal.sigkill);
      } catch (_) {}
    }

    // процесс мёртв, а устройство ещё нет: поверх живого tun-keqdis следующая сессия падает
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
        final code = await _exitCodeOrNull(process);
        if (code != null) {
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
    final socksIssue =
        await LocalPortResolver.probe('127.0.0.1', request.socksPort);
    if (socksIssue != null) {
      throw VpnStartException(
        localPortBlockedMessage(
          label: 'SOCKS',
          port: request.socksPort,
          issue: socksIssue,
        ),
      );
    }
    if (!needsHttp) return;
    final httpIssue =
        await LocalPortResolver.probe('127.0.0.1', request.httpPort);
    if (httpIssue != null) {
      throw VpnStartException(
        localPortBlockedMessage(
          label: 'HTTP',
          port: request.httpPort,
          issue: httpIssue,
        ),
      );
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

  @override
  void emit(VpnState state) {
    if (!_stateCtrl.isClosed) _stateCtrl.add(state);
  }




  // счётчики API ядра, а не интерфейса: рукопожатия TCP отвечает локальный стек,
  // и пришло было бы и от мёртвого сервера
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
  Future<void> pollTrafficStats(ConnectionMode mode, {bool force = false}) async {
    if (!statsPollingEnabled && !force) return;
    if (_xrayProcess == null &&
        _mihomoProcess == null &&
        _rootXrayProcess == null) {
      return;
    }
    try {
      final int inOctets;
      final int outOctets;

      if (_mihomoProcess != null) {
        final api = MihomoApiSession();
        final port = api.port;
        if (port == null) {
          emitConnectedTelemetry(mode);
          return;
        }
        final t = await queryClashTraffic(port, secret: api.secret);
        if (t == null) {
          emitConnectedTelemetry(mode);
          return;
        }
        inOctets = t.down;
        outOctets = t.up;
      } else if (mode == ConnectionMode.tun) {
        // в интерфейс ядро ОС пишет исходящее (tx) и читает ответы (rx)
        final c = await _queryTunCounters();
        if (c == null) {
          emitConnectedTelemetry(mode);
          return;
        }
        inOctets = c.rx;
        outOctets = c.tx;
      } else if (_xrayMetricsPort != null) {
        final t = await queryXrayTraffic(_xrayMetricsPort!);
        if (t == null) {
          emitConnectedTelemetry(mode);
          return;
        }
        inOctets = t.down;
        outOctets = t.up;
      } else {
        return;
      }

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
      AppLogger.instance.debug('Linux getTrafficStats failed: $e');
    }
  }




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



}
