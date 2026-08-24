import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../core/app_logger.dart';
import '../core/exceptions.dart';
import '../models/tun_settings.dart';
import '../services/debug_log_service.dart';
import '../services/ephemeral_xray_ping.dart';
import '../services/windows_desktop_service.dart';
import '../utils/keqrnel_config.dart';
import '../utils/mihomo_api_session.dart';
import '../utils/singbox_tun_config.dart';
import '../utils/wireproxy_config.dart';
import 'connection_mode.dart';
import 'core_capabilities.dart';
import 'desktop_traffic_stats.dart';
import 'local_port_plan.dart';
import 'socks_credential_generator.dart';
import 'tun_failure_hints.dart';
import 'tunnel_backend.dart';
import 'tunnel_session_request.dart';
import 'tunnel_state.dart';
import 'vpn_backend.dart';
import 'windows_core_paths.dart';
import 'xray_session_stats.dart';

/// windows: xray всегда + sing-box только для tun, системный прокси через wininet
class WindowsTunnelBackend with DesktopTrafficStats implements TunnelBackend {
  static const _method = MethodChannel('keqdis_vpn_channel');

  /// Active session backend — for Xray log export on desktop.
  static WindowsTunnelBackend? activeInstance;

  /// Логи последней ЗАВЕРШЁННОЙ сессии. После teardown [activeInstance]
  /// зануляется, и экран логов отвечал «подключитесь сначала» ровно в тот
  /// момент, когда логи нужнее всего — после внезапной смерти ядра.
  static String lastSessionLogs = '';

  final _stateCtrl = StreamController<VpnState>.broadcast();
  Process? _xrayProcess;
  Process? _singboxProcess;
  // keqrnel: единое ядро (sing-box host + встроенный xray) — заменяет связку
  // _xrayProcess + _singboxProcess. null когда неактивно.
  Process? _keqrnelProcess;
  // Порт clash_api keqrnel — из него читаем кумулятивный трафик (proxy-режим)
  // и список соединений для дебаг-экрана (оба режима).
  int? _keqrnelClashPort;

  // mihomo: одно ядро на оба режима. В proxy-режиме держит локальные socks/http,
  // в TUN — ещё и сам wintun-адаптер (keqrnel в этой схеме не участвует вовсе).
  Process? _mihomoProcess;

  /// Порт clash_api активной сессии; null — сессии нет или API не поднят
  /// (цепочка xray+sing-box его не даёт). Читает [ConnectionsService].
  ///
  /// У mihomo координаты API придумывает не бэкенд, а тот же код, что собирал
  /// конфиг ([MihomoApiSession]) — порт и `secret` едут внутрь конфига, и второй
  /// источник правды тут был бы просто вторым шансом разъехаться.
  int? get clashApiPort =>
      _keqrnelClashPort ?? (_mihomoProcess != null ? MihomoApiSession().port : null);

  /// PID живых процессов ядра: подпись → pid. Пустая карта — сессии нет.
  /// Читает панель «Внутренности»; больше эти процессы из Dart нигде не видны.
  Map<String, int> get activeCorePids => {
    if (_keqrnelProcess != null) 'keqrnel': _keqrnelProcess!.pid,
    if (_mihomoProcess != null) 'mihomo': _mihomoProcess!.pid,
    if (_xrayProcess != null) 'xray': _xrayProcess!.pid,
    if (_wireproxyProcess != null) 'wireproxy': _wireproxyProcess!.pid,
    if (_singboxProcess != null) 'sing-box (TUN)': _singboxProcess!.pid,
  };
  Directory? _sessionDir;
  ({String username, String password})? _pendingCreds;
  ConnectionMode? _activeMode;

  @override
  ConnectionMode? get activeMode => _activeMode;
  final StringBuffer _xrayLog = StringBuffer();
  final StringBuffer _singboxLog = StringBuffer();

  // AmneziaWG: процесс wireproxy-awg (SOCKS5[/HTTP]); используется и для proxy-,
  // и для TUN-режима (в TUN дополнительно поднимается sing-box). null когда неактивен.
  Process? _wireproxyProcess;
  // Порт info/metrics эндпоинта wireproxy (`-i`) для подсчёта трафика в proxy-режиме.
  int? _awgInfoPort;

  // true пока идёт штатный stopSession — чтобы вотчдог не принял наш же
  // kill за внезапную смерть ядра.
  bool _stoppingSession = false;

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

  /// `true` — админ, `false` — нет, `null` — выяснить не удалось (канал не
  /// ответил). На `null` попытку не блокируем: лучше дать ядру сказать своё.
  Future<bool?> _isElevated() async {
    try {
      return await _method.invokeMethod<bool>('requestTunnelPermission');
    } on PlatformException {
      return null;
    }
  }

  /// Несколько последних строк вывода ядра для текста ошибки. Пусто, если
  /// ядро вообще ничего не написало.
  String _sessionLogTail({int maxLines = 10}) {
    final text = exportSessionLogs(maxLines: maxLines).trim();
    return text == '(no process output)' ? '' : text;
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

      // TUN поднимает wintun-адаптер и правит таблицу маршрутов — без прав
      // администратора ядро просто умирает, и пользователь видит «keqrnel
      // stopped unexpectedly (exit code 1)» вместо причины. Отсекаем заранее:
      // формулировка со словами «administrator rights» попадает в готовый
      // локализованный случай UiErrorCode.tunAdmin (см. explainError).
      if (request.mode == ConnectionMode.tun && await _isElevated() == false) {
        throw const VpnStartException(
          'TUN mode needs administrator rights: the wintun adapter and the '
          'system route table cannot be set up without them. Restart the app '
          'as administrator, or use Proxy mode.',
        );
      }

      _sessionDir = await WindowsCorePaths.sessionDir();

      switch (request.vpnBackend) {
        case VpnBackend.awg:
          await _startAwgSession(request);
        case VpnBackend.mihomo:
          await _startMihomoSession(request);
        case VpnBackend.xray:
          // keqrnel — единственное ядро для xray-протоколов (proxy и TUN);
          // отдельные xray.exe/sing-box.exe не поставляются.
          await _startKeqrnelSession(request);
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
      // а системный прокси — направленным на мёртвый порт.
      _watchProcessExit(_keqrnelProcess, 'keqrnel');
      _watchProcessExit(_mihomoProcess, 'mihomo');
      _watchProcessExit(_singboxProcess, 'keqrnel TUN');
      _watchProcessExit(_wireproxyProcess, 'wireproxy');
      _watchProcessExit(_xrayProcess, 'xray');
    } catch (e, st) {
      AppLogger.instance.error('Windows tunnel start failed', error: e, stackTrace: st);
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

  /// keqrnel (единое ядро) — один процесс вместо цепочки. Диспетчер по режиму.
  Future<void> _startKeqrnelSession(TunnelSessionRequest request) async {
    if (request.mode == ConnectionMode.tun) {
      await _startKeqrnelTunSession(request);
    } else {
      await _startKeqrnelProxySession(request);
    }
  }

  /// proxy-режим: локальные socks/http (и LAN-инбаунды при шаринге) слушает
  /// sing-box-часть keqrnel, внутри — встроенный xray. Системный прокси
  /// Windows — поверх. sing-box TUN здесь не задействован, админ не нужен.
  Future<void> _startKeqrnelProxySession(TunnelSessionRequest request) async {
    final bin = await WindowsCorePaths.keqrnelExecutable();
    if (bin == null) {
      throw VpnStartException(
        'keqrnel.exe not found. ${WindowsCorePaths.binariesHint}',
      );
    }

    // sing-box owns the local SOCKS/HTTP listeners and forwards through the
    // xray bridge, so it counts traffic and exposes it via clash_api.
    final clashPort = await _freePort();
    final merged = KeqrnelConfig.proxyWithStats(
      xrayConfig: request.xrayConfig,
      socksPort: request.socksPort,
      httpPort: request.httpPort,
      clashPort: clashPort,
      findProcess: request.debugMode,
    );
    _keqrnelClashPort = clashPort;
    final configFile = File('${_sessionDir!.path}/keqrnel.json');
    await configFile.writeAsString(merged);

    await _ensurePortsAvailable(request);

    final workDir = p.dirname(bin);
    final geoDir = await WindowsCorePaths.geoAssetDir();

    _keqrnelProcess = await Process.start(
      bin,
      [configFile.path],
      workingDirectory: workDir,
      environment: _coreProcessEnvironment(geoDir),
      mode: ProcessStartMode.normal,
    );
    _pipeProcessOutput(_keqrnelProcess!, _xrayLog, 'keqrnel');

    final socksReady = await _waitForPort(
      '127.0.0.1',
      request.socksPort,
      process: _keqrnelProcess,
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
        process: _keqrnelProcess,
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

    await WindowsDesktopService.registerSessionCoreProcesses(
      xrayPid: _keqrnelProcess?.pid ?? 0,
      singboxPid: 0,
    );
  }

  /// TUN-режим: один процесс вместо xray + sing-box. Берём тот же sing-box
  /// TUN-конфиг, но его socks-`proxy` заменён на встроенный xray
  /// (см. [KeqrnelConfig.fromChain]). Запускается из каталога с wintun.dll.
  Future<void> _startKeqrnelTunSession(TunnelSessionRequest request) async {
    final bin = await WindowsCorePaths.keqrnelExecutable();
    if (bin == null) {
      throw VpnStartException(
        'keqrnel.exe not found. ${WindowsCorePaths.binariesHint}',
      );
    }
    final singConfig = request.singboxConfig;
    if (singConfig == null || singConfig.isEmpty) {
      throw const VpnStartException(
        'singboxConfig is required for keqrnel TUN',
      );
    }

    await _ensureTunPrerequisites(bin, request);

    final clashPort = await _freePort();
    final merged = KeqrnelConfig.fromChain(
      singboxConfig: await _tunStackForCore(singConfig, bin),
      xrayConfig: request.xrayConfig,
      windows: true,
      clashApiPort: clashPort,
    );
    _keqrnelClashPort = clashPort;
    final configFile = File('${_sessionDir!.path}/keqrnel.json');
    await configFile.writeAsString(merged);

    // Запускаем рядом с wintun.dll (как sing-box); xray-ассеты — через env.
    final workDir = p.dirname(bin);
    final geoDir = await WindowsCorePaths.geoAssetDir();

    _keqrnelProcess = await Process.start(
      bin,
      [configFile.path],
      workingDirectory: workDir,
      environment: _coreProcessEnvironment(geoDir),
      mode: ProcessStartMode.normal,
    );
    _pipeProcessOutput(_keqrnelProcess!, _singboxLog, 'keqrnel');

    final ready = await _waitForSingbox(
      process: _keqrnelProcess!,
      log: _singboxLog,
    );
    if (!ready) {
      throw VpnStartException(_tunStartError(_singboxLog));
    }

    await WindowsDesktopService.registerSessionCoreProcesses(
      xrayPid: _keqrnelProcess?.pid ?? 0,
      singboxPid: 0,
    );
  }

  /// mihomo — второе полноценное ядро, а не обёртка вокруг keqrnel.
  ///
  /// Отличие от xray-пути принципиальное: в TUN-режиме адаптером владеет само
  /// mihomo (внутри у него тот же sing-tun), поэтому связки «ядро → локальный
  /// SOCKS → sing-box» здесь нет вовсе — процесс один на любой режим. Отсюда и
  /// требования те же, что к keqrnel: права администратора и `wintun.dll`
  /// рядом с бинарём.
  Future<void> _startMihomoSession(TunnelSessionRequest request) async {
    final bin = await WindowsCorePaths.mihomoExecutable();
    if (bin == null) {
      throw VpnStartException(
        'mihomo.exe not found. ${WindowsCorePaths.binariesHint}',
      );
    }
    final config = request.mihomoConfig;
    if (config == null || config.isEmpty) {
      throw const VpnStartException('mihomoConfig is required for mihomo');
    }

    final isTun = request.mode == ConnectionMode.tun;
    if (isTun) {
      await _ensureTunPrerequisites(bin, request);
    } else {
      // mihomo поднимает оба локальных инбаунда из одного конфига, и занятый
      // соседом порт роняет старт целиком, а не отключает одну возможность.
      await _ensurePortsAvailable(request);
    }

    // Расширение `.yaml` — то, что ядро ждёт; содержимое при этом JSON (YAML 1.2
    // его надмножество, см. MihomoConfigGen).
    final configFile = File('${_sessionDir!.path}/mihomo.yaml');
    await configFile.writeAsString(config);

    // `-d` — домашний каталог ядра: оттуда оно берёт geoip.dat/geosite.dat,
    // туда же пишет свой cache.db и, если конфига там нет, создаёт пустой
    // `config.yaml`. Последнее и решает: на каталоге без права записи это
    // ошибка `config.Init`, после которой ядро не стартует вовсе.
    final home = await WindowsCorePaths.mihomoHomeDir();

    _mihomoProcess = await Process.start(
      bin,
      ['-d', home, '-f', configFile.path],
      // Рядом с бинарём лежит wintun.dll, а грузит его ядро по имени, то есть
      // из каталога процесса.
      workingDirectory: p.dirname(bin),
      mode: ProcessStartMode.normal,
    );
    _pipeProcessOutput(_mihomoProcess!, _xrayLog, 'mihomo');

    if (isTun) {
      final ready = await _waitForMihomoTun(
        process: _mihomoProcess!,
        log: _xrayLog,
      );
      if (!ready) {
        throw VpnStartException(_tunStartError(_xrayLog, core: 'mihomo.exe'));
      }
    } else {
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

    await WindowsDesktopService.registerSessionCoreProcesses(
      xrayPid: _mihomoProcess?.pid ?? 0,
      singboxPid: 0,
    );
  }

  /// Готовность TUN у mihomo — по появлению интерфейса и по его собственной
  /// строке лога.
  ///
  /// По адресу, как у sing-box, спрашивать нельзя: адрес интерфейса mihomo
  /// считает из `dns.fake-ip-range` и задать его отдельно не даёт (см.
  /// [MihomoConfigGen.buildTun]). Зато имя мы задаём сами — по нему и смотрим.
  Future<bool> _waitForMihomoTun({
    required Process process,
    required StringBuffer log,
  }) async {
    var waited = 0;
    while (waited < _tunReadyBudgetMs) {
      final code = await _exitCodeOrNull(process);
      if (code != null) {
        throw VpnStartException(
          'mihomo exited with code $code before the tunnel came up.\n'
          '${_tunStartError(log, core: 'mihomo.exe')}',
        );
      }
      if (log.toString().contains('Tun adapter listening at')) return true;
      if (await _tunAdapterUp(extraAddress: _mihomoTunAddress)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      waited += 300;
    }
    return false;
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
  ///
  /// withHttp: сам процесс приложения роутится в TUN «direct» (ради честных
  /// пингов, см. singbox_tun_config), поэтому чекер/загрузчик обновлений ходит
  /// через локальный HTTP-инбаунд — без него апдейт при активном AWG TUN
  /// уходил напрямую на 127.0.0.1:httpPort без слушателя и падал.
  Future<void> _startAwgTunSession(TunnelSessionRequest request) async {
    await _startWireproxy(request, withHttp: true);
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

  /// TUN-обёртка для AmneziaWG: keqrnel (как sing-box host) заворачивает
  /// локальный SOCKS5 wireproxy в TUN — отдельный sing-box.exe не нужен.
  Future<void> _startSingboxSession(TunnelSessionRequest request) async {
    final bin = await WindowsCorePaths.keqrnelExecutable();
    if (bin == null) {
      throw VpnStartException(
        'keqrnel.exe not found. ${WindowsCorePaths.binariesHint}',
      );
    }
    final singConfig = request.singboxConfig;
    if (singConfig == null || singConfig.isEmpty) {
      throw const VpnStartException('singboxConfig is required');
    }

    final singConfigFile = File('${_sessionDir!.path}/keqrnel-tun.json');
    await singConfigFile.writeAsString(await _tunStackForCore(singConfig, bin));

    final workDir = p.dirname(bin);
    _singboxProcess = await Process.start(
      bin,
      ['run', '-c', singConfigFile.path],
      workingDirectory: workDir,
      mode: ProcessStartMode.normal,
    );
    _pipeProcessOutput(_singboxProcess!, _singboxLog, 'keqrnel-tun');

    if (request.mode == ConnectionMode.tun) {
      final singReady = await _waitForSingbox(
        process: _singboxProcess!,
        log: _singboxLog,
      );
      if (!singReady) {
        throw VpnStartException(_tunStartError(_singboxLog));
      }
    }
  }

  /// Что должно быть на месте ДО старта TUN, но проверяется только там.
  ///
  /// Оба случая иначе выглядят одинаково — «keqrnel TUN did not start» с
  /// невнятным хвостом лога, — а причины у них разные и обе чинятся руками:
  ///
  ///  * `wintun.dll` рядом с ядром. Его сносит антивирус (файл без подписи
  ///    рядом с exe — типовая эвристика) и теряет ручная распаковка портативной
  ///    сборки. Без него sing-tun не создаёт адаптер вовсе.
  ///  * Локальные порты. В TUN-режиме их слушает встроенный xray внутри
  ///    keqrnel: занял 2080 сосед (второй клиент, прошлая сессия, что угодно) —
  ///    и ядро падает на старте инбаунда, хотя TUN тут вообще ни при чём.
  Future<void> _ensureTunPrerequisites(
    String binPath,
    TunnelSessionRequest request,
  ) async {
    final wintun = File(p.join(p.dirname(binPath), 'wintun.dll'));
    if (!wintun.existsSync()) {
      throw VpnStartException(
        'wintun.dll is missing next to ${p.basename(binPath)} (${wintun.path}). '
        'TUN mode cannot create the network adapter without it — antivirus '
        'quarantine and half-unpacked portable builds are the usual reasons. '
        'Reinstall the app or use Proxy mode.',
      );
    }
    await _ensurePortsAvailable(request);
  }

  /// Последняя проверка портов перед стартом ядра.
  ///
  /// Обычно сюда приезжают уже подобранные порты ([LocalPortResolver] отработал
  /// до генерации конфига), так что срабатывает это на гонке «занял между
  /// проверкой и стартом» — и тогда важно назвать ПРИЧИНУ: «занят соседом»,
  /// «изъят Windows под Hyper-V/WSL» и «запрещён защитой» лечатся по-разному, а
  /// выглядят одинаково.
  ///
  /// Порта здесь два, и оба обязательны в любом режиме: HTTP-инбаунд ядро
  /// поднимает всегда (через него ходит апдейтер и на него смотрит системный
  /// прокси), поэтому занятый HTTP-порт роняет ядро целиком — а не «отключает
  /// одну возможность», как считалось раньше.
  Future<void> _ensurePortsAvailable(TunnelSessionRequest request) async {
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
    // HTTP-инбаунд поднимает то же ядро и в TUN-режиме (его порты лифтит
    // keqrnel), поэтому занятый порт роняет старт независимо от режима.
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
  }

  /// Вотчдог: ядро завершилось само (не через [stopSession]) → снимаем
  /// системный прокси, чистим состояние и эмитим error вместо вечного
  /// «Connected» поверх мёртвого туннеля.
  void _watchProcessExit(Process? process, String label) {
    if (process == null) return;
    unawaited(process.exitCode.then((code) async {
      if (_stoppingSession) return;
      // Процесс уже не из активной сессии (штатный stop занулил поля).
      if (!identical(process, _keqrnelProcess) &&
          !identical(process, _mihomoProcess) &&
          !identical(process, _singboxProcess) &&
          !identical(process, _wireproxyProcess) &&
          !identical(process, _xrayProcess)) {
        return;
      }
      // Хвост снимаем ДО teardown и кладём прямо в текст ошибки: голый exit
      // code не говорит ничего, а экран логов после остановки сессии показать
      // уже нечего (см. lastSessionLogs).
      final details = _sessionLogTail();
      // Причину ищем в ПОЛНОМ выводе сессии, а не в хвосте: строка с реальной
      // ошибкой часто оказывается выше десятка строк агонии ядра.
      final hint = tunFailureHint(exportSessionLogs(), windows: true);
      AppLogger.instance.error(
        '$label exited unexpectedly with code $code; tearing the session down'
        '${hint == null ? '' : '\n${hint.message}'}'
        '${details.isEmpty ? '' : '\n$details'}',
      );
      try {
        await stopSession();
      } catch (_) {}
      emit(VpnState(
        status: VpnStatus.error,
        errorMessage:
            '$label stopped unexpectedly (exit code $code). Disconnected.'
            '${hint == null ? '' : '\n${hint.message}'}'
            '${details.isEmpty ? '' : '\n$details'}',
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
    final wasTun = _activeMode == ConnectionMode.tun;
    stopStatsLoop();
    // Забираем логи сессии до её разбора: после teardown экран логов уже не
    // достучится до этого инстанса, а разбирать чаще всего приходится именно
    // упавшую сессию.
    final logs = exportSessionLogs();
    if (logs.trim().isNotEmpty && logs.trim() != '(no process output)') {
      lastSessionLogs = logs;
    }
    if (emitStates) emit(const VpnState(status: VpnStatus.disconnecting));

    try {
      await _method.invokeMethod<void>('setSystemProxy', {'enabled': false});
    } catch (_) {}

    // TUN owners first (gracefully, so the embedded sing-box reverts the TUN
    // adapter / routes / DNS), then the upstream socks providers.
    await _killProcess(_keqrnelProcess, graceful: true);
    // mihomo слушает сигналы, а не stdin: на Windows это всё равно жёсткий
    // TerminateProcess, поэтому уборку адаптера доделывает драйвер wintun —
    // её и дожидается _awaitTunAdapterGone ниже.
    await _killProcess(_mihomoProcess);
    await _killProcess(_singboxProcess, graceful: true);
    await _killProcess(_wireproxyProcess);
    await _killProcess(_xrayProcess);
    _wireproxyProcess = null;
    _awgInfoPort = null;
    _singboxProcess = null;
    _xrayProcess = null;
    _keqrnelProcess = null;
    _mihomoProcess = null;
    _keqrnelClashPort = null;
    _xrayBinPath = null;

    await WindowsDesktopService.clearSessionCoreProcesses();

    // Процесс мёртв — адаптер ещё нет. wintun снимает его, когда закрылся
    // последний хэндл, и Windows делает это не мгновенно; при жёстком добивании
    // (graceful не успел) он и вовсе доживает до конца драйверной уборки.
    // Стартовать поверх такого адаптера нельзя: sing-tun на занятом имени
    // получает от CreateAdapter ErrExist и делает OpenAdapter — то есть
    // настраивает УМИРАЮЩИЙ адаптер. Снаружи это «через раз ошибка, через раз
    // туннель поднялся, а трафика нет».
    //
    // Только если сессия РЕАЛЬНО была TUN: чужой sing-box-клиент рядом держит
    // тот же адрес 172.19.0.1 (это дефолт sing-box), и ждать его исчезновения
    // на каждом отключении прокси-режима незачем.
    if (wasTun) await _awaitTunAdapterGone();

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
    if (_xrayProcess != null ||
        _wireproxyProcess != null ||
        _keqrnelProcess != null ||
        _mihomoProcess != null) {
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
    bool keepAlive = true,
  }) async {
    if (items.isEmpty) return [];
    final raw = await EphemeralXrayPing.urlTestBatch(
      items: items
          .map((e) => (id: e.$1, xrayConfigJson: e.$2))
          .toList(),
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

  /// Dart [Process.start] replaces the whole environment when `environment` is
  /// set — merge with the parent so keqrnel keeps PATH, SystemRoot, etc.
  static Map<String, String>? _coreProcessEnvironment(String? geoDir) {
    if (geoDir == null) return null;
    return {...Platform.environment, 'XRAY_LOCATION_ASSET': geoDir};
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

    // allowMalformed: a core line in the system ANSI codepage (RU Windows) or
    // a stray binary byte must not throw FormatException and silently kill the
    // log pipe — that's exactly when the log matters most.
    const decoder = Utf8Decoder(allowMalformed: true);
    process.stderr.transform(decoder).listen(handle);
    process.stdout.transform(decoder).listen(handle);
  }

  /// Non-blocking peek at a process's exit status. `null` means still running;
  /// otherwise the exit code. On Windows a killed process yields a large exit
  /// code (not a negative signal like Linux), but keep the same null-means-
  /// running contract so "exited" is never misread as "alive".
  static Future<int?> _exitCodeOrNull(Process process) => process.exitCode
      .then<int?>((c) => c)
      .timeout(const Duration(milliseconds: 1), onTimeout: () => null);

  Future<void> _killProcess(Process? process, {bool graceful = false}) async {
    if (process == null) return;
    try {
      if (graceful) {
        // On Windows kill() is a hard TerminateProcess — sing-box then never
        // reverts the TUN adapter, routes and DNS, which can leave the network
        // broken after disconnect. keqrnel shuts down cleanly on stdin EOF, so
        // close stdin and give it time to revert; hard-kill only as a fallback.
        try {
          await process.stdin.close();
        } catch (_) {}
        final code = await process.exitCode.timeout(
          const Duration(seconds: 5),
          onTimeout: () => -2,
        );
        if (code != -2) return;
      }
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
    while (waited < _tunReadyBudgetMs) {
      final code = await _exitCodeOrNull(process);
      if (code != null) {
        throw VpnStartException(
          'keqrnel exited with code $code before the tunnel came up.\n'
          '${_tunStartError(log ?? StringBuffer())}',
        );
      }
      // Готовность — только по строкам самого sing-box (см. singboxTunReady):
      // баннер встроенного xray печатается раньше, чем поднят TUN.
      if (singboxTunReady((log ?? StringBuffer()).toString())) return true;
      // Адаптер с нашим адресом — тот же сигнал, но не из лога: у сборки без
      // привычных строк (или с другим уровнем лога) он остаётся единственным.
      // Спрашиваем не сразу: адаптер мог остаться от убитой сессии (sing-tun
      // снимает его при штатном выходе, а после kill он живёт ещё пару секунд),
      // и на первых опросах это был бы чужой сигнал.
      if (waited >= 5000 && await _tunAdapterUp()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      waited += 300;
    }
    // Ни строки, ни адаптера за бюджет: живой процесс всё ещё считаем удачей
    // (так было и раньше), но говорим об этом в лог — «подключено» тут уже
    // предположение, а не факт.
    final stillRunning = await _exitCodeOrNull(process);
    if (stillRunning == null) {
      AppLogger.instance.warn(
        'keqrnel TUN: no readiness signal in '
        '${_tunReadyBudgetMs ~/ 1000}s, assuming it is up because the process '
        'is alive.\n${_tail(log ?? StringBuffer())}',
      );
    }
    return stillRunning == null;
  }

  /// Бюджет ожидания TUN. Больше прежних 15с: сюда попадает и разбор geo-баз
  /// встроенным xray (geoip.dat — десятки мегабайт), и создание wintun-адаптера.
  static const _tunReadyBudgetMs = 30000;

  /// Текст отказа старта TUN: опознанная причина (если она в логе есть) +
  /// общий совет + хвост лога. Без разбора наружу уходило одно и то же
  /// «did not start» на десяток совершенно разных поломок.
  String _tunStartError(StringBuffer log, {String core = 'keqrnel.exe'}) {
    final text = log.toString();
    return tunStartFailureMessage(
      fallback: 'The TUN tunnel did not start. Run the app as Administrator '
          'and make sure wintun.dll sits next to $core.',
      coreOutput: text,
      windows: true,
      tail: _tail(log),
    );
  }

  /// Сверяет стек TUN-инбаунда с тем, что умеет ЭТОТ бинарь ядра.
  ///
  /// Ядро без `-tags with_gvisor` на `stack: gvisor` не ругается в конфиге, а
  /// падает при старте — «TUN не поднялся, exit code 1» на ровном месте.
  /// Поставляемый keqrnel собран с тегом, но собранный руками из исходников
  /// (`go build ./...`) — нет.
  Future<String> _tunStackForCore(String singboxConfig, String binPath) async {
    final result = applyTunStackFallback(
      singboxConfig,
      gvisorAvailable: await CoreCapabilities.hasGvisor(binPath),
    );
    if (result.downgradedFrom != null) {
      AppLogger.instance.warn(
        'TUN stack "${result.downgradedFrom}" needs a core built with '
        '-tags with_gvisor; this keqrnel has none, falling back to "system". '
        'On Windows the system stack needs an inbound Windows Firewall rule — '
        'if there is no traffic at all, that rule is the first thing to check.',
      );
    } else if (result.config.contains('"stack": "${TunSettings.stackSystem}"')) {
      // Стек выбран пользователем, а не подставлен откатом — но предупредить
      // всё равно надо: system терминирует TCP листенером на адресе самого
      // интерфейса, и без входящего разрешения фаервола адаптер поднят,
      // маршруты стоят, ошибок нет, а трафика нет вовсе. Правило sing-tun
      // заводит сам, но результат игнорирует.
      AppLogger.instance.warn(
        'TUN stack is "system": on Windows it terminates TCP with a listener on '
        'the TUN interface address and therefore needs an inbound Windows '
        'Firewall rule. sing-tun adds it itself but ignores the result — if the '
        'tunnel comes up and no traffic flows at all, that rule (or a '
        'third-party firewall blocking it) is the first suspect. The gVisor '
        'stack does not depend on it.',
      );
    }
    return result.config;
  }

  /// Ждёт исчезновения нашего wintun-адаптера после остановки ядра.
  ///
  /// Возвращается сразу, если адаптера и так нет (обычный случай: сессии не
  /// было либо она была proxy-режимом). Не дождались — не блокируем старт:
  /// лучше попытка с предупреждением в логе, чем отказ подключаться.
  Future<void> _awaitTunAdapterGone() async {
    const budgetMs = 6000;
    var waited = 0;
    while (waited < budgetMs) {
      if (!await _tunAdapterUp()) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      waited += 250;
    }
    AppLogger.instance.warn(
      'TUN adapter $kTunInterfaceAddress is still up ${budgetMs ~/ 1000}s after '
      'the core was stopped. The next TUN start may take over the dying '
      'adapter instead of creating a new one.',
    );
  }

  /// Поднялся ли наш wintun-адаптер: у интерфейса есть адрес из TUN-подсети.
  /// Имя интерфейса на Windows зависит от того, что показывает система, а
  /// адрес мы задаём сами (singbox_tun_config), поэтому ищем по нему.
  ///
  /// [extraAddress] — адрес второго ядра: у mihomo он не наш выбор, а
  /// производная от `dns.fake-ip-range`, поэтому передаётся отдельно.
  Future<bool> _tunAdapterUp({String? extraAddress}) async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        if (iface.name == kTunInterfaceName) return true;
        for (final addr in iface.addresses) {
          if (addr.address == kTunInterfaceAddress) return true;
          if (extraAddress != null && addr.address == extraAddress) return true;
        }
      }
    } catch (_) {
      // Перечисление интерфейсов не удалось — решает лог.
    }
    return false;
  }

  /// Адрес tun-интерфейса mihomo — первый адрес его `fake-ip-range`.
  static const _mihomoTunAddress = '198.18.0.1';

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
            // Причина почти всегда в самом выводе (порт, конфиг, права) —
            // называем её, а не только код выхода.
            final buffer = log ?? StringBuffer();
            final hint = tunFailureHint(buffer.toString(), windows: true);
            throw VpnStartException(
              '$processLabel exited with code $code.'
              '${hint == null ? '' : '\n${hint.message}'}'
              '\n${_tail(buffer)}',
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
        _keqrnelProcess == null &&
        _mihomoProcess == null) {
      return;
    }
    try {
      final int inOctets;
      final int outOctets;

      if (_mihomoProcess != null) {
        // У mihomo источник один на оба режима — его собственный RESTful API.
        // Счётчик там кумулятивный по всем соединениям ядра, то есть тот же
        // смысл, что у clash_api keqrnel.
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
      } else if (_wireproxyProcess != null && _awgInfoPort != null && mode == ConnectionMode.proxy) {
        // AmneziaWG proxy: кумулятивные rx/tx из wireproxy /metrics.
        final m = await queryWireproxyMetrics(_awgInfoPort!);
        if (m == null) {
          // метрики недоступны — хотя бы тикаем длительность сессии
          emitConnectedTelemetry(mode);
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
        if (result == null || result['ok'] != true) {
          // Counters unavailable — still keep the session timer ticking.
          emitConnectedTelemetry(mode);
          return;
        }
        inOctets = (result['inOctets'] as num?)?.toInt() ?? 0;
        outOctets = (result['outOctets'] as num?)?.toInt() ?? 0;
      } else if (mode == ConnectionMode.proxy && _keqrnelClashPort != null) {
        // keqrnel proxy: кумулятивный трафик из clash_api sing-box.
        final t = await queryClashTraffic(_keqrnelClashPort!);
        if (t == null) {
          emitConnectedTelemetry(mode);
          return;
        }
        inOctets = t.down;
        outOctets = t.up;
      } else {
        // нет источника счётчика — хотя бы тикаем длительность сессии.
        emitConnectedTelemetry(mode);
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

      final deltaIn =
          inOctets >= prevInOctets ? inOctets - prevInOctets : 0;
      final deltaOut =
          outOctets >= prevOutOctets ? outOctets - prevOutOctets : 0;
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
      AppLogger.instance.debug('getTrafficStats failed: $e');
    }
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

  /// Ходит ли хоть что-нибудь через поднятое ядро.
  ///
  /// Проверка идёт через ЛОКАЛЬНЫЙ HTTP-инбаунд — он есть в обоих режимах (в
  /// TUN его инбаунды лифтит keqrnel, через него же качается обновление), и
  /// путь через него ровно тот же, что у трафика из туннеля: те же правила
  /// роутинга, тот же аутбаунд, тот же сервер. Неудача означает, что не
  /// загрузится ничего, — и сказать об этом надо сразу, а не оставлять
  /// пользователя наедине с зелёной кнопкой.
  ///
  /// Только предупреждение: сессию не рвём. Правило пользователя, отправляющее
  /// тестовый адрес в block, — тоже причина, и разрывать из-за неё живой
  /// туннель нельзя.
  Future<void> _verifyChainReachable(TunnelSessionRequest request) async {
    await Future<void>.delayed(const Duration(seconds: 3));
    if (_activeMode == null) return; // сессию уже погасили
    final result = await _probeLocalHttpProxy(request.httpPort);
    if (result.contains('status=204') || result.contains('status=200')) return;
    if (_activeMode == null) return;
    AppLogger.instance.warn(
      'The tunnel is up, but a test request through the core did not go '
      'through ($result). Nothing will load until this is fixed — the usual '
      'reasons are an unreachable or expired server, wrong server settings, or '
      'a routing rule that blocks the test address.',
    );
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
