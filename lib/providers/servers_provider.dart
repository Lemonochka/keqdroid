part of 'providers.dart';

class ServersState {
  final List<ServerItem> servers;
  final String? activeServerId;
  final bool isLoading;
  final String? error;

  /// Индекс серверов по id — считается один раз на состояние, чтобы каждый
  /// `_ServerTile` не искал себя в `servers` линейно (O(N²) на длинный список).
  final Map<String, ServerItem> byId;

  ServersState({
    this.servers = const [],
    this.activeServerId,
    this.isLoading = false,
    this.error,
  }) : byId = {for (final s in servers) s.id: s};

  ServerItem? get activeServer => byId[activeServerId];

  // sentinel чтобы отличить "не передали" от явного null (сброс activeServerId):
  // через обычный nullable + ?? занулить поле в copyWith не получится
  static const _sentinel = Object();

  ServersState copyWith({
    List<ServerItem>? servers,
    Object? activeServerId = _sentinel,
    bool? isLoading,
    String? error,
  }) =>
      ServersState(
        servers: servers ?? this.servers,
        activeServerId: activeServerId == _sentinel
            ? this.activeServerId
            : activeServerId as String?,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

class ServersNotifier extends Notifier<ServersState> {
  @override
  ServersState build() {
    _load();
    return ServersState(isLoading: true);
  }

  Future<void> _load() async {
    final storage = ref.read(storageProvider);
    final servers = await _syncChains(storage, await storage.getServers());
    final activeId = storage.getActiveServerId();
    state = ServersState(servers: servers, activeServerId: activeId);
  }

  /// Подтягивает в цепочки свежие ссылки их узлов.
  ///
  /// Обновление подписки переписывает ссылки серверов (ротация
  /// reality-параметров, смена порта), а цепочка хранит их снимок — без этого
  /// шага она молча оставалась бы на протухшем конфиге. Узлы, которых в списке
  /// уже нет, остаются на снимке: цепочка продолжает работать по последней
  /// известной ссылке, а не разваливается.
  ///
  /// Пишем только реально изменившиеся цепочки — обычная загрузка списка не
  /// должна дёргать хранилище.
  Future<List<ServerItem>> _syncChains(
    StorageService storage,
    List<ServerItem> servers,
  ) async {
    final chains = servers.where((s) => s.protocol == 'chain').toList();
    if (chains.isEmpty) return servers;

    final live = <String, ({String config, String name})>{
      for (final s in servers)
        if (s.protocol != 'chain')
          s.id: (config: s.config, name: s.displayName),
    };

    var result = servers;
    for (final chain in chains) {
      final refreshed = chain.chainConfig!.refreshed(live);
      if (identical(refreshed, chain.chainConfig)) continue;
      final updated = chain.copyWith(config: refreshed.encode());
      try {
        await storage.upsertServer(updated);
      } catch (e, st) {
        AppLogger.instance.warn(
          'Failed to refresh proxy chain nodes',
          error: e,
          stackTrace: st,
        );
        continue;
      }
      result = [
        for (final s in result) s.id == updated.id ? updated : s,
      ];
    }
    return result;
  }

  /// Создаёт цепочку из выбранных серверов (порядок — от входного узла к
  /// выходному) и кладёт её в список обычным сервером.
  Future<ServerItem> saveChain({
    String? id,
    required String name,
    required List<ServerItem> hops,
  }) async {
    if (hops.length < 2) {
      throw Exception('A proxy chain needs at least two nodes');
    }
    if (hops.length > ProxyChainConfig.maxHops) {
      throw Exception(
        'A proxy chain holds at most ${ProxyChainConfig.maxHops} nodes',
      );
    }
    for (final hop in hops) {
      if (!ProxyChainConfig.canBeHop(hop.protocol)) {
        throw Exception(
          '${hop.displayName}: ${hop.protocol.toUpperCase()} cannot be a chain node',
        );
      }
    }

    final config = ProxyChainConfig(
      name: name.trim(),
      hops: [
        for (final hop in hops)
          ProxyChainHop(
            serverId: hop.id,
            name: hop.displayName,
            config: hop.config,
          ),
      ],
    ).encode();

    if (id == null) {
      final server = ServerItem.fromRaw(config);
      await ref.read(storageProvider).upsertServer(server);
      state = state.copyWith(servers: [...state.servers, server]);
      return server;
    }

    await _updateServer(id, (s) => s.copyWith(config: config));
    return state.servers.firstWhere((s) => s.id == id);
  }

  Future<void> reload() => _load();

  /// перечитывает серверы после обновления подписки.
  /// subscription_service переиспользует старые ID при совпадении конфига,
  /// так что activeServerId в storage уже актуален — просто читаем заново
  Future<void> reloadPreservingActive() => _load();

  Future<void> setActive(ServerItem server) async {
    await ref.read(storageProvider).setActiveServerId(server.id);
    state = state.copyWith(activeServerId: server.id);
  }

  Future<void> addManual(String rawConfig) async {
    final config = rawConfig.trim();
    final validationError = validateServerConfig(config);
    if (validationError != null) throw Exception(validationError);
    if (state.servers.any((s) => s.config == config)) {
      throw Exception('This server is already added');
    }
    final server = ServerItem.fromRaw(config);
    await ref.read(storageProvider).upsertServer(server);
    state = state.copyWith(servers: [...state.servers, server]);
  }

  /// Пользовательское имя сервера; null/пусто — сброс к имени из конфига.
  Future<void> rename(String id, String? name) async {
    final trimmed = name?.trim();
    await _updateServer(
      id,
      (s) => s.copyWith(
        customName: (trimmed == null || trimmed.isEmpty) ? null : trimmed,
      ),
    );
  }

  Future<void> togglePin(String id) async {
    await _updateServer(
      id,
      (s) => s.copyWith(pinnedAt: s.isPinned ? null : DateTime.now()),
    );
  }

  /// Замена конфига сервера из GUI-редактора. Для подписочных серверов взводит
  /// configOverridden, чтобы правка пережила обновление подписки.
  Future<void> updateConfig(String id, String rawConfig) async {
    final config = rawConfig.trim();
    final validationError = validateServerConfig(config);
    if (validationError != null) throw Exception(validationError);
    if (state.servers.any((s) => s.id != id && s.config == config)) {
      throw Exception('This server is already added');
    }
    await _updateServer(
      id,
      (s) => s.copyWith(
        config: config,
        configOverridden: s.type == ServerItemType.subscription &&
            (s.configOverridden || config != s.config),
      ),
    );
  }

  /// Возврат подписочного сервера к конфигу из подписки: снимает
  /// override-флаг и тянет свежий конфиг рефрешем подписки.
  Future<void> revertConfigOverride(ServerItem server) async {
    if (!server.configOverridden || server.subscriptionId == null) return;
    await _updateServer(server.id, (s) => s.copyWith(configOverridden: false));
    final subs = ref.read(subscriptionsProvider).value ?? [];
    final sub = subs.cast<Subscription?>().firstWhere(
          (s) => s?.id == server.subscriptionId,
          orElse: () => null,
        );
    if (sub != null) {
      await ref.read(subscriptionsProvider.notifier).refreshTracked(sub);
    }
  }

  /// Точечное обновление сервера: пишет через serial-очередь storage и
  /// обновляет state, не трогая остальной список.
  Future<void> _updateServer(
    String id,
    ServerItem Function(ServerItem) change,
  ) async {
    final idx = state.servers.indexWhere((s) => s.id == id);
    if (idx == -1) return;
    final updated = change(state.servers[idx]);
    await ref.read(storageProvider).upsertServer(updated);
    final list = [...state.servers]..[idx] = updated;
    state = state.copyWith(servers: list);
  }

  static String? validateServerConfig(String rawConfig) {
    if (rawConfig.isEmpty) return 'Configuration is empty';

    // Цепочка серверов: собственный формат приложения, узлы внутри уже
    // проверены при сборке — здесь только целостность ссылки.
    if (ProxyChainConfig.looksLikeChain(rawConfig)) {
      return ProxyChainConfig.describeProblem(rawConfig);
    }

    if (AwgProfile.isAwgConfig(rawConfig)) {
      try {
        AwgProfile.parse(rawConfig);
      } catch (e) {
        return 'Invalid AmneziaWG config: $e';
      }
      return null;
    }

    // Готовый конфиг ядра целиком (провайдеры отдают такие «сервера с готовым
    // роутингом»): проверяем, что это именно xray-конфиг с аутбаундами.
    if (CustomXrayConfig.looksLikeJson(rawConfig)) {
      return CustomXrayConfig.describeProblem(rawConfig);
    }

    final lower = rawConfig.toLowerCase();
    if (!(lower.startsWith('vless://') ||
        lower.startsWith('vmess://') ||
        lower.startsWith('trojan://') ||
        lower.startsWith('ss://') ||
        lower.startsWith('ssr://') ||
        lower.startsWith('hysteria://') ||
        lower.startsWith('hysteria2://') ||
        lower.startsWith('hy2://'))) {
      return 'Unsupported format. Use vless://, vmess://, trojan://, ss://, ssr://, hysteria://, hysteria2://, hy2:// or AmneziaWG .conf';
    }

    if (lower.startsWith('vmess://')) {
      final payload = rawConfig.substring('vmess://'.length).trim();
      try {
        final decoded = utf8.decode(base64.decode(base64.normalize(payload)));
        final json = jsonDecode(decoded);
        if (json is! Map<String, dynamic>) return 'Invalid vmess config';
        final host = (json['add'] ?? '').toString().trim();
        final port = int.tryParse((json['port'] ?? '').toString()) ?? 0;
        if (host.isEmpty || port <= 0) return 'Invalid vmess config: host or port missing';
      } catch (_) {
        return 'Invalid vmess config';
      }
      return null;
    }

    try {
      final uri = Uri.parse(rawConfig);
      if (uri.host.isEmpty || uri.port <= 0) {
        return 'Invalid server config: host or port missing';
      }
      if (lower.startsWith('hysteria://') ||
          lower.startsWith('hysteria2://') ||
          lower.startsWith('hy2://')) {
        final qp = uri.queryParameters;
        final auth = (qp['auth'] ?? qp['password'] ?? '').trim();
        final fromUser = uri.userInfo.trim().isNotEmpty
            ? Uri.decodeComponent(uri.userInfo).trim()
            : '';
        if (auth.isEmpty && fromUser.isEmpty) {
          return 'Invalid hysteria config: add auth (query auth= / password= or userInfo before @)';
        }
      }
    } catch (_) {
      return 'Invalid server config';
    }
    return null;
  }

  Future<void> delete(String id) async {
    await ref.read(storageProvider).deleteServer(id);
    state = state.copyWith(
      servers: state.servers.where((s) => s.id != id).toList(),
      activeServerId: state.activeServerId == id ? null : state.activeServerId,
    );
  }

  /// батч-обновление ping + типа теста: один write в storage и один rebuild
  Future<void> updatePingResults(
    Map<String, ({int? pingMs, String? lastPingType})> updates,
  ) async {
    if (updates.isEmpty) return;
    // Мержим в актуальный список ВНУТРИ serial-очереди storage: запись
    // снапшота провайдера целиком (saveServers) затирала серверы, если
    // параллельно успела обновиться подписка.
    final merged = await ref
        .read(storageProvider)
        .applyPingUpdates(updates, DateTime.now());
    state = state.copyWith(servers: merged);
  }

  /// пингует серверы: UI обновляем по мере результатов, в storage пишем разом в конце
  Future<List<PingResult>> _pingServersWithBatchedUpdates(
    List<ServerItem> servers,
  ) async {
    final results = <PingResult>[];
    final pending = <String, ({int? pingMs, String? lastPingType})>{};

    // Троттлинг UI: результаты приходят по одному, а каждый эмит state
    // перестраивает всю панель серверов (перегруппировка, пересортировка групп,
    // все раскрытые тайлы). Копим результаты и применяем пачкой ~5 раз/сек —
    // прогресс в UI живой, но ребилдов на порядок меньше на больших списках.
    final buffered = <PingResult>[];
    void flushBufferedToState() {
      if (buffered.isEmpty) return;
      final newList = [...state.servers];
      final indexById = <String, int>{
        for (var i = 0; i < newList.length; i++) newList[i].id: i,
      };
      final now = DateTime.now();
      for (final r in buffered) {
        final idx = indexById[r.serverId];
        if (idx == null) continue;
        newList[idx] = newList[idx].copyWith(
          pingMs: r.success ? r.latencyMs : null,
          lastTestedAt: now,
          lastPingType: PingService.pingTypeToStored(r.pingType),
        );
      }
      buffered.clear();
      state = state.copyWith(servers: newList);
    }
    final settings = await ref.read(storageProvider).getSettings();
    final vpnState = await _vpnStateForPing();
    final vpnConnected = vpnState?.status == VpnStatus.connected;
    final tunMode = vpnState?.activeMode == ConnectionMode.tun;
    // Raw TCP ping is unmeasurable through a TUN tunnel — switch to URL ping.
    final pingType = PingService.pingTypeForConnectionState(
      PingService.pingTypeFromSettings(settings),
      vpnConnected: vpnConnected,
      tunMode: tunMode,
    );
    final testUrl = PingTestConfig.resolveTestUrl(settings);

    Future<String?> resolveServerIp(ServerItem server) =>
        _resolveFirstAddress(server.address);

    final anySpeed = servers.any(
      (s) => PingService.effectivePingType(s, pingType) == PingType.speed,
    );
    final anyUrl = servers.any(
      (s) => PingService.effectivePingType(s, pingType) == PingType.url,
    );

    final flushTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => flushBufferedToState(),
    );

    // Крутилка на каждом тайле, а не только на кнопке группы. Раньше её ставил
    // один pingSingle, поэтому «пинг всех» выглядел так, будто ничего не
    // происходит: список стоял неподвижно, пока не приедет первый результат.
    // Гасим по одному, по мере готовности, — видно, как замер идёт по списку.
    final pingingIds = servers.map((s) => s.id).toSet();
    ref
        .read(pingingServerIdsProvider.notifier)
        .update((set) => {...set, ...pingingIds});
    void stopPinging(Iterable<String> ids) {
      if (ids.isEmpty) return;
      ref
          .read(pingingServerIdsProvider.notifier)
          .update((set) => {...set}..removeAll(ids));
    }

    try {
      await PingService.pingBatch(
        servers,
        pingType,
        settings: settings,
        proxyPort: settings.localPort,
        timeoutSeconds: anySpeed ? 20 : (anyUrl ? 8 : 5),
        batchSize: 5,
        vpnConnected: vpnConnected,
        testUrl: testUrl,
        resolveServerIp: (anyUrl || anySpeed) ? resolveServerIp : null,
        onResult: (result) {
          results.add(result);
          pending[result.serverId] = (
            pingMs: result.success ? result.latencyMs : null,
            lastPingType: PingService.pingTypeToStored(result.pingType),
          );
          buffered.add(result);
          // Не через buffered: цифра может подождать общий флаш, а крутилка,
          // висящая над уже готовым результатом, читается как «завис».
          pingingIds.remove(result.serverId);
          stopPinging([result.serverId]);
        },
      );
    } finally {
      flushTimer.cancel();
      flushBufferedToState();
      // Сюда попадают те, по кому результата так и не пришло, — например если
      // весь батч упал исключением на полпути.
      stopPinging(pingingIds);
    }

    if (pending.isNotEmpty) {
      // Мержим результаты в актуальный список из storage, а не пишем снапшот
      // провайдера целиком: если за время пинга обновилась подписка, снапшот
      // устарел и затёр бы её новые серверы.
      final merged = await ref
          .read(storageProvider)
          .applyPingUpdates(pending, DateTime.now());
      state = state.copyWith(servers: merged);
    }
    return results;
  }

  /// Состояние VPN для выбора типа пинга.
  ///
  /// Снимком читать нельзя: пока провайдер в loading (первый кадр после старта,
  /// смена сервера, перезапуск ядра) `.value` отдаёт null, «подключены» выходит
  /// false — и замер уходит сырым TCP прямо в туннель, где меряет локальный
  /// конец вместо сервера. Ждём первое значение, но недолго: пинг не должен
  /// зависать из-за состояния, а без него отработает как раньше.
  Future<VpnState?> _vpnStateForPing() async {
    final snapshot = ref.read(vpnStateProvider);
    if (snapshot.hasValue) return snapshot.value;
    try {
      return await ref
          .read(vpnStateProvider.future)
          .timeout(const Duration(milliseconds: 700));
    } catch (_) {
      return null;
    }
  }

  Future<void> pingAll() async {
    await _pingServersWithBatchedUpdates(state.servers);
  }

  /// пингует серверы одной подписки (или manual-серверы при subscriptionId == null)
  ///
  /// Цепочки в «ручную» группу не входят — у них своя ([pingChains]).
  Future<void> pingSubscription(String? subscriptionId) {
    final servers = subscriptionId == null
        ? state.servers
            .where((s) => s.subscriptionId == null && s.protocol != 'chain')
            .toList()
        : state.servers
            .where((s) => s.subscriptionId == subscriptionId)
            .toList();
    return _pingScoped(subscriptionId ?? manualGroupKey, servers);
  }

  /// Ключ скоупа группы цепочек — общий для пинга, сворачивания и сортировки.
  static const String chainsGroupKey = '__chains__';

  /// То же для серверов, добавленных руками (без подписки).
  static const String manualGroupKey = '__manual__';

  Future<void> pingChains() => _pingScoped(
        chainsGroupKey,
        state.servers.where((s) => s.protocol == 'chain').toList(),
      );

  Future<void> _pingScoped(String scopeKey, List<ServerItem> servers) async {
    ref.read(pingingScopesProvider.notifier).update((set) => {...set, scopeKey});
    try {
      final results = await _pingServersWithBatchedUpdates(servers);
      if (results.isNotEmpty && results.every((r) => !r.success)) {
        final firstErr =
            results.first.error.isEmpty ? 'All pings failed' : results.first.error;
        throw Exception(firstErr);
      }
    } finally {
      ref.read(pingingScopesProvider.notifier)
          .update((set) => {...set}..remove(scopeKey));
    }
  }

  Future<void> pingSingle(String serverId) async {
    ref.read(pingingServerIdsProvider.notifier).update((set) => {...set, serverId});
    final server = state.servers.cast<ServerItem?>().firstWhere(
          (s) => s?.id == serverId,
      orElse: () => null,
    );
    if (server == null) {
      ref.read(pingingServerIdsProvider.notifier)
          .update((set) => {...set}..remove(serverId));
      return;
    }
    try {
      final settings = await ref.read(storageProvider).getSettings();
      final vpnState = await _vpnStateForPing();
      final vpnConnected = vpnState?.status == VpnStatus.connected;
      final tunMode = vpnState?.activeMode == ConnectionMode.tun;
      // Raw TCP ping is unmeasurable through a TUN tunnel — switch to URL ping.
      final pingType = PingService.pingTypeForConnectionState(
        PingService.pingTypeFromSettings(settings),
        vpnConnected: vpnConnected,
        tunMode: tunMode,
      );
      String? serverIp;
      final effectiveType = PingService.effectivePingType(server, pingType);
      if (effectiveType == PingType.url || effectiveType == PingType.speed) {
        serverIp = await _resolveFirstAddress(server.address);
      }
      final result = await PingService.ping(
        server,
        pingType,
        settings: settings,
        proxyPort: settings.localPort,
        timeoutSeconds: effectiveType == PingType.speed
            ? 20
            : (effectiveType == PingType.url ? 8 : 5),
        testUrl: PingTestConfig.resolveTestUrl(settings),
        vpnConnected: vpnConnected,
        resolvedServerIp: serverIp,
      );
      await updatePingResults({
        serverId: (
          pingMs: result.success ? result.latencyMs : null,
          lastPingType: PingService.pingTypeToStored(result.pingType),
        ),
      });
      if (!result.success) {
        throw Exception(result.error.isEmpty ? 'Ping failed' : result.error);
      }
    } finally {
      ref.read(pingingServerIdsProvider.notifier)
          .update((set) => {...set}..remove(serverId));
    }
  }
}

final serversProvider = NotifierProvider<ServersNotifier, ServersState>(
  ServersNotifier.new,
);
