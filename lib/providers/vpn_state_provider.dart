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
    final api = MihomoApiSession();
    // Зачистка — на всех платформах: пара переживает сессию, а по ней
    // «Соединения» решают, к какому диалекту API обращаться.
    if (s.status == VpnStatus.disconnected || s.status == VpnStatus.error) {
      api.clear();
      return;
    }
    // Восстановление — только на Android: это единственное место, где сессия
    // ядра переживает Dart-изолят (плитка, пересоздание движка).
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
      var settings = await GeoAssetService.sanitizeRules(
        applyRoutingRules(
          await ref.read(storageProvider).getSettings(),
          await ref.read(storageProvider).getRules(),
        ),
      );
      // Свои DNS-адреса, которых ядро не исполнит, генератор выбрасывает молча
      // (иначе они не «не сработают», а не дадут ядру подняться). Пользователю
      // это видно только по тому, что его DNS «не применился» — говорим прямо.
      if (settings.xrayCore.dnsUseCustom) {
        final dropped =
            XrayCoreSettings.xrayDnsServers(settings.xrayCore.dnsServers)
                .dropped;
        if (dropped.isNotEmpty) {
          AppLogger.instance.warn(
            'Custom DNS: ${dropped.length} address(es) dropped — the core '
            'cannot run them: ${dropped.join(', ')}. Supported: plain ip[:port], '
            'https+local://, https://, h2c://, tcp://, quic+local://, '
            'localhost, fakedns.',
          );
        }
      }

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
      if ((Platform.isWindows || Platform.isLinux) &&
          connectionMode == ConnectionMode.proxy &&
          routingMode != AppRoutingMode.allProxy) {
        // Не «сплит не сработал», а «сессия идёт как весь-трафик»: без туннеля
        // ядро не знает процесса-владельца соединения, а оставленный от сплита
        // финал (`onlySelected` → DIRECT) отправил бы мимо прокси ВСЁ.
        AppLogger.instance.warn(
          'Split tunneling rules are ignored in Proxy mode on desktop: without '
          'a tunnel the core cannot tell which process a connection belongs '
          'to. The session runs as "all traffic" instead — switch to TUN mode '
          'to apply per-process rules.',
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

      // Локальные порты — это пожелание, а не факт. 2080 держит сосед (второй
      // клиент, наше же осиротевшее ядро, локальный сервер), а на Windows целые
      // диапазоны изымает Hyper-V/WSL: слушателя нет, `netstat` пуст, бинд
      // запрещён (WSAEACCES). Раньше любой из этих случаев заканчивался отказом
      // подключаться — снаружи «прокси/TUN не работает», а чинить надо руками и
      // в другом месте. Теперь порт подбирается рабочий; расхождение с
      // настройкой идёт в лог, а сами настройки НЕ переписываются.
      //
      // Ставить это раньше нельзя: выше есть ветка, которая сохраняет
      // `settings` в хранилище (автостарт без прав → Proxy), и подменённые
      // порты уехали бы в постоянные настройки.
      if (Platform.isWindows || Platform.isLinux) {
        final portPlan = await LocalPortResolver.resolve(settings);
        for (final change in portPlan.changes) {
          AppLogger.instance.warn(change.describe());
        }
        settings = portPlan.applyTo(settings);
        ActiveLocalPorts().set(
          socksPort: portPlan.socksPort,
          httpPort: portPlan.httpPort,
        );
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

      // Ядро выбирает ФОРМАТ сервера, а настройка — только там, где формат
      // берут оба (обычная ссылка). Готовый конфиг исполняет то ядро, на языке
      // которого он написан: xray-json — xray, clash-yaml — mihomo. Несовпадение
      // с выбором пользователя больше не молчит: раньше это выглядело как
      // «настройка не работает» (в списке ядер mihomo, в сессии libxray).
      final choice = resolveVpnBackend(
        config: server.config,
        preference: settings.vpnCore,
        mihomoAvailable: mihomoShipsHere,
      );
      if (choice.skip != null) {
        AppLogger.instance.warn(
          'Core preference "${settings.vpnCore}" is not used for this server: '
          '${vpnCoreSkipLogReason(choice.skip!)}. Running it on '
          '${choice.backend.wireValue}.',
        );
      }

      final vpnBackend = choice.backend;
      final mihomoPicked = vpnBackend == VpnBackend.mihomo;

      // Координаты API ядра нужны ДО генерации: они едут внутрь конфига.
      // У xray-пути аналога нет — там «Соединения» читают access-лог.
      final mihomoApi = MihomoApiSession();
      if (mihomoPicked) {
        await mihomoApi.renew();
      } else {
        mihomoApi.clear();
      }

      // Туннель принадлежит самому mihomo: адаптер, маршруты и перехват DNS —
      // его, а не sing-box'а или tun2socks. Различие платформ ровно одно: на
      // десктопе ядро создаёт устройство само, на Android получает готовый
      // дескриптор от VpnService (и потому не трогает ни адреса, ни маршруты).
      final MihomoTunOptions? mihomoTun;
      if (!mihomoPicked) {
        mihomoTun = null;
      } else if (Platform.isAndroid) {
        mihomoTun = const MihomoTunOptions(
          fromFileDescriptor: true,
          // Стек не спрашиваем: `TunSettings` — десктопная настройка, а gvisor
          // держит весь TCP/IP внутри процесса ядра, что на Android
          // единственный рабочий вариант без root.
          stack: TunSettings.stackGvisor,
          autoRoute: false,
        );
      } else if (connectionMode == ConnectionMode.tun) {
        mihomoTun = MihomoTunOptions(
          device: kTunInterfaceName,
          stack: settings.tun.stack,
          mtu: settings.tun.mtu,
          autoRoute: settings.tun.autoRoute,
          strictRoute:
              settings.tun.strictRouteEnabled(windows: Platform.isWindows),
        );
      } else {
        mihomoTun = null;
      }

      final mihomoConfig = mihomoPicked
          ? MihomoConfigGen.generate(
              server.config,
              settings,
              socksPort: settings.localPort,
              // HTTP-инбаунд — только на десктопе: под tun2socks в ядро ходят
              // одним SOCKS, а лишний слушающий порт на телефоне не нужен.
              httpPort: Platform.isAndroid ? null : settings.httpPort,
              resolvedServerIp: serverIp,
              localInboundsNoAuth: desktopProxyNoAuth,
              apiPort: mihomoApi.port,
              apiSecret: mihomoApi.secret,
              tun: mihomoTun,
              routingMode: routingMode,
              managedProcessNames: switch (routingMode) {
                AppRoutingMode.onlySelected ||
                AppRoutingMode.allExceptSelected =>
                  processNames,
                AppRoutingMode.allProxy => const <String>[],
              },
              appProcessName: Platform.isAndroid
                  ? ''
                  : p.basename(Platform.resolvedExecutable),
            )
          : null;

      // Готовый конфиг несёт свои geo-правила: неизвестный ядру код уронил бы
      // разбор целиком (для списков настроек это уже сделал
      // GeoAssetService.sanitizeRules выше).
      final customGeoIndex =
          server.protocol == 'custom' ? await GeoAssetService.index() : null;
      // Чистка молчит, а выброшенное авторское правило меняет смысл конфига:
      // его трафик проваливается в наш `final`, и с «остальной трафик = блок»
      // перестаёт ходить вовсе. Снаружи это «приложение блокирует то, что
      // провайдер пускает через прокси» — называем причину вслух.
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

      // AmneziaWG поднимается из сырого .conf своим ядром — xray-конфиг не нужен.
      // У mihomo свой конфиг, xray-генератор для него не запускаем.
      final xrayConfig = (isAwg || mihomoPicked)
          ? ''
          : ConfigGeneratorV2.generateConfig(
              server.config,
              settings,
              resolvedServerIp: serverIp,
              localInboundsNoAuth: desktopProxyNoAuth,
              geoIndex: customGeoIndex,
            );

      // Забирать ли IPv6 в туннель. Спрашиваем машину, а не только настройку:
      // IPv6-адрес на TUN-интерфейсе там, где IPv6 в системе выключен, роняет
      // sing-box на старте («set ipv6 dns: Access is denied»), то есть чинил бы
      // утечку ценой неработающего TUN. См. [TunSettings.blockIpv6Leak].
      final hostHasIpv6 = connectionMode == ConnectionMode.tun &&
              (Platform.isWindows || Platform.isLinux) &&
              settings.tun.blockIpv6Leak &&
              !mihomoPicked
          ? await hostHasGlobalIpv6(excludeInterfaceName: kTunInterfaceName)
          : false;
      // Молчаливого отката быть не должно: у mihomo туннель свой, и наш
      // sing-box-инбаунд с его IPv6-адресом в этой схеме не участвует вовсе.
      if (mihomoPicked &&
          connectionMode == ConnectionMode.tun &&
          settings.tun.blockIpv6Leak &&
          (Platform.isWindows || Platform.isLinux) &&
          await hostHasGlobalIpv6(excludeInterfaceName: kTunInterfaceName)) {
        AppLogger.instance.warn(
          'This machine has global IPv6, but the tunnel here belongs to the '
          'mihomo core, which keeps its own IPv6 handling — the TUN option '
          '"keep IPv6 inside the tunnel" covers the xray/keqrnel core only. '
          'IPv6 traffic can therefore bypass the tunnel; switch the core to '
          'xray in Settings → About if that matters.',
        );
      }

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
        hostHasIpv6: hostHasIpv6,
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
    // Порты сессии больше ничего не слушает — апдейтер обязан вернуться к
    // настройке, а не стучаться в подменённый порт умершего ядра.
    ActiveLocalPorts().clear();
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
