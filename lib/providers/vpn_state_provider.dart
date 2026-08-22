part of 'providers.dart';

/// Что делать с состоянием из натива, пока идёт НАША попытка подключения.
enum ConnectInFlightAction {
  /// Не трогать состояние: сообщение ничего не говорит об исходе попытки.
  ignore,

  /// Применить, попытка продолжается.
  apply,

  /// Применить и считать попытку завершённой.
  applyAndFinish,
}

/// Правило отсечки для [VpnStateNotifier].
///
/// Ключевой случай — `disconnected` до старта сессии. Между тапом и запуском
/// сервиса стрим и полутрасекундный поллинг успевают доложить «отключено»,
/// потому что сервис ещё не поднят. Принять этот ответ за исход попытки —
/// значит погасить UI на полпути: connecting → disconnected → connected.
/// Особенно заметно на первом подключении, когда сервис холодный.
ConnectInFlightAction connectInFlightAction(
  VpnStatus status, {
  required bool awaitingSessionStart,
}) {
  if (awaitingSessionStart && status == VpnStatus.disconnected) {
    return ConnectInFlightAction.ignore;
  }
  return switch (status) {
    VpnStatus.connected ||
    VpnStatus.disconnected =>
      ConnectInFlightAction.applyAndFinish,
    VpnStatus.error => ConnectInFlightAction.apply,
    _ => ConnectInFlightAction.ignore,
  };
}

class VpnStateNotifier extends AsyncNotifier<VpnState> {
  StreamSubscription<VpnState>? _sub;
  bool _connectInFlight = false;
  // Окно от тапа до фактического старта сессии. Всё это время нативный сервис
  // ещё не поднят и честно отвечает `disconnected` — принимать этот ответ за
  // исход НАШЕЙ попытки нельзя.
  bool _awaitingSessionStart = false;
  bool _serverSwitchInProgress = false;
  // Пользователь отменил попытку подключения (тап по кругу в connecting) —
  // connect-in-flight сворачивается в disconnected вместо error/connected.
  bool _cancelRequested = false;
  // Сигналит _waitForDisconnected при приходе события disconnected из стрима —
  // вместо опроса state с фиксированными задержками.
  Completer<void>? _disconnectWaiter;
  Timer? _androidPollTimer;
  AppLifecycleListener? _androidLifecycle;

  void _applyNativeState(VpnState s) {
    _restoreSocksCredentialsIfNeeded(s);
    _syncMihomoApiSession(s);
    if (_serverSwitchInProgress && s.status == VpnStatus.error) return;
    if (_connectInFlight) {
      // Реальный неуспех попытки ловит _awaitNativeConnectOutcome, поэтому
      // отсечка ничего не теряет.
      switch (connectInFlightAction(
        s.status,
        awaitingSessionStart: _awaitingSessionStart,
      )) {
        case ConnectInFlightAction.ignore:
          break;
        case ConnectInFlightAction.apply:
          state = AsyncData(s);
        case ConnectInFlightAction.applyAndFinish:
          state = AsyncData(s);
          _connectInFlight = false;
      }
      return;
    }
    final current = state.value;
    if (current != null &&
        current.status == s.status &&
        current.telemetryEquals(s)) {
      return;
    }
    state = AsyncData(s);
  }

  bool _credsRestoreInFlight = false;

  /// VpnService на Android переживает пересоздание Flutter-движка, а синглтон
  /// Socks5Credentials живёт в Dart-изоляте: свежий изолят видит connected, но
  /// ходит в запароленный локальный http-инбаунд без Proxy-Authorization и
  /// получает 407 (проверка обновлений, рефреш подписок). Подтягиваем креды
  /// работающей сессии из нативного сервиса. Connect-flow перезапишет их при
  /// следующем подключении через Socks5Credentials().init.
  void _restoreSocksCredentialsIfNeeded(VpnState s) {
    if (!Platform.isAndroid) return;
    if (s.status != VpnStatus.connected) return;
    if (Socks5Credentials().isInitialized) return;
    if (_credsRestoreInFlight) return;
    _credsRestoreInFlight = true;
    unawaited(() async {
      try {
        final creds =
            await ref.read(vpnEngineProvider).fetchActiveSocksCredentials();
        if (creds != null) {
          Socks5Credentials().init(creds.username, creds.password);
          AppLogger.instance.info(
            'SOCKS5 credentials restored from the running VPN service',
          );
        }
      } finally {
        _credsRestoreInFlight = false;
      }
    }());
  }

  bool _mihomoApiRestoreInFlight = false;

  /// Держит [MihomoApiSession] в согласии с тем, что реально происходит в
  /// нативном сервисе.
  ///
  /// Два случая, когда синглтон пуст, а сессия жива: пересоздание
  /// Flutter-движка и реконнект из плитки (там ядро поднимает сервис, connect-
  /// flow в Dart не выполняется вовсе). В обоих натив достаёт пару из файла
  /// конфига, который исполняет ядро.
  ///
  /// Обратная сторона — отключение: в мёртвый порт экран «Соединения» стучался
  /// бы по три секунды на каждый опрос, показывая «Core API unreachable»
  /// вместо честного «сессии нет».
  void _syncMihomoApiSession(VpnState s) {
    if (!Platform.isAndroid) return;
    final api = MihomoApiSession();
    if (s.status == VpnStatus.disconnected || s.status == VpnStatus.error) {
      api.clear();
      return;
    }
    if (s.status != VpnStatus.connected) return;
    if (api.isActive || _mihomoApiRestoreInFlight) return;
    _mihomoApiRestoreInFlight = true;
    unawaited(() async {
      try {
        final restored = await VpnNativeBridge.getMihomoApi();
        if (restored != null) {
          api.restore(port: restored.port, secret: restored.secret);
          AppLogger.instance.info(
            'mihomo API restored from the running VPN service',
          );
        }
      } finally {
        _mihomoApiRestoreInFlight = false;
      }
    }());
  }

  void _startAndroidPolling() {
    if (!Platform.isAndroid) return;
    _androidPollTimer?.cancel();
    _androidPollTimer = Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) => unawaited(syncFromNative()),
    );
  }

  void _stopAndroidPolling() {
    _androidPollTimer?.cancel();
    _androidPollTimer = null;
  }

  void _onAndroidResumed() {
    if (!Platform.isAndroid) return;
    ref.read(vpnEngineProvider).refreshStateStream();
    unawaited(syncFromNative());
    _startAndroidPolling();
  }

  @override
  Future<VpnState> build() async {
    final engine = ref.read(vpnEngineProvider);
    unawaited(_sub?.cancel());
    _sub = engine.stateStream.listen((s) {
      if (s.status == VpnStatus.disconnected) {
        final waiter = _disconnectWaiter;
        if (waiter != null && !waiter.isCompleted) waiter.complete();
      }
      _applyNativeState(s);
    });
    ref.onDispose(() {
      _sub?.cancel();
      _stopAndroidPolling();
      _androidLifecycle?.dispose();
      _androidLifecycle = null;
    });

    if (Platform.isAndroid) {
      _androidLifecycle?.dispose();
      _androidLifecycle = AppLifecycleListener(
        onResume: _onAndroidResumed,
        onPause: _stopAndroidPolling,
        onHide: _stopAndroidPolling,
      );
      _onAndroidResumed();
    }

    try {
      return await engine.getCurrentState();
    } catch (_) {
      return VpnState.disconnected;
    }
  }

  /// Подтягивает фактическое состояние из нативного сервиса (Android VpnService).
  /// Нужно при возврате в приложение и когда VPN переключали из шторки/плитки QS.
  Future<void> syncFromNative() async {
    try {
      final s = await ref.read(vpnEngineProvider).getCurrentState();
      _applyNativeState(s);
    } catch (e, st) {
      AppLogger.instance.debug(
        'syncFromNative failed',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<VpnState> _awaitNativeConnectOutcome(VpnEngine engine) async {
    for (var i = 0; i < 150; i++) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (_cancelRequested) {
        return const VpnState(status: VpnStatus.disconnected);
      }
      final s = await engine.getCurrentState();
      if (s.status == VpnStatus.connected ||
          s.status == VpnStatus.error ||
          s.status == VpnStatus.disconnected) {
        return s;
      }
    }
    return engine.getCurrentState();
  }

  Future<void> connect({bool autostartTunFallback = false}) async {
    if (_connectInFlight) {
      AppLogger.instance.debug('VPN connect() ignored: connect already in progress');
      return;
    }

    final server = ref.read(serversProvider).activeServer;
    if (server == null) {
      state = AsyncData(VpnState(
        status: VpnStatus.error,
        errorMessage: 'No active server selected',
      ));
      return;
    }

    _connectInFlight = true;
    _cancelRequested = false;
    _awaitingSessionStart = true;

    try {
      final isAwg = AwgProfile.isAwgConfig(server.config);

      await ref.read(serversProvider.notifier).setActive(server);

      final engine = ref.read(vpnEngineProvider);

      // Плитка QS / уведомление могли уже поднять VPN, пока Flutter готовил конфиг.
      final native = await engine.getCurrentState();
      if (native.status == VpnStatus.connected) {
        state = AsyncData(native);
        return;
      }
      if (native.status == VpnStatus.connecting) {
        // Сервис уже поднимается (плитка QS / уведомление) — «отключено» из
        // стрима с этого момента говорит о нашей же сессии, отсечку снимаем.
        _awaitingSessionStart = false;
        state = AsyncData(native);
        final settled = await _awaitNativeConnectOutcome(engine);
        state = AsyncData(settled);
        if (_cancelRequested ||
            settled.status == VpnStatus.connected ||
            settled.status == VpnStatus.error) {
          return;
        }
      } else {
        state = const AsyncData(VpnState(status: VpnStatus.connecting));
      }
      // Структурированные правила (RoutingRule) складываем в текстовые списки
      // настроек — так они попадают в оба генератора конфига без правок в них.
      // Затем выкидываем geoip:/geosite:-коды, которых нет в поставляемых базах:
      // xray на неизвестном коде не игнорирует правило, а падает на разборе
      // всего конфига, и подключение умирает с «SOCKS port not ready».
      final settings = await GeoAssetService.sanitizeRules(
        applyRoutingRules(
          await ref.read(storageProvider).getSettings(),
          await ref.read(storageProvider).getRules(),
        ),
      );
      final split = ref.read(splitTunnelingProvider);
      final excludePkgs = split.excludePackages.toList();
      final includePkgs = split.includePackages.toList();
      final routingMode = routingModeFromSplit(
        includePackages: split.includePackages,
        excludePackages: split.excludePackages,
      );
      final processNames = Platform.isWindows
          ? processNamesForSplit(
              includePackages: split.includePackages,
              excludePackages: split.excludePackages,
            )
          : const <String>[];

      if (Platform.isAndroid) {
        final permitted = await engine.requestVpnPermission();
        if (!permitted) throw const VpnPermissionDeniedException();
      }

      var connectionMode = TunnelSessionBuilder.resolveMode(settings);
      if (Platform.isWindows &&
          connectionMode == ConnectionMode.proxy &&
          routingMode != AppRoutingMode.allProxy) {
        AppLogger.instance.warn(
          'Split tunneling rules are ignored in Proxy mode on Windows. '
          'Switch to TUN mode to apply per-process rules.',
        );
      }
      if (Platform.isWindows && isAwg && connectionMode == ConnectionMode.tun) {
        // AmneziaWG TUN использует sing-box (wintun) → нужны права администратора.
        // Proxy-режим (wireproxy-awg) работает без админ-прав.
        final elevated = await engine.requestVpnPermission();
        if (!elevated) {
          AppLogger.instance.warn(
            'AmneziaWG TUN requires admin rights for the sing-box wintun adapter.',
          );
        }
      }
      if (Platform.isWindows && !isAwg && connectionMode == ConnectionMode.tun) {
        final elevated = await engine.requestVpnPermission();
        if (!elevated) {
          if (autostartTunFallback) {
            connectionMode = ConnectionMode.proxy;
            AppLogger.instance.warn(
              'Autostart: TUN requires admin rights, falling back to Proxy',
            );
            // Персистим фактический режим, чтобы sidebar/tray показывали Proxy,
            // а не TUN. Иначе UI остаётся в TUN, и повторный выбор TUN не
            // срабатывает (next == current), вынуждая делать proxy→tun вручную.
            await ref.read(settingsNotifierProvider.notifier).save(
                  settings.copyWith(
                    connectionMode: ConnectionMode.proxy.storageValue,
                  ),
                );
          } else {
            AppLogger.instance.warn(
              'TUN mode: app is not elevated. sing-box may fail to create routes.',
            );
          }
        }
      }

      // 1. забираем SOCKS5-креды у нативного сервиса
      final creds = await engine.fetchSocksCredentials();
      Socks5Credentials().init(creds.username, creds.password);

      // 2. резолвим домен сервера заранее, чтобы direct-правило роутинга
      //    шло по IP, а не по домену (важно когда DNS сам идёт через прокси)
      final serverIp =
          await _resolveFirstAddress(server.address) ?? server.address;

      // Desktop system/Firefox proxy config — Windows wininet, GNOME gsettings,
      // Firefox user.js — has no field for SOCKS/HTTP credentials, so password
      // auth on the localhost inbounds makes browsers prompt endlessly. Use
      // noauth on the loopback inbounds in desktop proxy mode (safe: they bind
      // to 127.0.0.1 only). AmneziaWG proxy is already noauth via wireproxy.
      final desktopProxyNoAuth = (Platform.isWindows || Platform.isLinux) &&
          connectionMode == ConnectionMode.proxy;

      // mihomo пока только на Android и только для одиночных ссылок: цепочки и
      // готовые xray-конфиги описаны в терминах xray, переводить их незачем —
      // такие серверы остаются на своём ядре независимо от выбора.
      final mihomoPicked = !isAwg &&
          Platform.isAndroid &&
          settings.vpnCore == AppSettings.vpnCoreMihomo &&
          server.protocol != 'custom' &&
          ProxyChainConfig.tryParse(server.config) == null;

      final vpnBackend = isAwg
          ? VpnBackend.awg
          : mihomoPicked
              ? VpnBackend.mihomo
              : VpnBackend.xray;

      // Координаты API ядра нужны ДО генерации: они едут внутрь конфига.
      // У xray-пути аналога нет — там «Соединения» читают access-лог.
      final mihomoApi = MihomoApiSession();
      if (mihomoPicked) {
        await mihomoApi.renew();
      } else {
        mihomoApi.clear();
      }

      final mihomoConfig = mihomoPicked
          ? MihomoConfigGen.generate(
              server.config,
              settings,
              socksPort: settings.localPort,
              resolvedServerIp: serverIp,
              apiPort: mihomoApi.port,
              apiSecret: mihomoApi.secret,
            )
          : null;

      // AmneziaWG поднимается из сырого .conf своим ядром — xray-конфиг не нужен.
      // У mihomo свой конфиг, xray-генератор для него не запускаем.
      final xrayConfig = (isAwg || mihomoPicked)
          ? ''
          : ConfigGeneratorV2.generateConfig(
              server.config,
              settings,
              resolvedServerIp: serverIp,
              localInboundsNoAuth: desktopProxyNoAuth,
              // Готовый конфиг несёт свои geo-правила: неизвестный ядру код
              // уронил бы разбор целиком (для списков настроек это уже сделал
              // GeoAssetService.sanitizeRules выше).
              geoIndex: server.protocol == 'custom'
                  ? await GeoAssetService.index()
                  : null,
            );

      final session = TunnelSessionBuilder.build(
        settings: settings,
        xrayConfig: xrayConfig,
        vpnBackend: vpnBackend,
        awgConfig: isAwg ? server.config : null,
        mihomoConfig: mihomoConfig,
        resolvedServerIp: serverIp,
        socksUsername: creds.username,
        socksPassword: creds.password,
        excludePackages: excludePkgs,
        includePackages: includePkgs,
        excludeProcesses: routingMode == AppRoutingMode.allExceptSelected
            ? processNames
            : const [],
        includeProcesses: routingMode == AppRoutingMode.onlySelected
            ? processNames
            : const [],
        routingMode: routingMode,
        serverName: server.displayName,
        modeOverride: connectionMode,
      );
      await engine.startSession(session);
      _awaitingSessionStart = false;

      if (_cancelRequested) {
        // Отмена пришла, пока сессия поднималась — гасим её и выходим тихо.
        try {
          await engine.stopVpn();
        } catch (_) {}
        state = const AsyncData(VpnState(status: VpnStatus.disconnected));
        return;
      }

      var sessionState = await engine.getCurrentState();
      if (sessionState.status == VpnStatus.connecting) {
        sessionState = await _awaitNativeConnectOutcome(engine);
      }
      if (_cancelRequested) {
        state = const AsyncData(VpnState(status: VpnStatus.disconnected));
        return;
      }
      if (sessionState.status == VpnStatus.connected) {
        state = AsyncData(sessionState);
      } else if (sessionState.status == VpnStatus.error) {
        // Присваиваем явно: во время смены сервера _applyNativeState дропает
        // error-эмиты из стрима (_serverSwitchInProgress), а на десктопе нет
        // поллинга — без этого UI навсегда застревал в «подключается».
        state = AsyncData(sessionState);
      } else {
        state = AsyncData(VpnState(
          status: VpnStatus.connected,
          activeMode: sessionState.activeMode,
        ));
      }
    } catch (e, st) {
      if (_cancelRequested) {
        // Ошибка спровоцирована самой отменой (ядро убито стопом) —
        // это не сбой подключения, показываем спокойный «отключён».
        state = const AsyncData(VpnState(status: VpnStatus.disconnected));
        return;
      }
      AppLogger.instance.error(
        'VPN connect failed in VpnStateNotifier.connect()',
        error: e,
        stackTrace: st,
      );
      state = AsyncData(VpnState(
        status: VpnStatus.error,
        errorMessage: e.toString(),
      ));
      Error.throwWithStackTrace(e, st);
    } finally {
      _connectInFlight = false;
      _awaitingSessionStart = false;
    }
  }

  /// Отмена идущей попытки подключения (тап по кругу в состоянии connecting):
  /// гасим поднимающуюся сессию, connect-in-flight завершится как disconnected.
  /// Если connect уже не в полёте — обычный disconnect.
  Future<void> cancelConnect() async {
    if (!_connectInFlight) {
      await disconnect();
      return;
    }
    _cancelRequested = true;
    // Отмена — «отключено» из стрима снова значимо, даже если сессия ещё не
    // успела стартовать.
    _awaitingSessionStart = false;
    state = const AsyncData(VpnState(status: VpnStatus.disconnecting));
    try {
      await ref.read(vpnEngineProvider).stopVpn();
    } catch (e, st) {
      AppLogger.instance.warn(
        'cancelConnect: stopVpn failed',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> disconnect() async {
    state = const AsyncData(VpnState(status: VpnStatus.disconnecting));
    try {
      await ref.read(vpnEngineProvider).stopVpn();
    } catch (e, st) {
      AppLogger.instance.error(
        'VPN disconnect failed in VpnStateNotifier.disconnect()',
        error: e,
        stackTrace: st,
      );
      state = AsyncData(VpnState(
        status: VpnStatus.error,
        errorMessage: e.toString(),
      ));
      Error.throwWithStackTrace(e, st);
    }
  }

  /// переподключение к текущему activeServer (смена сервера на активном VPN)
  Future<void> reconnectToActiveServer() async {
    if (_serverSwitchInProgress || _connectInFlight) return;

    final status = state.value?.status;
    if (status != VpnStatus.connected && status != VpnStatus.connecting) {
      await connect();
      return;
    }

    _serverSwitchInProgress = true;
    ref.read(vpnServerSwitchInProgressProvider.notifier).set(true);
    try {
      state = const AsyncData(VpnState(status: VpnStatus.disconnecting));
      await ref.read(vpnEngineProvider).stopVpn();
      await _waitForDisconnected();
      await connect();
    } finally {
      _serverSwitchInProgress = false;
      ref.read(vpnServerSwitchInProgressProvider.notifier).set(false);
    }
  }

  Future<void> _waitForDisconnected() async {
    final status = state.value?.status;
    // Ждём только если ещё не disconnected. Чтение state и регистрация
    // _disconnectWaiter синхронны (между ними нет await), поэтому событие из
    // стрима не может проскользнуть в зазоре — гонки нет (Dart однопоточен).
    if (status != null && status != VpnStatus.disconnected) {
      final waiter = _disconnectWaiter = Completer<void>();
      try {
        await waiter.future.timeout(const Duration(seconds: 4));
      } on TimeoutException {
        // движок не прислал disconnected за таймаут — не блокируем переподключение
      } finally {
        if (identical(_disconnectWaiter, waiter)) _disconnectWaiter = null;
      }
    }
    // даём ядру/туннелю осесть перед повторным connect
    await Future.delayed(const Duration(milliseconds: 350));
  }

  Future<void> toggle() async {
    final status = state.value?.status ?? VpnStatus.disconnected;
    if (status == VpnStatus.connected || status == VpnStatus.connecting) {
      await disconnect();
    } else {
      await connect();
    }
  }
}

/// true пока переподключаемся при смене сервера — чтобы не показывать ложные ошибки
final vpnStateProvider =
    AsyncNotifierProvider<VpnStateNotifier, VpnState>(VpnStateNotifier.new);
