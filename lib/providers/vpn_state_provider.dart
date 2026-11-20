part of 'providers.dart';

enum ConnectInFlightAction { ignore, apply, applyAndFinish }

// до старта сессии сервис ещё не поднят и честно отвечает disconnected, это не исход попытки
ConnectInFlightAction connectInFlightAction(
  VpnStatus status, {
  required bool awaitingSessionStart,
}) {
  if (awaitingSessionStart && status == VpnStatus.disconnected) {
    return ConnectInFlightAction.ignore;
  }
  return switch (status) {
    VpnStatus.connected ||
    VpnStatus.disconnected => ConnectInFlightAction.applyAndFinish,
    VpnStatus.error => ConnectInFlightAction.apply,
    _ => ConnectInFlightAction.ignore,
  };
}

class VpnStateNotifier extends AsyncNotifier<VpnState> {
  StreamSubscription<VpnState>? _sub;
  bool _connectInFlight = false;
  bool _awaitingSessionStart = false;
  bool _serverSwitchInProgress = false;
  bool _cancelRequested = false;
  // сессия, которую поднял этот connect: смена сервера на mihomo берёт из неё порты, логин и пароль и API
  _LiveSession? _live;
  Completer<void>? _disconnectWaiter;
  Timer? _androidPollTimer;
  AppLifecycleListener? _androidLifecycle;

  late final _autoSelect = _AutoSelectMonitor(
    ref: () => ref,
    vpnState: () => state.value,
    reconnect: reconnectToActiveServer,
    now: () => (debugAutoSelectClock ?? DateTime.now)(),
  );

  @visibleForTesting
  static DateTime Function()? debugAutoSelectClock;

  @visibleForTesting
  Future<void> debugAutoSelectListen() => _autoSelect.listenOnce();

  @visibleForTesting
  Future<void> debugAutoSelectProbe() => _autoSelect.probe();

  @visibleForTesting
  Future<void> debugAutoSelectRecheck() => _autoSelect.recheckTick();

  late final _namesFallback = _NamesFallbackMonitor(
    ref: () => ref,
    live: () => _live,
    vpnState: () => state.value,
    reconnect: reconnectToActiveServer,
    now: () => (debugNamesFallbackClock ?? DateTime.now)(),
    probe: (port) => (debugNamesProbe ?? NamesFallback.probe)(port),
  );

  @visibleForTesting
  static DateTime Function()? debugNamesFallbackClock;

  @visibleForTesting
  static Future<NamesVerdict> Function(int httpPort)? debugNamesProbe;

  @visibleForTesting
  Future<void> debugNamesFallbackCheck() => _namesFallback.check();

  void _applyNativeState(VpnState s) {
    if (s.status == VpnStatus.connected) {
      unawaited(syncSocksCredentialsFromService());
    }
    _syncMihomoApiSession(s);
    _persistActiveLocalHttpPort(s.status);
    if (_serverSwitchInProgress && s.status == VpnStatus.error) return;
    if (_connectInFlight) {
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

  // для фоновых изолятов: мимо туннеля им нельзя, а пробовать порт мало, на нём может слушать чужой клиент
  void _persistActiveLocalHttpPort(VpnStatus status) {
    final storage = ref.read(storageProvider);
    if (status != VpnStatus.connected) {
      // сброс без await, иначе зависшая запись подключения воскресит порт после отключения
      if (storage.getActiveLocalHttpPort() != null) {
        unawaited(storage.setActiveLocalHttpPort(null));
      }
      return;
    }
    unawaited(_writeActiveLocalHttpPort(storage));
  }

  Future<void> _writeActiveLocalHttpPort(StorageService storage) async {
    // на Android через getSettings: кэш может быть холодным, и на диск уехал бы порт по умолчанию
    final port =
        ActiveLocalPorts().httpPort ?? (await storage.getSettings()).httpPort;
    if (!ref.mounted) return;
    if (state.value?.status != VpnStatus.connected) return;
    // пароль сверяем тоже: после реконнекта порт прежний, а пароль новый
    final creds = Socks5Credentials();
    final stored = storage.getActiveLocalHttpCredentials();
    if (storage.getActiveLocalHttpPort() == port &&
        stored.username == creds.username &&
        stored.password == creds.password) {
      return;
    }
    await storage.setActiveLocalHttpPort(
      port,
      username: creds.username,
      password: creds.password,
    );
  }

  Future<void>? _credsSync;

  @visibleForTesting
  static bool? debugSyncsCredentials;

  // на ПК логин и пароль держит само приложение, сверять не с кем
  static bool get _syncsCredentials =>
      debugSyncsCredentials ?? Platform.isAndroid;

  // Логин и пароль приложения и ядра расходились: свежий изолят пуст, а старт поверх живой сессии ядро
  // не перезапускает. Тогда всё приложение до перезапуска получало 407 от своего же прокси (Pixel 6a, 12.11.2026)
  Future<void> syncSocksCredentialsFromService() {
    if (!_syncsCredentials || _connectInFlight) return Future<void>.value();
    return _credsSync ??= _takeSocksCredentialsFromService().whenComplete(
      () => _credsSync = null,
    );
  }

  Future<void> _takeSocksCredentialsFromService() async {
    final creds = await ref
        .read(vpnEngineProvider)
        .fetchActiveSocksCredentials();
    // connect() сверит сам, когда поднимет ядро
    if (creds == null || !ref.mounted || _connectInFlight) return;
    final current = Socks5Credentials();
    if (current.username == creds.username &&
        current.password == creds.password) {
      return;
    }
    final restored = !current.isInitialized;
    current.init(creds.username, creds.password);
    if (restored) {
      AppLogger.instance.info(
        'SOCKS5 credentials restored from the running VPN service',
      );
    } else {
      AppLogger.instance.warn(
        'Local proxy credentials of the app differed from the running VPN '
        'session; the session ones are used now',
      );
    }
    _persistActiveLocalHttpPort(state.value?.status ?? VpnStatus.disconnected);
  }

  bool _mihomoApiRestoreInFlight = false;

  void _syncMihomoApiSession(VpnState s) {
    final api = MihomoApiSession();
    if (s.status == VpnStatus.disconnected || s.status == VpnStatus.error) {
      api.clear();
      return;
    }
    if (!Platform.isAndroid) return;
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
    _autoSelect.start();
    listenSelf((previous, next) {
      if (previous?.value?.status != VpnStatus.connected &&
          next.value?.status == VpnStatus.connected) {
        unawaited(_applyTemplatePins());
      }
    });
    if (_syncsCredentials) {
      localProxyCredentialsSync = syncSocksCredentialsFromService;
    }
    ref.onDispose(() {
      if (localProxyCredentialsSync == syncSocksCredentialsFromService) {
        localProxyCredentialsSync = null;
      }
      _autoSelect.stop();
      _namesFallback.stop();
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

  // в конфиге mihomo закрепить узел в url-test нечем, а store-selected выключен, поэтому шлём после каждого
  // подключения; список proxy-providers ядро может ещё качать, тогда Set отвечает proxy not exist
  Future<void> _applyTemplatePins() async {
    final server = ref.read(serversProvider).activeServer;
    final subId = server?.subscriptionId;
    if (server == null || subId == null) return;
    final template = ref.read(subscriptionTemplateProvider(subId));
    if (template == null || template.nodeFor(server) == null) return;
    final choices =
        (ref.read(subscriptionsProvider).value ?? const <Subscription>[])
            .where((s) => s.id == subId)
            .firstOrNull
            ?.groupChoices ??
        const <String, String>{};
    final pins = {
      for (final MapEntry(:key, :value) in choices.entries)
        if (template.pinnable(key)) key: value,
    };
    for (var attempt = 0; pins.isNotEmpty && attempt < 5; attempt++) {
      if (attempt > 0) await Future<void>.delayed(const Duration(seconds: 2));
      if (!ref.mounted || state.value?.status != VpnStatus.connected) return;
      for (final group in [...pins.keys]) {
        if (await MihomoGroupsApi.select(group, pins[group]!)) {
          pins.remove(group);
        }
      }
    }
    if (pins.isNotEmpty) {
      AppLogger.instance.warn(
        'Template pins not applied: ${pins.keys.join(', ')}',
      );
    }
    if (ref.mounted) ref.invalidate(liveTemplateGroupsProvider(subId));
  }

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
      await Future<void>.delayed(const Duration(milliseconds: 300));
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

  Future<RuleListDomains> _cachedRuleLists(AppSettings settings) async {
    try {
      final lists = await ref
          .read(ruleListServiceProvider)
          .domainsFor(settings);
      if (!lists.isEmpty) {
        AppLogger.instance.info(
          'Rule lists: block ${lists.blocked.length}, '
          'direct ${lists.direct.length}, proxy ${lists.proxy.length} domains',
        );
      }
      return lists;
    } catch (e, st) {
      AppLogger.instance.warn(
        'Rule lists unreadable, connecting without them',
        error: e,
        stackTrace: st,
      );
      return RuleListDomains.none;
    }
  }

  // на диск только правка поверх сохранённых настроек: в settings из connect() правила уже
  // сложены в списки, и так они приклеились бы к полям навсегда
  Future<void> _saveDuringConnect(
    AppSettings Function(AppSettings saved) change,
  ) async {
    final saved = await ref.read(settingsNotifierProvider.future);
    await ref.read(settingsNotifierProvider.notifier).save(change(saved));
  }

  // неизвестные geo-коды выбрасываем, xray на таком коде роняет весь конфиг; нечитаемый кэш списков подключению не мешает
  Future<({String entries, List<String> listDomains})> _prepareRouteEntries(
    String entries,
    GeoAssetIndex index,
  ) async {
    final clean = stripUnknownGeoTokensText(entries, index);
    if (clean.dropped.isNotEmpty) {
      AppLogger.instance.warn(
        'Route: geo code(s) not in the bundled bases dropped: '
        '${clean.dropped.join(', ')}',
      );
    }
    var listed = const <String>[];
    try {
      listed = await ref
          .read(ruleListServiceProvider)
          .domainsForEntries(entries);
    } catch (e) {
      AppLogger.instance.warn('Rule lists for a route unreadable: $e');
    }
    return (entries: clean.text, listDomains: listed);
  }

  Future<List<RouteServerOutbound>> _prepareRouteServers(
    List<RouteServerOutbound> servers,
  ) async {
    if (servers.isEmpty) return servers;
    final index = await GeoAssetService.index();
    final out = <RouteServerOutbound>[];
    for (final server in servers) {
      final p = await _prepareRouteEntries(server.entries, index);
      out.add(server.copyWith(entries: p.entries, listDomains: p.listDomains));
    }
    return out;
  }

  Future<List<RouteAppRules>> _prepareAppRoutes(
    List<RouteAppRules> routes,
  ) async {
    if (routes.isEmpty) return routes;
    final index = await GeoAssetService.index();
    final out = <RouteAppRules>[];
    for (final route in routes) {
      final p = await _prepareRouteEntries(route.entries, index);
      out.add(route.copyWith(entries: p.entries, listDomains: p.listDomains));
    }
    return out;
  }

  Future<void> connect({bool autostartTunFallback = false}) async {
    if (_connectInFlight) {
      AppLogger.instance.debug(
        'VPN connect() ignored: connect already in progress',
      );
      return;
    }

    final server = ref.read(serversProvider).activeServer;
    if (server == null) {
      state = AsyncData(
        VpnState(
          status: VpnStatus.error,
          errorMessage: 'No active server selected',
        ),
      );
      return;
    }

    _connectInFlight = true;
    _live = null;
    _cancelRequested = false;
    _awaitingSessionStart = true;

    try {
      await ref.read(serversProvider.notifier).setActive(server);

      final engine = ref.read(vpnEngineProvider);

      final native = await engine.getCurrentState();
      if (native.status == VpnStatus.connected) {
        state = AsyncData(native);
        return;
      }
      if (native.status == VpnStatus.connecting) {
        // сервис уже поднят плиткой или уведомлением, отсечка больше не нужна
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
      final built = (await _buildSession(
        server,
        engine,
        autostartTunFallback: autostartTunFallback,
      ))!;
      final session = built.request;
      await engine.startSession(session);
      _awaitingSessionStart = false;

      if (_cancelRequested) {
        try {
          await engine.stopVpn();
        } catch (e) {
          AppLogger.instance.debug('stopVpn after cancel failed', error: e);
        }
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
        _live = built;
        _namesFallback.connected();
      } else if (sessionState.status == VpnStatus.error) {
        // явно: при смене сервера ошибки из стрима отбрасываются, и без поллинга на десктопе UI застревал в подключении
        state = AsyncData(sessionState);
      } else {
        state = AsyncData(
          VpnState(
            status: VpnStatus.connected,
            activeMode: sessionState.activeMode,
          ),
        );
        _live = built;
        _namesFallback.connected();
      }
    } catch (e, st) {
      if (_cancelRequested) {
        state = const AsyncData(VpnState(status: VpnStatus.disconnected));
        return;
      }
      AppLogger.instance.error(
        'VPN connect failed in VpnStateNotifier.connect()',
        error: e,
        stackTrace: st,
      );
      state = AsyncData(
        VpnState(status: VpnStatus.error, errorMessage: e.toString()),
      );
      Error.throwWithStackTrace(e, st);
    } finally {
      _connectInFlight = false;
      _awaitingSessionStart = false;
      // ветки выше пишут state мимо _applyNativeState, поэтому порт сохраняем здесь
      _persistActiveLocalHttpPort(
        state.value?.status ?? VpnStatus.disconnected,
      );
      if (state.value?.status == VpnStatus.connected) {
        unawaited(syncSocksCredentialsFromService());
      }
    }
  }

  // сборка сессии для connect и для смены сервера на ходу; в reuse порты, логин и пароль и API работающего ядра,
  // а null возвращается, когда на ходу эту сессию не поднять
  Future<_LiveSession?> _buildSession(
    ServerItem server,
    VpnEngine engine, {
    _LiveSession? reuse,
    bool autostartTunFallback = false,
  }) async {
    final storage = ref.read(storageProvider);
    final profile = profileForServer(
      await storage.getRoutingProfiles(),
      server,
    );
    final saved = await storage.getSettings();
    // «Всё остальное» профиля только в эту сессию: на диск настройки пишет лишь _saveDuringConnect
    final stored = profile == null
        ? saved
        : saved.copyWith(finalOutbound: profile.finalOutbound);
    final routes = profile?.routes ?? await storage.getRoutes();
    if (profile != null) {
      AppLogger.instance.info('Routing profile: ${profile.name}');
    }

    final subId = server.subscriptionId;
    final template = subId == null ? null : storage.getClashTemplate(subId);
    String? templated;
    if (template != null) {
      final choices =
          (await storage.getSubscriptions())
              .where((s) => s.id == subId)
              .firstOrNull
              ?.groupChoices ??
          const <String, String>{};
      // кривой шаблон не повод не подключаться: сервер работает узлом, как без шаблона
      try {
        templated = templatedSessionConfig(
          server: server,
          template: template,
          settings: stored,
          choices: choices,
        );
      } catch (e, st) {
        AppLogger.instance.warn(
          'Provider template skipped',
          error: e,
          stackTrace: st,
        );
      }
    }
    if (templated != null) {
      AppLogger.instance.info('Provider template: mihomo runs it whole');
    }
    final runConfig = templated ?? server.config;

    // готовый конфиг исполняет ядро его языка, настройка решает только для обычной ссылки; выбираем до свёртки
    // маршрутов, потому что от ядра зависит, какие другие серверы встанут в конфиг
    final resolved = resolveVpnBackend(
      config: runConfig,
      preference: stored.vpnCore,
      mihomoAvailable: mihomoShipsHere,
    );
    final choice = templated != null && resolved.skip == VpnCoreSkip.clashConfig
        ? (
            backend: resolved.backend,
            format: resolved.format,
            skip: VpnCoreSkip.clashTemplate,
          )
        : resolved;
    // на ходу меняется только конфиг mihomo, для другого ядра нужны стоп и старт
    if (reuse != null && choice.backend != VpnBackend.mihomo) return null;
    // режим сохранённый: если автозапуск откатится в прокси, генератор без туннеля правил по процессам и так не напишет
    final appsRun = appRoutesRun(TunnelSessionBuilder.resolveMode(stored));
    final routeServers = await _prepareRouteServers(
      routeServerOutbounds(
        routes: routes,
        servers: ref.read(serversProvider).servers,
        activeServerId: server.id,
        core: choice.backend,
        withApps: appsRun,
      ),
    );
    final appRoutes = [
      if (appsRun)
        ...await _prepareAppRoutes(
          routeAppRules(routes: routes, outbounds: routeServers),
        ),
      ...await _prepareAppRoutes(
        routeProtocolRules(routes: routes, outbounds: routeServers),
      ),
    ];

    // маршрут на сервер без своего выхода (пропал, совпал с активным, не встаёт в ядро) уходит через VPN.
    // неизвестные geo-коды выбрасываем: xray на них падает целиком (SOCKS port not ready)
    var settings = await GeoAssetService.sanitizeRules(
      foldRoutes(
        stored,
        routes,
        serverUsable: (r) => routeServers.any((o) => o.serverId == r.serverId),
      ),
    );
    if (settings.xrayCore.dnsUseCustom) {
      final onMihomo = choice.backend == VpnBackend.mihomo;
      final dropped = onMihomo
          ? MihomoConfigGen.droppedDnsServers(settings.xrayCore.dnsServers)
          : XrayCoreSettings.xrayDnsServers(
              settings.xrayCore.dnsServers,
            ).dropped;
      if (dropped.isNotEmpty) {
        AppLogger.instance.warn(
          'Custom DNS: ${dropped.length} address(es) dropped — the core '
          'cannot run them: ${dropped.join(', ')}. Supported: '
          '${onMihomo ? 'plain ip[:port], udp://, tcp://, https://, tls://, '
                    'quic://, dhcp://, localhost' : 'plain ip[:port], '
                    'https+local://, https://, h2c://, tcp://, quic+local://, '
                    'localhost, fakedns'}.',
        );
      }
    }
    final ruleLists = await _cachedRuleLists(settings);

    final split = ref.read(splitTunnelingProvider);
    final excludePkgs = split.excludePackages.toList();
    final includePkgs = split.includePackages.toList();
    final routingMode = routingModeFromSplit(
      includePackages: split.includePackages,
      excludePackages: split.excludePackages,
    );
    final processNames = (Platform.isWindows || Platform.isLinux)
        ? processNamesForSplit(
            includePackages: split.includePackages,
            excludePackages: split.excludePackages,
          )
        : const <String>[];

    var connectionMode = TunnelSessionBuilder.resolveMode(settings);

    if (Platform.isAndroid && connectionMode != ConnectionMode.proxy) {
      final permitted = await engine.requestVpnPermission();
      if (!permitted) throw const VpnPermissionDeniedException();
    }
    if ((Platform.isWindows || Platform.isLinux) &&
        connectionMode == ConnectionMode.proxy &&
        routingMode != AppRoutingMode.allProxy) {
      AppLogger.instance.warn(
        'Split tunneling rules are ignored in Proxy mode on desktop: without '
        'a tunnel the core cannot tell which process a connection belongs '
        'to. The session runs as "all traffic" instead — switch to TUN mode '
        'to apply per-process rules.',
      );
    }
    // на ходу права проверены ещё при подключении; без прав TUN поднимает служба KeqdroidTun
    if (reuse == null &&
        Platform.isWindows &&
        connectionMode == ConnectionMode.tun) {
      final elevated =
          await engine.requestVpnPermission() ||
          await WindowsTunService.state() == TunServiceState.ready;
      if (!elevated) {
        if (autostartTunFallback) {
          connectionMode = ConnectionMode.proxy;
          AppLogger.instance.warn(
            'Autostart: TUN requires admin rights, falling back to Proxy',
          );
          // иначе интерфейс остаётся в TUN, и повторный выбор TUN не срабатывает (next == current)
          await _saveDuringConnect(
            (saved) => saved.copyWith(
              connectionMode: ConnectionMode.proxy.storageValue,
            ),
          );
        } else {
          AppLogger.instance.warn(
            'TUN mode: app is not elevated. The core may fail to create routes.',
          );
        }
      }
    }

    // настроенный порт может держать сосед, а на Windows диапазоны изымают Hyper-V и WSL,
    // поэтому подбираем рабочий и настройки не переписываем
    LocalPortPlan? portPlan;
    if (Platform.isWindows || Platform.isLinux) {
      // на ходу порты держит работающее ядро, и подбор принял бы их за чужие
      final plan = reuse?.ports ?? await LocalPortResolver.resolve(settings);
      if (reuse == null) {
        for (final change in plan.changes) {
          AppLogger.instance.warn(change.describe());
        }
        ActiveLocalPorts().set(
          socksPort: plan.socksPort,
          httpPort: plan.httpPort,
        );
      }
      settings = plan.applyTo(settings);
      portPlan = plan;
    }

    final creds = reuse?.creds ?? await engine.fetchSocksCredentials();
    // в режиме прокси логин и пароль вписывают руками в чужое приложение, а сессионные устаревали бы при каждом переподключении
    if (Platform.isAndroid &&
        connectionMode == ConnectionMode.proxy &&
        settings.proxyModeAuth) {
      var user = settings.proxyModeUser;
      var pass = settings.proxyModePass;
      if (user.isEmpty || pass.isEmpty) {
        user = randomProxyToken(12);
        pass = randomProxyToken(20);
        settings = settings.copyWith(proxyModeUser: user, proxyModePass: pass);
        await _saveDuringConnect(
          (saved) => saved.copyWith(proxyModeUser: user, proxyModePass: pass),
        );
      }
      Socks5Credentials().init(user, pass);
    } else {
      Socks5Credentials().init(creds.username, creds.password);
    }

    final serverIp =
        await _resolveFirstAddress(server.address) ?? server.address;

    // системный прокси Windows/GNOME и поле прокси у Wi-Fi не умеют пароль: с auth браузеры
    // спрашивают его без конца, а на Android ядро отбивает каждое соединение
    final proxyModeNoAuth =
        connectionMode == ConnectionMode.proxy &&
        (!Platform.isAndroid || !settings.proxyModeAuth);

    // несовпадение ядра с выбором пишем в лог: раньше это выглядело как настройка не работает
    if (choice.skip != null) {
      AppLogger.instance.warn(
        'Core preference "${settings.vpnCore}" is not used for this server: '
        '${vpnCoreSkipLogReason(choice.skip!)}. Running it on '
        '${choice.backend.wireValue}.',
      );
    }

    final vpnBackend = choice.backend;
    final mihomoPicked = vpnBackend == VpnBackend.mihomo;

    final ownerGuard = ownerGuardFor(
      android: Platform.isAndroid,
      tun: connectionMode == ConnectionMode.tun,
      routingMode: routingMode,
      sdkInt: await ref.read(androidSdkIntProvider.future),
    );

    final mihomoApi = MihomoApiSession();
    if (mihomoPicked) {
      // external-controller ядро на ходу не перечитывает, поэтому API прежний
      if (reuse == null) await mihomoApi.renew();
    } else {
      mihomoApi.clear();
    }

    final desktop = Platform.isWindows || Platform.isLinux;
    final tunSession = connectionMode == ConnectionMode.tun;
    final strictRoute = settings.tun.strictRouteEnabled(
      windows: Platform.isWindows,
    );
    // IPv6-адрес на TUN при выключенном в системе IPv6 роняет ядро; строгий маршрут на Linux закрывал IPv6
    // без маршрута (sing-tun, unreachable), теперь так же: захват и блок
    final captureIpv6 =
        desktop &&
        tunSession &&
        (settings.tun.ipv6 != TunSettings.ipv6Bypass ||
            (Platform.isLinux && strictRoute)) &&
        await hostHasGlobalIpv6(excludeInterfaceName: kTunInterfaceName);
    final ipv6ViaVpn =
        tunSession &&
        settings.tun.ipv6 == TunSettings.ipv6Vpn &&
        server.ipv6Exit == true &&
        (!desktop || captureIpv6);
    if (tunSession && settings.tun.ipv6 == TunSettings.ipv6Vpn) {
      AppLogger.instance.info(switch ((ipv6ViaVpn, server.ipv6Exit)) {
        (true, _) => 'IPv6 goes through the server: its check found IPv6.',
        (false, true) =>
          'IPv6 stays closed: this machine has no global IPv6 address.',
        (false, false) =>
          'IPv6 stays closed: the last check found no IPv6 at this server.',
        (false, null) =>
          'IPv6 stays closed until a ping checks this server '
              'for IPv6.',
      });
    }
    // с UseIPv4 ядро не отдаёт AAAA, и IPv6 через сервер никто бы не выбрал
    if (ipv6ViaVpn && settings.xrayCore.dnsQueryStrategy == 'UseIPv4') {
      settings = settings.copyWith(
        xrayCore: settings.xrayCore.copyWith(dnsQueryStrategy: 'UseIP'),
      );
    }

    final MihomoTunOptions? mihomoTun;
    if (!mihomoPicked) {
      mihomoTun = null;
    } else if (Platform.isAndroid) {
      mihomoTun = MihomoTunOptions(
        fromFileDescriptor: true,
        // на Android без root работает только gvisor
        stack: TunSettings.stackGvisor,
        autoRoute: false,
        ipv6: ipv6ViaVpn ? TunSettings.ipv6Vpn : null,
      );
    } else if (connectionMode == ConnectionMode.tun) {
      final picked = Platform.isLinux
          ? await LinuxFirewalls.tunStack(settings.tun.stack)
          : (stack: settings.tun.stack, blockedBy: null);
      if (picked.blockedBy != null) {
        AppLogger.instance.warn(
          '${picked.blockedBy!.name} is on and drops the connections the '
          '"${settings.tun.stack}" TUN stack accepts, so TCP would not go '
          'through. This session uses the gvisor stack instead.',
        );
      }
      mihomoTun = MihomoTunOptions(
        device: kTunInterfaceName,
        stack: picked.stack,
        mtu: settings.tun.mtu,
        autoRoute: settings.tun.autoRoute,
        strictRoute: strictRoute,
        ipv6: ipv6ViaVpn
            ? TunSettings.ipv6Vpn
            : (captureIpv6 ? TunSettings.ipv6Close : TunSettings.ipv6Bypass),
      );
    } else {
      mihomoTun = null;
    }

    final clashGeoIndex =
        mihomoPicked && (server.protocol == 'clash' || templated != null)
        ? await GeoAssetService.index()
        : null;
    if (clashGeoIndex != null) {
      final dropped =
          CustomClashConfig.tryParse(
            runConfig,
          )?.withKnownGeo(clashGeoIndex).dropped ??
          const <String>[];
      if (dropped.isNotEmpty) {
        AppLogger.instance.warn(
          'Provider config: ${dropped.length} rule(s) were dropped — their '
          'geo codes are not in the bundled databases: '
          '${dropped.toSet().join(', ')}. mihomo refuses the whole config on '
          'an unknown code. Their traffic now follows the next rules.',
        );
      }
    }

    final mihomoConfig = mihomoPicked
        ? MihomoConfigGen.generate(
            runConfig,
            settings,
            socksPort: settings.localPort,
            // Dart HttpClient не умеет SOCKS, а пакет приложения исключён из TUN, так что http-порт нужен и тут
            httpPort: settings.httpPort,
            resolvedServerIp: serverIp,
            localInboundsNoAuth: proxyModeNoAuth,
            apiPort: mihomoApi.port,
            apiSecret: mihomoApi.secret,
            tun: mihomoTun,
            routingMode: routingMode,
            managedProcessNames: switch (routingMode) {
              AppRoutingMode.onlySelected ||
              AppRoutingMode.allExceptSelected => processNames,
              AppRoutingMode.allProxy => const <String>[],
            },
            appProcessName: Platform.isAndroid
                ? ''
                : p.basename(Platform.resolvedExecutable),
            ruleLists: ruleLists,
            routeServers: routeServers,
            appRoutes: appRoutes,
            ownerGuard: ownerGuard,
            geoIndex: clashGeoIndex,
          )
        : null;

    final customGeoIndex = server.protocol == 'custom'
        ? await GeoAssetService.index()
        : null;
    if (server.protocol == 'custom') {
      final parsed = CustomXrayConfig.tryParse(server.config);
      final dead = parsed == null
          ? (rules: 0, tags: const <String>[])
          : previewDeadInboundRules(
              parsed.json,
              ConfigGeneratorV2.appInboundTags,
            );
      if (dead.rules > 0) {
        AppLogger.instance.warn(
          'Provider config: ${dead.rules} routing rule(s) are bound to '
          'inbound tags this app does not create '
          '(${dead.tags.toSet().join(', ')}). The app replaces the config '
          'inbounds with its own — those rules will never match, and their '
          'traffic follows "unmatched traffic" in Settings → Routing.',
        );
      }
    }
    if (customGeoIndex != null && !customGeoIndex.isEmpty) {
      final parsed = CustomXrayConfig.tryParse(server.config);
      final lost = parsed == null
          ? (tokens: const <String>[], removedRules: 0)
          : previewUnknownGeo(parsed.json, customGeoIndex);
      if (lost.removedRules > 0) {
        final blocked =
            settings.finalOutbound == AppSettings.finalOutboundBlock;
        AppLogger.instance.warn(
          'Provider config: ${lost.removedRules} routing rule(s) were '
          'dropped — their geo codes are not in the bundled databases: '
          '${lost.tokens.toSet().join(', ')}. The core exits on an unknown '
          'code, so the rules cannot be kept. Their traffic now falls '
          'through to "unmatched traffic" in Settings → Routing'
          '${blocked ? ', which is set to BLOCK — that traffic will not '
                    'connect at all. Set it to Proxy or Bypass, or replace the '
                    'codes in the config.' : '.'}',
        );
      }
    }

    final xrayDesktopTun = desktop && tunSession && !mihomoPicked;

    // проверка ходит через локальный вход и смотрит именно сервер, поэтому только там, где всё остальное через VPN
    final namesCheck =
        desktop &&
        !mihomoPicked &&
        settings.finalOutbound == AppSettings.finalOutboundProxy;
    final resolveTargets =
        !mihomoPicked &&
        NamesFallback.active(
          server,
          (debugNamesFallbackClock ?? DateTime.now)(),
        );
    if (resolveTargets) {
      AppLogger.instance.info(
        'This server did not open sites by name lately, so the core finds '
        'their addresses itself and sends the server addresses.',
      );
    }

    final listedSettings = mihomoPicked ? settings : ruleLists.expand(settings);

    final xrayConfig = mihomoPicked
        ? ''
        : ConfigGeneratorV2.generateConfig(
            server.config,
            listedSettings,
            resolvedServerIp: serverIp,
            localInboundsNoAuth: proxyModeNoAuth,
            geoIndex: customGeoIndex,
            nativeTunInbound:
                Platform.isAndroid &&
                connectionMode == ConnectionMode.tun &&
                !mihomoPicked,
            nativeTunIpv6: Platform.isAndroid && ipv6ViaVpn,
            desktopTun: xrayDesktopTun
                ? DesktopTunOptions(
                    windows: Platform.isWindows,
                    mtu: settings.tun.mtu,
                    autoRoute: settings.tun.autoRoute,
                    strictRoute: strictRoute,
                    captureIpv6: captureIpv6,
                    passIpv6: ipv6ViaVpn,
                    udpTimeoutSec: settings.tun.udpTimeoutSec,
                    routingMode: routingMode,
                    managedProcessNames: routingMode == AppRoutingMode.allProxy
                        ? const []
                        : processNames,
                    appProcessName: p.basename(Platform.resolvedExecutable),
                  )
                : null,
            routeServers: routeServers,
            appRoutes: appRoutes,
            ownerGuard: ownerGuard,
            resolveTargets: resolveTargets,
          );

    final session = TunnelSessionBuilder.build(
      settings: listedSettings,
      xrayConfig: xrayConfig,
      vpnBackend: vpnBackend,
      mihomoConfig: mihomoConfig,
      excludePackages: excludePkgs,
      includePackages: includePkgs,
      excludeProcesses: routingMode == AppRoutingMode.allExceptSelected
          ? processNames
          : const [],
      includeProcesses: routingMode == AppRoutingMode.onlySelected
          ? processNames
          : const [],
      serverName: server.displayName,
      modeOverride: connectionMode,
    );
    return (
      request: session,
      ports: portPlan,
      creds: creds,
      serverId: server.id,
      namesCheck: namesCheck,
      resolvesTargets: resolveTargets,
    );
  }

  Future<void> cancelConnect() async {
    if (!_connectInFlight) {
      await disconnect();
      return;
    }
    _cancelRequested = true;
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
    _live = null;
    state = const AsyncData(VpnState(status: VpnStatus.disconnecting));
    ActiveLocalPorts().clear();
    _persistActiveLocalHttpPort(VpnStatus.disconnecting);
    try {
      await ref.read(vpnEngineProvider).stopVpn();
    } catch (e, st) {
      AppLogger.instance.error(
        'VPN disconnect failed in VpnStateNotifier.disconnect()',
        error: e,
        stackTrace: st,
      );
      state = AsyncData(
        VpnState(status: VpnStatus.error, errorMessage: e.toString()),
      );
      Error.throwWithStackTrace(e, st);
    }
  }

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
      if (status == VpnStatus.connected && await _switchInPlace()) return;
      state = const AsyncData(VpnState(status: VpnStatus.disconnecting));
      await ref.read(vpnEngineProvider).stopVpn();
      await _waitForDisconnected();
      await connect();
    } finally {
      _serverSwitchInProgress = false;
      ref.read(vpnServerSwitchInProgressProvider.notifier).set(false);
    }
  }

  // туннель не снимается, и на время смены трафику некуда уйти мимо него; всё, что задаёт сам туннель
  // и входы, обязано совпасть с работающей сессией, иначе стоп и старт
  Future<bool> _switchInPlace() async {
    final live = _live;
    final server = ref.read(serversProvider).activeServer;
    if (live == null ||
        server == null ||
        live.request.vpnBackend != VpnBackend.mihomo) {
      return false;
    }
    final engine = ref.read(vpnEngineProvider);
    try {
      final built = await _buildSession(server, engine, reuse: live);
      if (built == null || !sameTunnelShell(live.request, built.request)) {
        AppLogger.instance.info(
          'Server switch: the tunnel changes too, reconnecting',
        );
        return false;
      }
      if (!await engine.reloadMihomoConfig(built.request)) return false;
      _live = built;
      AppLogger.instance.info('Server switched in place, the tunnel stayed up');
      return true;
    } catch (e, st) {
      AppLogger.instance.warn(
        'Server switch in place failed, reconnecting',
        error: e,
        stackTrace: st,
      );
      return false;
    }
  }

  Future<void> _waitForDisconnected() async {
    final status = state.value?.status;
    if (status != null && status != VpnStatus.disconnected) {
      final waiter = _disconnectWaiter = Completer<void>();
      try {
        await waiter.future.timeout(const Duration(seconds: 4));
      } on TimeoutException {
        AppLogger.instance.info(
          'No disconnected state within 4 s, reconnecting anyway',
        );
      } finally {
        if (identical(_disconnectWaiter, waiter)) _disconnectWaiter = null;
      }
    }
    // ядру и туннелю нужно осесть перед новым connect
    await Future<void>.delayed(const Duration(milliseconds: 350));
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

final vpnStateProvider = AsyncNotifierProvider<VpnStateNotifier, VpnState>(
  VpnStateNotifier.new,
);

typedef _LiveSession = ({
  TunnelSessionRequest request,
  LocalPortPlan? ports,
  ({String username, String password}) creds,
  String serverId,
  bool namesCheck,
  bool resolvesTargets,
});
