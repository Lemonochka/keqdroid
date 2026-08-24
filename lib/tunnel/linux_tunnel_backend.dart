import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/app_logger.dart';
import '../core/exceptions.dart';
import '../services/ephemeral_xray_ping.dart';
import '../utils/keqrnel_config.dart';
import '../utils/mihomo_api_session.dart';
import '../utils/singbox_tun_config.dart';
import '../utils/wireproxy_config.dart';
import 'connection_mode.dart';
import 'core_capabilities.dart';
import 'desktop_traffic_stats.dart';
import 'linux_core_paths.dart';
import 'local_port_plan.dart';
import 'socks_credential_generator.dart';
import 'tun_failure_hints.dart';
import 'tunnel_backend.dart';
import 'tunnel_session_request.dart';
import 'tunnel_state.dart';
import 'vpn_backend.dart';
import 'xray_session_stats.dart';

/// Пульс «прошла polkit-аутентификация для TUN, а беспарольного правила ещё
/// нет». Десктопный UI на Linux слушает поток и предлагает один раз установить
/// правило, чтобы дальше TUN стартовал без пароля. См.
/// [LinuxTunnelBackend.installPasswordlessTun].
final StreamController<void> _linuxTunRememberController =
    StreamController<void>.broadcast();
Stream<void> get linuxTunRememberOffers => _linuxTunRememberController.stream;

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
class LinuxTunnelBackend with DesktopTrafficStats implements TunnelBackend {
  static const tunInterfaceName = 'tun-keqdis';

  /// Куда root-обёртка pkexec редиректит stdout/stderr ядра (см.
  /// [_runKeqrnelAsRoot]): pkexec не держит наш pipe, и без файла реальная
  /// причина падения ядра терялась — наружу уходил только generic exit code.
  static const _coreLogPath = '/tmp/keqdroid_keqrnel.log';

  /// Момент запуска pkexec текущей сессии — [_coreLogPath] обнуляется только
  /// внутри root-обёртки, так что при падении ДО неё (сам pkexec) файл ещё
  /// хранит прошлую сессию; по mtime отличаем свежий лог от застарелого.
  DateTime? _keqrnelLaunchedAt;

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
  ConnectionMode? _activeMode;

  @override
  ConnectionMode? get activeMode => _activeMode;
  final StringBuffer _xrayLog = StringBuffer();
  final StringBuffer _singboxLog = StringBuffer();

  int? _awgInfoPort;
  String? _xrayBinPath;
  // Порт clash_api keqrnel — из него читаем кумулятивный трафик (proxy-режим)
  // и список соединений для дебаг-экрана (оба режима).
  int? _keqrnelClashPort;

  // mihomo: одно ядро на оба режима. В proxy-режиме обычный процесс, в TUN —
  // тот же root-путь через pkexec, что и у keqrnel (tun-устройство и маршруты
  // без root не создать).
  Process? _mihomoProcess;

  /// Порт clash_api активной сессии; null — сессии нет или API не поднят.
  /// Читает [ConnectionsService].
  ///
  /// У mihomo координаты API придумывает не бэкенд, а тот же код, что собирал
  /// конфиг ([MihomoApiSession]) — порт и `secret` едут внутрь конфига.
  int? get clashApiPort =>
      _keqrnelClashPort ??
      (_mihomoProcess != null ? MihomoApiSession().port : null);

  /// PID живых процессов ядра: подпись → pid. Пустая карта — сессии нет.
  /// Читает панель «Внутренности».
  ///
  /// У root-процесса TUN это pid обёртки (pkexec/helper), а не самого ядра:
  /// ядро он поднимает уже под собой, и его pid этой стороне не виден.
  Map<String, int> get activeCorePids => {
    if (_xrayProcess != null) 'keqrnel': _xrayProcess!.pid,
    if (_mihomoProcess != null)
      _mihomoRunsAsRoot ? 'mihomo (root, TUN)' : 'mihomo': _mihomoProcess!.pid,
    if (_wireproxyProcess != null) 'wireproxy': _wireproxyProcess!.pid,
    if (_singboxProcess != null) 'keqrnel (root, TUN)': _singboxProcess!.pid,
  };

  /// TUN-сессия mihomo идёт через pkexec, и остановить её нужно так же, как
  /// keqrnel: удалением сентинела, а не сигналом (обычный пользователь
  /// root-процессу сигнал послать не может).
  bool _mihomoRunsAsRoot = false;

  // true пока идёт штатный stopSession — чтобы вотчдог не принял наш же
  // kill за внезапную смерть ядра.
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
    // Linux doesn't stash these (unlike Windows, which guards startSession on
    // them): the caller applies the returned pair via Socks5Credentials().init.
    return SocksCredentialGenerator.generatePair();
  }

  @override
  Future<void> startSession(TunnelSessionRequest request) async {
    emit(VpnState(status: VpnStatus.connecting, activeMode: request.mode));
    _activeMode = request.mode;
    _xrayLog.clear();
    _singboxLog.clear();

    try {
      await _cleanupForRestart();
      activeInstance = this;
      // _cleanupForRestart() зануляет _activeMode внутри _stopSessionInner —
      // вернуть режим НОВОЙ сессии. Иначе вся сессия живёт с _activeMode=null:
      // getCurrentState теряет режим, а setTrafficStatsPollingEnabled(true)
      // после разворота из трея молча НЕ перезапускает опрос счётчиков —
      // трафик/время замерзают до реконнекта.
      _activeMode = request.mode;
      _sessionDir = await LinuxCorePaths.sessionDir();

      final isTun = request.mode == ConnectionMode.tun;
      switch (request.vpnBackend) {
        case VpnBackend.awg:
          await (isTun
              ? _startAwgTunSession(request)
              : _startAwgProxySession(request));
        case VpnBackend.mihomo:
          await _startMihomoSession(request);
        case VpnBackend.xray:
          await (isTun
              ? _startKeqrnelTunSession(request)
              : _startKeqrnelProxySession(request));
      }

      startStatsLoop(request.mode);
      emitConnectedTelemetry(request.mode);

      // «Ядро поднялось» и «через него что-то ходит» — разные утверждения, и
      // расходятся они постоянно: истёкшая подписка, мёртвый сервер, правило,
      // отправившее всё в block. Снаружи это «подключено, но ничего не
      // грузится» без единой строчки о причине. Проверяем сами — в фоне, чтобы
      // не задерживать подключение.
      unawaited(_verifyChainReachable(request));

      // Смерть ядра посреди сессии без вотчдога оставляла UI в «Connected»,
      // а системный прокси (gsettings) — направленным на мёртвый порт.
      _watchProcessExit(_xrayProcess, 'keqrnel');
      _watchProcessExit(_mihomoProcess, 'mihomo');
      _watchProcessExit(_singboxProcess, 'keqrnel TUN');
      _watchProcessExit(_wireproxyProcess, 'wireproxy');
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
      findProcess: request.debugMode,
    );
    _keqrnelClashPort = clashPort;
    final configFile = File(p.join(_sessionDir!.path, 'keqrnel.json'));
    await configFile.writeAsString(merged);

    // HTTP-инбаунд ядро поднимает всегда (через него ходит апдейтер), поэтому
    // занятый HTTP-порт роняет ядро целиком независимо от системного прокси.
    await _ensurePortsAvailable(request, needsHttp: true);

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
    // Локальные порты в TUN-режиме слушает встроенный xray внутри keqrnel:
    // занял их сосед — ядро падает на старте инбаунда, и наружу это выглядит
    // как «TUN не поднялся», хотя TUN тут ни при чём.
    await _ensurePortsAvailable(request, needsHttp: true);

    final clashPort = await _freePort();
    final merged = KeqrnelConfig.fromChain(
      singboxConfig: singConfig,
      xrayConfig: request.xrayConfig,
      windows: false,
      clashApiPort: clashPort,
    );
    _keqrnelClashPort = clashPort;
    await _runKeqrnelAsRoot(merged);
  }

  // ---- mihomo -------------------------------------------------------------

  /// mihomo — второе полноценное ядро, а не обёртка вокруг keqrnel: в
  /// TUN-режиме tun-устройство и маршруты создаёт оно само (внутри у него тот
  /// же sing-tun), поэтому связки «ядро → локальный SOCKS → keqrnel» здесь нет.
  /// Требование то же, что у keqrnel: root через pkexec.
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
    // Локальные socks/http поднимает то же ядро и в TUN-режиме: через HTTP
    // ходит апдейтер, и занятый соседом порт роняет старт целиком.
    await _ensurePortsAvailable(request, needsHttp: true);

    // Расширение `.yaml` — то, что ядро ждёт; содержимое при этом JSON (YAML 1.2
    // его надмножество, см. MihomoConfigGen).
    final configFile = File(p.join(_sessionDir!.path, 'mihomo.yaml'));
    await configFile.writeAsString(config);

    if (isTun) {
      _mihomoRunsAsRoot = true;
      // Дом для root-запуска — в каталоге сессии, а не в пользовательском
      // кэше: иначе root наплодил бы там своих `config.yaml`/`cache.db`,
      // которые следующий обычный запуск уже не перепишет.
      final home = await _stageGeoAssetsForRoot() ?? _sessionDir!.path;
      final rootBin = await _stageBinaryForRoot(bin, 'mihomo');

      _mihomoProcess = await _startElevatedCore(
        binPath: rootBin,
        configPath: configFile.path,
        geoOrHomeDir: home,
        kind: 'mihomo',
        label: 'mihomo',
        log: _singboxLog,
        onStarted: (p) => _mihomoProcess = p,
      );

      final ready = await _waitForTunCore(
        process: _mihomoProcess!,
        log: _singboxLog,
      );
      final coreLog = await _readRootCoreLog();
      if (coreLog.trim().isNotEmpty) {
        _singboxLog
          ..writeln('=== mihomo (core) ===')
          ..writeln(coreLog);
      }
      if (!ready) {
        final tail = coreLog.trim().isEmpty
            ? _tail(_singboxLog)
            : _tail(StringBuffer(coreLog));
        throw VpnStartException(tunStartFailureMessage(
          fallback: 'The mihomo TUN tunnel did not start.',
          coreOutput: coreLog.trim().isEmpty ? _singboxLog.toString() : coreLog,
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

  // withHttp и в TUN-режиме: процесс приложения идёт мимо TUN (direct-правило
  // sing-box), обновления качаются через локальный HTTP-инбаунд wireproxy.
  Future<void> _startAwgTunSession(TunnelSessionRequest request) async {
    await _startWireproxy(request, withHttp: true);
    final singConfig = request.singboxConfig;
    if (singConfig == null || singConfig.isEmpty) {
      throw const VpnStartException('singboxConfig is required for TUN mode');
    }
    await _runKeqrnelAsRoot(singConfig);
  }

  // ---- passwordless TUN (polkit rule) -------------------------------------

  /// Root-owned хелпер, который pkexec запускает вместо inline `sh -c`.
  /// polkit-правило разрешает беспарольный запуск ИМЕННО этого пути.
  /// Путь версионирован намеренно. Тело обёртки — контракт по позициям
  /// аргументов, а установленный у пользователя хелпер живёт своей жизнью:
  /// добавь мы восьмой аргумент к прежнему пути, у всех, кто уже поставил
  /// беспарольное правило, mihomo молча запускался бы командой keqrnel. Новый
  /// путь честнее: [isPasswordlessTunInstalled] отвечает «нет», пользователь
  /// один раз вводит пароль и ставит правило заново (старый хелпер при этом
  /// удаляется).
  static const _polkitHelperPath = '/usr/local/lib/keqdroid/core-tun-root';

  /// Хелпер прежней версии — умел запускать только keqrnel. Установка новой
  /// его сносит, иначе он остался бы разрешён в polkit навсегда.
  static const _legacyPolkitHelperPath =
      '/usr/local/lib/keqdroid/keqrnel-tun-root';

  /// polkit JS-правило (polkit >= 0.106). Разрешает беспарольный запуск хелпера
  /// для активной локальной сессии.
  static const _polkitRulePath = '/etc/polkit-1/rules.d/49-keqdroid-tun.rules';

  /// Разово за запуск приложения: показали ли уже предложение установить правило.
  static bool _rememberOfferedThisRun = false;

  /// Тело root-обёртки TUN. Один и тот же скрипт запускается двумя путями:
  ///  * правило не стоит → `pkexec sh -c <body> sh <args>` (polkit спросит пароль);
  ///  * правило стоит     → `pkexec <_polkitHelperPath> <args>` (без пароля),
  ///    файл хелпера = shebang + это тело.
  /// Восьмой аргумент — какое ядро запускать: командные строки у них разные
  /// (`keqrnel run -c <cfg>` против `mihomo -d <home> -f <cfg>`), а обёртка
  /// одна. Пустой KIND означает keqrnel — так обёртка ведёт себя как прежняя.
  ///
  /// `modprobe tun` здесь потому, что это ЕДИНСТВЕННОЕ место, где мы root:
  /// без модуля `/dev/net/tun` не существует, и ядро падает на открытии
  /// устройства («no such file or directory») — типовой случай минимальных
  /// сборок ядра и контейнеров. Позиции аргументов при этом не тронуты, так
  /// что уже установленный хелпер прежней версии остаётся корректным (он
  /// просто не умеет этого чинить, и тогда причину называет
  /// [tunFailureHint]).
  static const _tunWrapperBody = r'''SB="$1"; CFG="$2"; GEO="$3"; LOGF="$4"; SENT="$5"; APPPID="$6"; AUTHF="$7"; KIND="$8"
: >"$LOGF"
: >"$AUTHF"
echo "[wrap v4 sentinel] start KIND=$KIND SENT=$SENT exists=$([ -e "$SENT" ] && echo y || echo n) APPPID=$APPPID app=$(kill -0 "$APPPID" 2>/dev/null && echo y || echo n)" >>"$LOGF"
if [ ! -e /dev/net/tun ]; then
  echo "[wrap] /dev/net/tun missing, loading module" >>"$LOGF"
  modprobe tun >>"$LOGF" 2>&1 || echo "[wrap] modprobe tun failed" >>"$LOGF"
fi
if [ "$KIND" = "mihomo" ]; then
  "$SB" -d "$GEO" -f "$CFG" >>"$LOGF" 2>&1 &
else
  if [ -n "$GEO" ]; then export XRAY_LOCATION_ASSET="$GEO"; fi
  "$SB" run -c "$CFG" >>"$LOGF" 2>&1 &
fi
sb=$!
while [ -e "$SENT" ] && kill -0 "$APPPID" 2>/dev/null; do
  kill -0 "$sb" 2>/dev/null || break
  sleep 1
done
echo "[wrap v4 sentinel] stop sent=$([ -e "$SENT" ] && echo y || echo n) app=$(kill -0 "$APPPID" 2>/dev/null && echo y || echo n) sb=$(kill -0 "$sb" 2>/dev/null && echo y || echo n)" >>"$LOGF"
kill -TERM "$sb" 2>/dev/null
wait "$sb"
''';

  /// polkit-правило: беспарольный exec фиксированного хелпера для активной
  /// локальной сессии. Удаление файла возвращает запрос пароля.
  static const _polkitRuleContent =
      '''// keqdroid: passwordless authorization for TUN mode (installed on user request).
// Removing this file restores the password prompt on every TUN connect.
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.policykit.exec" &&
        action.lookup("program") == "$_polkitHelperPath" &&
        subject.local && subject.active) {
        return polkit.Result.YES;
    }
});
''';

  /// Установлено ли беспарольное правило. Признаком берём root-хелпер по
  /// [_polkitHelperPath], а polkit-правило НАМЕРЕННО не статим: каталог
  /// `/etc/polkit-1/rules.d` имеет режим 0700 (root/polkitd), обычный юзер в
  /// него не может зайти — `existsSync` на файле внутри ВСЕГДА вернёт false,
  /// даже когда правило на месте. Гейт по нему держал тумблер вечно
  /// «выключенным» после успешной установки (пользователь вводил пароль,
  /// файлы писались, но UI перечитывал «не установлено» и просил пароль снова).
  /// Хелпер лежит в общедоступном каталоге и ставится/удаляется вместе с
  /// правилом — это верный признак «беспарольный TUN установлен».
  static bool isPasswordlessTunInstalled() {
    if (!Platform.isLinux) return false;
    try {
      return File(_polkitHelperPath).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Ставит root-хелпер и polkit-правило ОДНИМ элевейтед-запуском (polkit
  /// спросит пароль один раз). После этого TUN стартует без пароля. true — успех.
  static Future<bool> installPasswordlessTun() async {
    if (!Platform.isLinux) return false;
    final helper = '#!/bin/sh\n$_tunWrapperBody';
    // Кавычки вокруг разделителей heredoc (<<'EOF') запрещают шеллу разворачивать
    // $1/$SB/$(...) внутри — они пишутся в файлы буквально.
    final script = '''
set -e
mkdir -p /usr/local/lib/keqdroid
rm -f '$_legacyPolkitHelperPath'
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
''';
    try {
      final res = await Process.run('pkexec', ['sh', '-c', script]);
      if (res.exitCode != 0) {
        AppLogger.instance.warn(
          'installPasswordlessTun failed: code=${res.exitCode} '
          'err=${res.stderr}',
        );
      }
      return res.exitCode == 0;
    } catch (e, st) {
      AppLogger.instance
          .error('installPasswordlessTun error', error: e, stackTrace: st);
      return false;
    }
  }

  /// Удаляет root-хелпер и polkit-правило (снова элевейтед-запуск с паролем) —
  /// возвращает поведение к запросу пароля на каждый TUN-коннект.
  static Future<bool> removePasswordlessTun() async {
    if (!Platform.isLinux) return false;
    final script =
        "rm -f '$_polkitHelperPath' '$_legacyPolkitHelperPath' '$_polkitRulePath'";
    try {
      final res = await Process.run('pkexec', ['sh', '-c', script]);
      return res.exitCode == 0;
    } catch (e, st) {
      AppLogger.instance
          .error('removePasswordlessTun error', error: e, stackTrace: st);
      return false;
    }
  }

  // ---- sing-box TUN (root via pkexec) -------------------------------------

  /// Запускает keqrnel под root через pkexec (TUN нужен root). keqrnel — это
  /// sing-box host: поднимает переданный sing-box-конфиг, один и тот же путь
  /// и для xray-протоколов, и для AmneziaWG-TUN.
  Future<void> _runKeqrnelAsRoot(String config) async {
    final singBin = await LinuxCorePaths.keqrnelExecutable();
    if (singBin == null) {
      throw VpnStartException(
        'keqrnel not found (required for TUN mode). ${LinuxCorePaths.binariesHint}',
      );
    }

    // Стек TUN-инбаунда — под возможности ЭТОГО бинаря: ядро без
    // `-tags with_gvisor` на `stack: gvisor` не ругается в конфиге, а падает
    // при старте («gVisor is not included in this build»), и TUN не поднимается
    // вовсе. Поставляемый keqrnel собран с тегом, собранный руками — вряд ли.
    final stackFix = applyTunStackFallback(
      config,
      gvisorAvailable: await CoreCapabilities.hasGvisor(singBin),
    );
    if (stackFix.downgradedFrom != null) {
      AppLogger.instance.warn(
        'TUN stack "${stackFix.downgradedFrom}" needs a core built with '
        '-tags with_gvisor; this keqrnel has none, falling back to "system".',
      );
    }

    final singConfigFile = File(p.join(_sessionDir!.path, 'keqrnel-tun.json'));
    await singConfigFile.writeAsString(stackFix.config);
    final rootGeoDir = await _stageGeoAssetsForRoot();
    final rootSingBin = await _stageBinaryForRoot(singBin, 'keqrnel');

    _singboxProcess = await _startElevatedCore(
      binPath: rootSingBin,
      configPath: singConfigFile.path,
      geoOrHomeDir: rootGeoDir ?? '',
      kind: '',
      label: 'keqrnel',
      log: _singboxLog,
      onStarted: (p) => _singboxProcess = p,
    );

    final ready = await _waitForTunCore(
      process: _singboxProcess!,
      log: _singboxLog,
    );

    // Pull the core's own output (the file above) into the session log so the
    // debug screen and the error below show the real sing-box/xray message.
    final coreLog = await _readRootCoreLog();
    if (coreLog.trim().isNotEmpty) {
      _singboxLog
        ..writeln('=== keqrnel (core) ===')
        ..writeln(coreLog);
    }

    if (!ready) {
      final tail = coreLog.trim().isEmpty
          ? _tail(_singboxLog)
          : _tail(StringBuffer(coreLog));
      throw VpnStartException(tunStartFailureMessage(
        fallback: 'The TUN tunnel did not start.',
        coreOutput: coreLog.trim().isEmpty ? _singboxLog.toString() : coreLog,
        windows: false,
        tail: tail,
      ));
    }
  }

  /// Копия ядра, которую сможет исполнить root.
  ///
  /// В AppImage бинарь лежит на пользовательском FUSE-монте (`/tmp/.mount_*`),
  /// куда root ВООБЩЕ не может зайти, и pkexec умирает с «Permission denied» /
  /// кодом 127. Копия в каталоге сессии (обычный /tmp) от этого избавлена.
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

  /// Вывод root-ядра из файла, куда его редиректит обёртка.
  Future<String> _readRootCoreLog() async {
    try {
      return await File(_coreLogPath).readAsString();
    } catch (_) {
      return '';
    }
  }

  /// Общий pkexec-путь для обоих ядер: сентинел, auth-маркер, запуск обёртки и
  /// ожидание самой авторизации. Возвращает процесс pkexec — готовность TUN
  /// меряет уже вызывающий.
  ///
  /// [onStarted] зовётся СРАЗУ после запуска, до ожидания авторизации: стоп,
  /// пришедший в это окно, обязан найти процесс на месте и снять сентинел.
  /// Иначе root-ядро остаётся жить с поднятым TUN, а убить его нам уже нечем —
  /// обычный пользователь root-процессу сигнал не пошлёт.
  Future<Process> _startElevatedCore({
    required String binPath,
    required String configPath,
    required String geoOrHomeDir,
    required String kind,
    required String label,
    required StringBuffer log,
    required void Function(Process) onStarted,
  }) async {
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
    // Sentinel-файл + `kill -0` PID poll, а НЕ stdin: после polkit-аутентификации
    // pkexec не пробрасывает stdin вызывающего в elevated-потомка — у того stdin
    // сразу на EOF, и любой stdin-вотчдог убивает keqrnel в момент запуска.
    // Сентинел не требует ни stdin, ни повторной элевации.
    //
    // pkexec runs keqrnel as root in the background; its stdout/stderr don't
    // reliably reach our captured pipe (the process can exit before the async
    // stream drains), which left core errors invisible — only a generic "code 1"
    // surfaced. Redirect them to a stable, root-readable file so the REAL reason
    // a TUN start failed is always available. Readiness is detected via the tun
    // interface appearing, so this doesn't depend on the live pipe.
    final sentinelFile = File(p.join(_sessionDir!.path, 'core.run'));
    await sentinelFile.writeAsString('1');
    _rootSentinel = sentinelFile;
    // Auth-маркер: root-обёртка создаёт его сразу после успешной polkit-
    // аутентификации. По нему отличаем «пользователь ещё вводит пароль» от
    // «ядро стартовало и должно поднять TUN» (см. _waitForElevation). Session
    // dir свежий на каждую сессию — застарелый маркер исключён.
    final authMarker = File(p.join(_sessionDir!.path, 'core.auth'));
    _keqrnelLaunchedAt = DateTime.now();

    // Позиции аргументов — контракт с телом обёртки; менять их можно только
    // вместе с версией [_polkitHelperPath].
    final coreArgs = <String>[
      binPath,
      configPath,
      geoOrHomeDir,
      _coreLogPath,
      sentinelFile.path,
      '$pid',
      authMarker.path,
      kind,
    ];
    // Если установлено беспарольное правило — pkexec запускает root-owned хелпер
    // по фиксированному пути (polkit пропускает без пароля). Иначе inline-обёртка
    // через `sh -c` (polkit покажет запрос пароля, как раньше).
    final usePasswordless = isPasswordlessTunInstalled();
    final pkexecArgs = usePasswordless
        ? <String>[_polkitHelperPath, ...coreArgs]
        : <String>['sh', '-c', _tunWrapperBody, 'sh', ...coreArgs];
    final Process process;
    try {
      process = await Process.start(
        'pkexec',
        pkexecArgs,
        workingDirectory: _sessionDir!.path,
        mode: ProcessStartMode.normal,
      );
    } on ProcessException catch (e) {
      throw VpnStartException(
        'Could not launch $label with elevated privileges. TUN mode needs '
        'pkexec (polkit). Install it, or use Proxy mode. ($e)',
      );
    }
    onStarted(process);
    _pipeProcessOutput(process, log);

    // Сначала дожидаемся polkit-аутентификации, и только потом меряем
    // готовность TUN — иначе 20с бюджета _waitForTunCore тикали, пока
    // пользователь вводил пароль, и коннект падал «после запроса прав».
    await _waitForElevation(
      process: process,
      authMarker: authMarker,
      log: log,
    );

    // Пользователь только что ввёл пароль в polkit, а беспарольного правила нет —
    // разово за запуск сигналим UI предложить его установить. Дальше — гейт по
    // настройке linuxTunRememberDismissed на стороне UI.
    if (!usePasswordless && !_rememberOfferedThisRun) {
      _rememberOfferedThisRun = true;
      if (!_linuxTunRememberController.isClosed) {
        _linuxTunRememberController.add(null);
      }
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

  /// Ждёт завершения polkit-аутентификации перед отсчётом готовности TUN.
  ///
  /// [Process.start] для pkexec возвращается сразу — ещё ДО того, как
  /// пользователь ввёл пароль в окне polkit. Если запустить 20-секундный
  /// бюджет [_waitForSingbox] в этот же момент, его съедает сам ввод пароля:
  /// tun-интерфейс не успевает появиться и коннект падает «keqrnel TUN did
  /// not start» сразу после запроса прав.
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
      final code = await _exitCodeOrNull(process);
      if (code != null) {
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

  /// Готовность TUN. Работает для обоих ядер: главный признак — появление
  /// самого интерфейса, а он у нас назван одинаково (`tun-keqdis`) независимо
  /// от того, кто его создал.
  Future<bool> _waitForTunCore({
    required Process process,
    required StringBuffer log,
  }) async {
    var waited = 0;
    while (waited < 20000) {
      final code = await _exitCodeOrNull(process);
      if (code != null) {
        throw VpnStartException(_elevationError(code, log));
      }
      // Строка ТОЛЬКО от sing-box: прежнее «"started" где-то и "tun"
      // где-то» ловило баннер встроенного xray, а он печатается раньше, чем
      // поднят tun-инбаунд (ядро стартует аутбаунды до инбаундов).
      if (singboxTunReady(log.toString())) return true;
      // tun interface up is the most reliable signal across versions.
      if (await _tunInterfaceExists()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      waited += 300;
    }
    // Timed out — only treat as ready if the tun device actually appeared.
    if (await _tunInterfaceExists()) return true;

    // Pull core log one last time for the error message below.
    try {
      final coreLog = await File(_coreLogPath).readAsString();
      if (coreLog.trim().isNotEmpty) {
        log
          ..writeln('=== keqrnel (core, timeout) ===')
          ..writeln(coreLog);
      }
    } catch (_) {}

    final stillRunning = await _exitCodeOrNull(process);
    if (stillRunning != null) {
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
        // Реальный вывод ядра лежит в _coreLogPath (pipe pkexec обычно пуст,
        // см. коммент у обёртки) — тянем его, иначе юзер видит голый код.
        // Файл доверяем только если он записан ПОСЛЕ запуска этой сессии.
        var coreTail = '';
        try {
          final coreLog = File(_coreLogPath);
          final launchedAt = _keqrnelLaunchedAt;
          if (launchedAt != null &&
              !coreLog.lastModifiedSync().isBefore(launchedAt)) {
            coreTail = coreLog.readAsStringSync().trim();
          }
        } catch (_) {}
        final detail =
            coreTail.isNotEmpty ? _tail(StringBuffer(coreTail)) : _tail(log);
        // Причину ищем в полном выводе (в хвосте её часто уже нет), а сам
        // хвост всё равно показываем: типовые случаи объясняет подсказка,
        // разбирать приходится нетиповые.
        final hint = tunFailureHint(
          coreTail.isNotEmpty ? coreTail : log.toString(),
          windows: false,
        );
        if (hint != null) {
          return 'The tunnel core exited with code $code.\n'
              '${hint.message}\n$detail';
        }
        return 'keqrnel exited with code $code (TUN/elevation failed?).\n'
            '$detail';
    }
  }

  Future<bool> _tunInterfaceExists() async {
    return Directory('/sys/class/net/$tunInterfaceName').exists();
  }

  /// Ходит ли хоть что-нибудь через поднятое ядро.
  ///
  /// Проверка идёт через ЛОКАЛЬНЫЙ HTTP-инбаунд — он есть в обоих режимах (в
  /// TUN его инбаунды лифтит keqrnel, через него же качается обновление), и
  /// путь через него ровно тот же, что у трафика из туннеля: те же правила
  /// роутинга, тот же аутбаунд, тот же сервер.
  ///
  /// Только предупреждение: сессию не рвём. Правило пользователя, отправляющее
  /// тестовый адрес в block, — тоже причина, и разрывать из-за неё живой
  /// туннель нельзя.
  Future<void> _verifyChainReachable(TunnelSessionRequest request) async {
    await Future<void>.delayed(const Duration(seconds: 3));
    if (_activeMode == null) return; // сессию уже погасили
    final client = HttpClient();
    String outcome;
    try {
      client.findProxy = (uri) => 'PROXY 127.0.0.1:${request.httpPort}';
      final req = await client
          .getUrl(Uri.parse('http://connectivitycheck.gstatic.com/generate_204'))
          .timeout(const Duration(seconds: 10));
      final response = await req.close().timeout(const Duration(seconds: 10));
      await response.drain<void>();
      if (response.statusCode == 204 || response.statusCode == 200) return;
      outcome = 'status=${response.statusCode}';
    } catch (e) {
      outcome = 'failed ($e)';
    } finally {
      client.close(force: true);
    }
    if (_activeMode == null) return;
    AppLogger.instance.warn(
      'The tunnel is up, but a test request through the core did not go '
      'through ($outcome). Nothing will load until this is fixed — the usual '
      'reasons are an unreachable or expired server, wrong server settings, or '
      'a routing rule that blocks the test address.',
    );
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
    // Намеренно НЕ трогаем прокси-настройки браузеров: gsettings задаёт
    // системный прокси, а Firefox можно один раз переключить на «Использовать
    // системные настройки прокси». Приложение чужие значения не правит.
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
  /// left behind: a system proxy still pointing at a dead local port. Called on
  /// Linux app startup. Does not touch core processes (avoid killing unrelated
  /// xray/sing-box the user may run).
  static Future<void> cleanupStaleState() async {
    try {
      await Process.run('gsettings', [
        'set',
        'org.gnome.system.proxy',
        'mode',
        'none',
      ]);
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
          !identical(process, _mihomoProcess) &&
          !identical(process, _wireproxyProcess)) {
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

  /// Зачистка перед стартом новой сессии — БЕЗ эмитов disconnecting/disconnected.
  /// Нотифаер пропускает disconnected из стрима в UI даже при connect-in-flight
  /// (так нужно Android'у: отмена диалога разрешения), поэтому эмит отсюда
  /// проваливал кнопку в серый «отключён» на пару секунд, пока поднимались ядра.
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

    if (_singboxProcess != null ||
        _xrayProcess != null ||
        _mihomoProcess != null ||
        _wireproxyProcess != null) {
      await _dumpLogsToFile();
    }

    // Always reset the system proxy on stop — even if this instance did not set
    // it (left over from a previous run/crash) — otherwise the desktop keeps
    // routing to a dead 127.0.0.1 proxy.
    await _gsettingsProxy(enabled: false);

    // sing-box first: it owns the tun device + routes, tear it down before the
    // upstream SOCKS provider so traffic fails closed, not into a dead socks.
    await _stopRootCore(_singboxProcess, 'keqrnel');
    // mihomo под root останавливается тем же сентинелом; обычный (proxy-режим)
    // — сигналом, как любой свой процесс.
    if (_mihomoRunsAsRoot) {
      await _stopRootCore(_mihomoProcess, 'mihomo');
    } else {
      await _killProcess(_mihomoProcess);
    }
    await _killProcess(_wireproxyProcess);
    await _killProcess(_xrayProcess);
    _singboxProcess = null;
    _mihomoProcess = null;
    _mihomoRunsAsRoot = false;
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
    if (emitStates) emit(VpnState.disconnected);
  }

  @override
  Future<bool> requestTunnelPermission() async => true;

  @override
  Future<VpnState> getCurrentState() async {
    if (_xrayProcess != null ||
        _wireproxyProcess != null ||
        _mihomoProcess != null ||
        _singboxProcess != null) {
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
    bool keepAlive = true,
  }) async {
    if (items.isEmpty) return [];
    // EphemeralXrayPing is Windows-only for now; on Linux this degrades to a
    // clear per-item error (TCP ping still works via getPing).
    final raw = await EphemeralXrayPing.urlTestBatch(
      items: items.map((e) => (id: e.$1, xrayConfigJson: e.$2)).toList(),
      socksPort: socksPort,
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

    // allowMalformed: a core line in a non-UTF-8 locale (or a stray binary
    // byte) must not throw FormatException and silently kill the log pipe —
    // that's exactly when the log matters most.
    const decoder = Utf8Decoder(allowMalformed: true);
    process.stderr.transform(decoder).listen(handle);
    process.stdout.transform(decoder).listen(handle);
  }

  /// Non-blocking peek at a process's exit status. `null` means still running;
  /// otherwise the exit code — which is NEGATIVE when the process was killed by
  /// a signal on Linux (SIGKILL -> -9, SIGTERM -> -15). Callers must therefore
  /// treat "not null" (not ">= 0") as "exited", or an OOM/kill reads as alive.
  static Future<int?> _exitCodeOrNull(Process process) => process.exitCode
      .then<int?>((c) => c)
      .timeout(const Duration(milliseconds: 1), onTimeout: () => null);

  /// Stops the elevated core gracefully. We cannot signal the root process
  /// directly, so we delete the sentinel file the root wrapper polls — it then
  /// SIGTERMs the core AS ROOT, which reverts auto_route/nftables before exiting.
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
      // Wrapper didn't exit in time — last resort so we never leave a root
      // core holding the TUN. The elevated pkill may show a polkit prompt.
      try {
        await Process.run('pkexec', ['pkill', '-TERM', '-x', coreName]);
      } catch (_) {}
      try {
        proc.kill(ProcessSignal.sigkill);
      } catch (_) {}
    }

    // Процесс мёртв — устройство ещё нет: ядро снимает интерфейс и маршруты уже
    // после выхода из main, а при жёстком добивании эту уборку доделывает ядро
    // ОС. Стартовать поверх ещё живого `tun-keqdis` нельзя: имя занято, и
    // следующая сессия либо падает, либо поднимается на умирающем устройстве —
    // «через раз ошибка, через раз туннеля нет».
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

  /// Последняя проверка портов перед стартом ядра.
  ///
  /// Порты сюда приезжают уже подобранные ([LocalPortResolver] отработал до
  /// генерации конфига), так что остаётся гонка «занял между проверкой и
  /// стартом». Причину всё равно называем: «занят соседом» и «запрещён» —
  /// разные действия пользователя.
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




  @override


  @override
  Future<void> pollTrafficStats(ConnectionMode mode, {bool force = false}) async {
    if (!statsPollingEnabled && !force) return;
    if (_xrayProcess == null &&
        _wireproxyProcess == null &&
        _mihomoProcess == null &&
        _singboxProcess == null) {
      return;
    }
    try {
      final int inOctets;
      final int outOctets;

      if (_mihomoProcess != null) {
        // У mihomo источник один на оба режима — его собственный RESTful API.
        // Счётчики tun-интерфейса тут не годятся: в TUN-режиме их пишет ядро
        // ОС, а в proxy-режиме интерфейса нет вовсе.
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
        // tun interface stats: kernel writes the app's egress to the device
        // (tx) and reads sing-box's downloaded replies from it (rx).
        final c = await _queryTunCounters();
        if (c == null) {
          emitConnectedTelemetry(mode);
          return;
        }
        inOctets = c.rx;
        outOctets = c.tx;
      } else if (_wireproxyProcess != null && _awgInfoPort != null) {
        final m = await queryWireproxyMetrics(_awgInfoPort!);
        if (m == null) {
          emitConnectedTelemetry(mode);
          return;
        }
        inOctets = m.rx;
        outOctets = m.tx;
      } else if (_keqrnelClashPort != null) {
        // keqrnel proxy: кумулятивный трафик из clash_api sing-box.
        final t = await queryClashTraffic(_keqrnelClashPort!);
        if (t == null) {
          emitConnectedTelemetry(mode);
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



}
