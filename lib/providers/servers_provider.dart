part of 'providers.dart';

class ServersState {
  final List<ServerItem> servers;
  final String? activeServerId;
  final bool isLoading;
  final String? error;

  final Map<String, ServerItem> byId;

  ServersState({
    this.servers = const [],
    this.activeServerId,
    this.isLoading = false,
    this.error,
  }) : byId = {for (final s in servers) s.id: s};

  ServerItem? get activeServer => byId[activeServerId];

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
  Future<void>? _initialLoad;
  DateTime? _lastAutoPing;

  @override
  ServersState build() {
    _initialLoad = _load();
    return ServersState(isLoading: true);
  }

  // на возврат в приложение не чаще раза в 15 минут, иначе каждое переключение окон гоняло бы пинг
  Future<void> autoPingAll() async {
    final last = _lastAutoPing;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(minutes: 15)) {
      return;
    }
    if (!(await ref.read(storageProvider).getSettings()).autoPing) return;
    await _initialLoad;
    if (state.servers.isEmpty || ref.read(pingingServerIdsProvider).isNotEmpty) {
      return;
    }
    _lastAutoPing = DateTime.now();
    await pingAll();
  }

  Future<void> autoPingSubscription(String subscriptionId) async {
    if (!(await ref.read(storageProvider).getSettings()).autoPing) return;
    if (ref.read(pingingScopesProvider).contains(subscriptionId)) return;
    try {
      await pingSubscription(subscriptionId);
    } catch (_) {
      // все замеры упали: на ручном пинге это сообщение, тут его показать некому
    }
  }

  Future<void> _load() async {
    final storage = ref.read(storageProvider);
    final servers = await _syncChains(storage, await storage.getServers());
    final activeId = storage.getActiveServerId();
    state = ServersState(servers: servers, activeServerId: activeId);
  }

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
      if (chainHopBackends(hop.config).isEmpty) {
        throw Exception(
          '${hop.displayName}: ${hop.protocol.toUpperCase()} cannot be a chain node',
        );
      }
    }

    final chain = ProxyChainConfig(
      name: name.trim(),
      hops: [
        for (final hop in hops)
          ProxyChainHop(
            serverId: hop.id,
            name: hop.displayName,
            config: hop.config,
          ),
      ],
    );
    if (chainBackends(chain).isEmpty) {
      throw Exception('No single core can link all nodes of this chain');
    }
    final config = chain.encode();

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

  Future<void> reloadPreservingActive() => _load();

  Future<void> setActive(ServerItem server) async {
    await ref.read(storageProvider).setActiveServerId(server.id);
    state = state.copyWith(activeServerId: server.id);
  }

  Future<void> addManual(String rawConfig) async {
    final config = normalizeImportedConfig(rawConfig);
    final validationError = validateServerConfig(config);
    if (validationError != null) throw Exception(validationError);

    final configs = MieruLink.expand(config);
    final fresh = configs
        .where((c) => !state.servers.any((s) => s.config == c))
        .toList();
    if (fresh.isEmpty) throw Exception('This server is already added');

    final added = <ServerItem>[];
    for (final c in fresh) {
      final server = ServerItem.fromRaw(c);
      await ref.read(storageProvider).upsertServer(server);
      added.add(server);
    }
    state = state.copyWith(servers: [...state.servers, ...added]);
  }

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

  Future<void> updateConfig(String id, String rawConfig) async {
    final config = normalizeImportedConfig(rawConfig);
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

  static String normalizeImportedConfig(String rawConfig) {
    final trimmed = rawConfig.trim();
    if (!AwgUri.looksLikeUri(trimmed)) return trimmed;
    try {
      return AwgUri.toConf(trimmed);
    } on ArgumentError {
      return trimmed;
    }
  }

  static String? validateServerConfig(String rawConfig) {
    if (rawConfig.isEmpty) return 'Configuration is empty';

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

    if (AwgUri.looksLikeUri(rawConfig)) {
      try {
        AwgProfile.parse(AwgUri.toConf(rawConfig));
      } catch (e) {
        return 'Invalid AmneziaWG link: $e';
      }
      return null;
    }

    if (CustomClashConfig.looksLikeClash(rawConfig)) {
      return CustomClashConfig.describeProblem(rawConfig);
    }
    if (SingboxOutbounds.looksLike(rawConfig)) {
      return SingboxOutbounds.describeProblem(rawConfig) ??
          'A sing-box config lists several servers: add it through import, '
              'not as the config of one server';
    }
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
        lower.startsWith('hy2://') ||
        lower.startsWith('tuic://') ||
        lower.startsWith('anytls://') ||
        lower.startsWith('mierus://') ||
        SocksLink.isSocks(rawConfig))) {
      return 'Unsupported format. Use vless://, vmess://, trojan://, ss://, ssr://, hysteria://, hysteria2://, hy2://, tuic://, anytls://, mierus://, socks://, wg://, an Xray JSON config, a sing-box config, a Clash YAML config or an AmneziaWG .conf';
    }

    if (HysteriaLinkParams.isV1(rawConfig)) {
      return 'Hysteria v1 is not supported. Ask the provider for a hysteria2:// link';
    }

    if (lower.startsWith('ssr://')) {
      return SsrLink.tryParse(rawConfig) == null
          ? 'Invalid SSR link: expected ssr:// with base64 of '
              'host:port:protocol:method:obfs:password'
          : null;
    }
    if (lower.startsWith('mierus://')) {
      return MieruLink.tryParse(rawConfig) == null
          ? 'Invalid Mieru link: it needs a host and port/protocol pairs'
          : null;
    }
    if (SocksLink.isSocks(rawConfig)) {
      return SocksLink.tryParse(rawConfig) == null
          ? 'Invalid SOCKS link: it needs a host and a port'
          : null;
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

  Future<void> updatePingResults(
    Map<String, ({int? pingMs, String? lastPingType})> updates,
  ) async {
    if (updates.isEmpty) return;
    // мержим внутри очереди storage: запись снапшота целиком затирала параллельно обновлённую подписку
    final merged = await ref
        .read(storageProvider)
        .applyPingUpdates(updates, DateTime.now());
    state = state.copyWith(servers: merged);
  }

  Future<List<PingResult>> _pingServersWithBatchedUpdates(
    List<ServerItem> servers,
  ) async {
    final results = <PingResult>[];
    final pending = <String, ({int? pingMs, String? lastPingType})>{};

    final buffered = <PingResult>[];

    final pingingIds = servers.map((s) => s.id).toSet();
    void stopPinging(Iterable<String> ids) {
      if (ids.isEmpty) return;
      ref
          .read(pingingServerIdsProvider.notifier)
          .update((set) => {...set}..removeAll(ids));
    }

    void flushBufferedToState() {
      if (buffered.isEmpty) return;
      final done = [for (final r in buffered) r.serverId];
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
      pingingIds.removeAll(done);
      stopPinging(done);
    }
    final settings = await ref.read(storageProvider).getSettings();
    final vpnState = await _vpnStateForPing();
    final vpnConnected = vpnState?.status == VpnStatus.connected;
    final tunMode = vpnState?.activeMode == ConnectionMode.tun;
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

    ref
        .read(pingingServerIdsProvider.notifier)
        .update((set) => {...set, ...pingingIds});

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
        },
      );
    } finally {
      flushTimer.cancel();
      flushBufferedToState();
      stopPinging(pingingIds);
    }

    if (pending.isNotEmpty) {
      // мержим в список из storage: снапшот провайдера затёр бы подписку, обновлённую за время пинга
      final merged = await ref
          .read(storageProvider)
          .applyPingUpdates(pending, DateTime.now());
      state = state.copyWith(servers: merged);
    }
    return results;
  }

  // снимок в loading даёт null, и сырой TCP-замер ушёл бы в туннель мерить локальный конец
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

  static const String chainsGroupKey = kChainsServerGroupKey;

  static const String manualGroupKey = kManualServerGroupKey;

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
