import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_logger.dart';
import '../core/exceptions.dart';
import '../models/app_info.dart';
import '../models/app_settings.dart';
import '../models/ping_test_config.dart';
import '../models/routing_rule.dart';
import '../models/server_item.dart';
import '../models/subscription.dart';
import '../services/ping_service.dart';
import '../services/storage_service.dart';
import '../services/subscription_service.dart';
import '../services/update_service.dart';
import '../services/tunnel_session_builder.dart';
import '../services/vpn_engine.dart';
import '../tunnel/app_routing_mode.dart';
import '../utils/config_gen.dart';
import '../utils/error_messages.dart';
import '../utils/process_name_utils.dart';
import '../utils/socks5_credentials.dart';
import '../utils/split_tunnel_routing.dart';

final storageProvider = Provider<StorageService>((ref) {
  throw UnimplementedError('Override storageProvider before runApp');
});

final subscriptionServiceProvider = Provider<SubscriptionService>((ref) {
  return SubscriptionService(ref.read(storageProvider));
});

// state для индикаторов на время обновления подписок/пинга
final subscriptionRefreshingIdsProvider = StateProvider<Set<String>>((ref) => <String>{});
final subscriptionRefreshErrorsProvider =
    StateProvider<Map<String, String>>((ref) => <String, String>{});
final pingingScopesProvider = StateProvider<Set<String>>((ref) => <String>{});
final pingingServerIdsProvider = StateProvider<Set<String>>((ref) => <String>{});
final collapsedServerGroupsProvider =
    StateProvider<Map<String, bool>>((ref) => <String, bool>{});
final collapsedSubscriptionCardsProvider =
    StateProvider<Map<String, bool>>((ref) => <String, bool>{});
final subscriptionReorderInProgressProvider =
    StateProvider<bool>((ref) => false);

/// индекс активной вкладки (0 = Servers)
final homeTabIndexProvider = StateProvider<int>((ref) => 0);

/// дробная позиция PageView для анимации при свайпе (0.0 = Servers)
final homeTabPageProvider = StateProvider<double>((ref) => 0.0);

final vpnEngineProvider = Provider<VpnEngine>((ref) {
  final engine = VpnEngine();
  engine.init();
  ref.onDispose(engine.dispose);
  return engine;
});

final updateInfoForceProvider = StateProvider<bool>((ref) => false);

final updateInfoProvider = FutureProvider<UpdateInfo?>((ref) async {
  final force = ref.watch(updateInfoForceProvider);
  return UpdateService.checkForUpdate(force: force);
});

class SubscriptionsNotifier extends AsyncNotifier<List<Subscription>> {
  Timer? _syncTimer;
  bool _autoUpdateRunning = false;
  DateTime _lastAutoUpdateCheck = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Future<List<Subscription>> build() async {
    // фоновый WorkManager пишет в SharedPreferences из другого изолята,
    // без reloadFromDisk() мы читаем устаревший кэш и lastUpdatedAt в UI не меняется
    final listener = AppLifecycleListener(
      onResume: () {
        Future(() async {
          await _syncSubscriptionsFromStorage();
          await _runInAppAutoUpdateTick(force: true);
          await _syncSubscriptionsFromStorage();
        });
      },
    );
    ref.onDispose(listener.dispose);
    _syncTimer ??= Timer.periodic(const Duration(seconds: 60), (_) async {
      await _syncSubscriptionsFromStorage();
      // сетевой auto-update гоняем только на onResume + WorkManager, не на каждый тик
    });
    ref.onDispose(() {
      _syncTimer?.cancel();
      _syncTimer = null;
    });

    return ref.read(storageProvider).getSubscriptions();
  }

  Future<void> _syncSubscriptionsFromStorage() async {
    if (ref.read(subscriptionReorderInProgressProvider)) return;
    try {
      await ref.read(storageProvider).reloadFromDisk();
    } catch (e, st) {
      AppLogger.instance.warn(
        'Failed to reload subscriptions from storage',
        error: e,
        stackTrace: st,
      );
    }
    final latest = await ref.read(storageProvider).getSubscriptions();
    final current = state.valueOrNull;
    if (current == null) return;
    if (_hasSubscriptionsChanged(current, latest)) {
      state = AsyncData(latest);
      await ref.read(serversProvider.notifier).reloadPreservingActive();
    }
  }

  Future<void> _runInAppAutoUpdateTick({bool force = false}) async {
    if (ref.read(subscriptionReorderInProgressProvider)) return;
    // fallback на случай когда WorkManager тормозит из-за Doze/OEM:
    // пока приложение открыто, сами проверяем и обновляем due-подписки
    final now = DateTime.now();
    if (_autoUpdateRunning) return;
    if (!force &&
        now.difference(_lastAutoUpdateCheck) < const Duration(minutes: 1)) {
      return;
    }
    _lastAutoUpdateCheck = now;
    _autoUpdateRunning = true;
    try {
      final service = ref.read(subscriptionServiceProvider);
      final due = await service.getDueForUpdate();
      if (due.isEmpty) return;

      final results = await Future.wait(
        due.map(service.updateSubscription),
        eagerError: false,
      );
      final hasSuccess = results.any((r) => r.success);
      if (!hasSuccess) return;

      final latest = await ref.read(storageProvider).getSubscriptions();
      state = AsyncData(latest);
      await ref.read(serversProvider.notifier).reloadPreservingActive();
    } finally {
      _autoUpdateRunning = false;
    }
  }

  bool _hasSubscriptionsChanged(List<Subscription> a, List<Subscription> b) {
    if (identical(a, b)) return false;
    if (a.length != b.length) return true;
    final byIdA = {for (final s in a) s.id: s};
    final byIdB = {for (final s in b) s.id: s};
    if (byIdA.length != byIdB.length) return true;
    for (final entry in byIdA.entries) {
      final x = entry.value;
      final y = byIdB[entry.key];
      if (y == null) return true;
      if (x.name != y.name ||
          x.url != y.url ||
          x.lastUpdatedAt != y.lastUpdatedAt ||
          x.usedBytes != y.usedBytes ||
          x.totalBytes != y.totalBytes ||
          x.expiresAt != y.expiresAt ||
          x.autoUpdate != y.autoUpdate ||
          x.serverCount != y.serverCount ||
          x.updateIntervalHours != y.updateIntervalHours) {
        return true;
      }
    }
    return false;
  }

  Future<void> add(Subscription sub) async {
    final existing = state.valueOrNull ?? await ref.read(storageProvider).getSubscriptions();
    final newUrl = _normalizeSubscriptionUrl(sub.url);
    final duplicate = existing.any(
      (s) => _normalizeSubscriptionUrl(s.url) == newUrl,
    );
    if (duplicate) {
      throw Exception('Subscription with this URL is already added');
    }

    await ref.read(storageProvider).upsertSubscription(sub);
    state = AsyncData([...?state.valueOrNull, sub]);
    try {
      await refresh(sub);
    } catch (e) {
      // первое обновление упало — откатываем add, чтобы не висели пустые подписки
      await ref.read(storageProvider).deleteSubscription(sub.id);
      state = AsyncData(
        (state.valueOrNull ?? []).where((s) => s.id != sub.id).toList(),
      );
      await ref.read(serversProvider.notifier).reloadPreservingActive();
      rethrow;
    }
  }

  static String _normalizeSubscriptionUrl(String url) {
    final trimmed = url.trim();
    try {
      final uri = Uri.parse(trimmed);
      final normalizedPath = uri.path.length > 1 && uri.path.endsWith('/')
          ? uri.path.substring(0, uri.path.length - 1)
          : uri.path;
      return uri
          .replace(
            scheme: uri.scheme.toLowerCase(),
            host: uri.host.toLowerCase(),
            path: normalizedPath,
          )
          .toString();
    } catch (_) {
      return trimmed;
    }
  }

  Future<void> remove(String id) async {
    await ref.read(storageProvider).deleteSubscription(id);
    state = AsyncData(
      (state.valueOrNull ?? []).where((s) => s.id != id).toList(),
    );
    await ref.read(serversProvider.notifier).reloadPreservingActive();
  }

  Future<void> refresh(Subscription sub) async {
    final result = await ref.read(subscriptionServiceProvider).updateSubscription(sub);

    if (result.success) {
      final subs = (state.valueOrNull ?? [])
          .map((s) => s.id == sub.id ? result.subscription : s)
          .toList();
      state = AsyncData(subs);
      await ref.read(serversProvider.notifier).reloadPreservingActive();
    } else {
      throw SubscriptionFetchException(
        result.error ?? 'Unknown error',
        url: sub.url,
      );
    }
  }

  Future<void> refreshTracked(Subscription sub) async {
    final id = sub.id;
    ref.read(subscriptionRefreshingIdsProvider.notifier).update((set) => {...set, id});
    ref.read(subscriptionRefreshErrorsProvider.notifier).update((m) {
      final next = <String, String>{...m};
      next.remove(id);
      return next;
    });

    try {
      await refresh(sub);
    } catch (e) {
      ref.read(subscriptionRefreshErrorsProvider.notifier).update((m) => {
            ...m,
            id: _shortError(e),
          });
      rethrow;
    } finally {
      ref.read(subscriptionRefreshingIdsProvider.notifier)
          .update((set) => {...set}..remove(id));
    }
  }

  Future<void> refreshAll() async {
    final subs = state.valueOrNull ?? [];
    if (subs.isEmpty) return;

    final errors = <String>[];

    await Future.wait(subs.map((sub) async {
      try {
        await refresh(sub);
      } catch (e) {
        errors.add('${sub.name}: ${_shortError(e)}');
      }
    }));

    if (errors.isNotEmpty) {
      throw Exception(errors.join('\n'));
    }
  }

  static String _shortError(Object e) {
    return explainError(e).short;
  }

  Future<void> updateInterval(String id, int hours) async {
    final subs = state.valueOrNull ?? [];
    final idx = subs.indexWhere((s) => s.id == id);
    if (idx == -1) return;
    final updated = subs[idx].copyWith(updateIntervalHours: hours);
    await ref.read(storageProvider).upsertSubscription(updated);
    final newList = [...subs]..[idx] = updated;
    state = AsyncData(newList);
  }

  Future<void> toggleAutoUpdate(String id) async {
    final subs = state.valueOrNull ?? [];
    final idx = subs.indexWhere((s) => s.id == id);
    if (idx == -1) return;
    final updated = subs[idx].copyWith(autoUpdate: !subs[idx].autoUpdate);
    await ref.read(storageProvider).upsertSubscription(updated);
    final newList = [...subs]..[idx] = updated;
    state = AsyncData(newList);
  }

  /// перемещает подписку.
  ///
  /// fromReorderableList: true когда зовётся из ReorderableListView — там Flutter
  /// даёт newIndex ещё до удаления элемента, так что при движении вниз вычитаем 1.
  /// для кнопок ↑↓ передавай false.
  Future<void> reorder(
      int oldIndex,
      int newIndex, {
        bool fromReorderableList = true,
      }) async {
    final subs = <Subscription>[...(state.valueOrNull ?? [])];
    if (oldIndex < 0 || oldIndex >= subs.length) return;

    // ReorderableListView даёт newIndex до удаления — при движении вниз правим индекс
    if (fromReorderableList && newIndex > oldIndex) newIndex -= 1;

    final item = subs.removeAt(oldIndex);
    final clampedNew = newIndex.clamp(0, subs.length);
    subs.insert(clampedNew, item);
    state = AsyncData(subs);

    // сохраняем весь список разом, иначе upsert по одному не двигает порядок в storage
    await ref.read(storageProvider).saveSubscriptions(subs);
  }

  /// меняет имя/URL подписки, серверы не трогаем
  Future<void> editMeta(String id, {String? name, String? url}) async {
    final subs = state.valueOrNull ?? [];
    final idx = subs.indexWhere((s) => s.id == id);
    if (idx == -1) return;
    if (url != null) {
      final newUrl = _normalizeSubscriptionUrl(url);
      final duplicate = subs.any(
        (s) => s.id != id && _normalizeSubscriptionUrl(s.url) == newUrl,
      );
      if (duplicate) {
        throw Exception('Subscription with this URL is already added');
      }
    }
    final updated = subs[idx].copyWith(
      name: name ?? subs[idx].name,
      url: url ?? subs[idx].url,
    );
    await ref.read(storageProvider).upsertSubscription(updated);
    final newList = [...subs]..[idx] = updated;
    state = AsyncData(newList);
  }
}

final subscriptionsProvider =
AsyncNotifierProvider<SubscriptionsNotifier, List<Subscription>>(
  SubscriptionsNotifier.new,
);

class ServersState {
  final List<ServerItem> servers;
  final String? activeServerId;
  final bool isLoading;
  final String? error;

  const ServersState({
    this.servers = const [],
    this.activeServerId,
    this.isLoading = false,
    this.error,
  });

  ServerItem? get activeServer => servers.cast<ServerItem?>().firstWhere(
        (s) => s?.id == activeServerId,
    orElse: () => null,
  );

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
    return const ServersState(isLoading: true);
  }

  Future<void> _load() async {
    final storage = ref.read(storageProvider);
    final servers = await storage.getServers();
    final activeId = storage.getActiveServerId();
    state = ServersState(servers: servers, activeServerId: activeId);
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
    var config = rawConfig.trim();
    final validationError = _validateManualConfig(config);
    if (validationError != null) throw Exception(validationError);
    if (state.servers.any((s) => s.config == config)) {
      throw Exception('This server is already added');
    }
    final server = ServerItem.fromRaw(config);
    await ref.read(storageProvider).upsertServer(server);
    state = state.copyWith(servers: [...state.servers, server]);
  }

  String? _validateManualConfig(String rawConfig) {
    if (rawConfig.isEmpty) return 'Configuration is empty';
    final lower = rawConfig.toLowerCase();
    if (!(lower.startsWith('vless://') ||
        lower.startsWith('vmess://') ||
        lower.startsWith('trojan://') ||
        lower.startsWith('ss://') ||
        lower.startsWith('ssr://') ||
        lower.startsWith('hysteria://') ||
        lower.startsWith('hysteria2://') ||
        lower.startsWith('hy2://'))) {
      return 'Unsupported format. Use vless://, vmess://, trojan://, ss://, ssr://, hysteria://, hysteria2:// or hy2://';
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

  Future<void> toggleFavorite(String id) async {
    final idx = state.servers.indexWhere((s) => s.id == id);
    if (idx == -1) return;
    final updated = state.servers[idx].copyWith(
      isFavorite: !state.servers[idx].isFavorite,
    );
    final newList = [...state.servers]..[idx] = updated;
    await ref.read(storageProvider).saveServers(newList);
    state = state.copyWith(servers: newList);
  }

  Future<void> updatePing(String serverId, int? pingMs) async {
    await updatePingResults({
      serverId: (pingMs: pingMs, lastPingType: null),
    });
  }

  /// батч-обновление ping + типа теста: один write в storage и один rebuild
  Future<void> updatePingResults(
    Map<String, ({int? pingMs, String? lastPingType})> updates,
  ) async {
    if (updates.isEmpty) return;
    final now = DateTime.now();
    final newList = state.servers
        .map((s) {
          final update = updates[s.id];
          if (update == null) return s;
          var item = s.copyWith(
            pingMs: update.pingMs,
            lastTestedAt: now,
          );
          if (update.lastPingType != null) {
            item = item.copyWith(lastPingType: update.lastPingType);
          }
          return item;
        })
        .toList();
    await ref.read(storageProvider).updatePingResults(updates);
    state = state.copyWith(servers: newList);
  }

  /// deprecated: используй updatePingResults когда известен тип пинга
  Future<void> updatePings(Map<String, int?> pings) async {
    await updatePingResults({
      for (final e in pings.entries) e.key: (pingMs: e.value, lastPingType: null),
    });
  }

  void _applyPingResultToState(PingResult result) {
    final pingMs = result.success ? result.latencyMs : null;
    final idx = state.servers.indexWhere((s) => s.id == result.serverId);
    if (idx == -1) return;
    final newList = [...state.servers];
    newList[idx] = newList[idx].copyWith(
      pingMs: pingMs,
      lastTestedAt: DateTime.now(),
      lastPingType: PingService.pingTypeToStored(result.pingType),
    );
    state = state.copyWith(servers: newList);
  }

  /// пингует серверы: UI обновляем по мере результатов, в storage пишем разом в конце
  Future<List<PingResult>> _pingServersWithBatchedUpdates(
    List<ServerItem> servers,
  ) async {
    final results = <PingResult>[];
    final pending = <String, ({int? pingMs, String? lastPingType})>{};
    final settings = await ref.read(storageProvider).getSettings();
    final vpnState = ref.read(vpnStateProvider).valueOrNull;
    final vpnConnected = vpnState?.status == VpnStatus.connected;
    final tunMode = vpnState?.activeMode == ConnectionMode.tun;
    // Raw TCP ping is unmeasurable through a TUN tunnel — switch to URL ping.
    final pingType = PingService.pingTypeForConnectionState(
      PingService.pingTypeFromSettings(settings),
      vpnConnected: vpnConnected,
      tunMode: tunMode,
    );
    final testUrl = PingTestConfig.resolveTestUrl(settings);

    Future<String?> resolveServerIp(ServerItem server) async {
      try {
        final addresses = await InternetAddress.lookup(server.address)
            .timeout(const Duration(seconds: 5));
        if (addresses.isNotEmpty) return addresses.first.address;
      } catch (_) {}
      return null;
    }

    final anySpeed = servers.any(
      (s) => PingService.effectivePingType(s, pingType) == PingType.speed,
    );
    final anyUrl = servers.any(
      (s) => PingService.effectivePingType(s, pingType) == PingType.url,
    );

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
        _applyPingResultToState(result);
      },
    );

    if (pending.isNotEmpty) {
      await ref.read(storageProvider).updatePingResults(pending);
    }
    return results;
  }

  Future<void> pingAll() async {
    await _pingServersWithBatchedUpdates(state.servers);
  }

  /// пингует серверы одной подписки (или manual-серверы при subscriptionId == null)
  Future<void> pingSubscription(String? subscriptionId) async {
    final scopeKey = subscriptionId ?? '__manual__';
    ref.read(pingingScopesProvider.notifier).update((set) => {...set, scopeKey});
    final servers = subscriptionId == null
        ? state.servers.where((s) => s.subscriptionId == null).toList()
        : state.servers.where((s) => s.subscriptionId == subscriptionId).toList();
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
      final vpnState = ref.read(vpnStateProvider).valueOrNull;
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
        try {
          final addresses = await InternetAddress.lookup(server.address)
              .timeout(const Duration(seconds: 5));
          if (addresses.isNotEmpty) serverIp = addresses.first.address;
        } catch (_) {}
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

class VpnStateNotifier extends AsyncNotifier<VpnState> {
  StreamSubscription<VpnState>? _sub;
  bool _connectInFlight = false;
  bool _serverSwitchInProgress = false;

  @override
  Future<VpnState> build() async {
    final engine = ref.read(vpnEngineProvider);
    _sub?.cancel();
    _sub = engine.stateStream.listen((s) {
      if (_serverSwitchInProgress && s.status == VpnStatus.error) {
        return;
      }
      // пока идёт connect() держим UI на "connecting" до его завершения
      if (_connectInFlight) {
        if (s.status == VpnStatus.error || s.status == VpnStatus.connected) {
          state = AsyncData(s);
        }
        return;
      }
      final current = state.valueOrNull;
      if (current != null && current.telemetryEquals(s)) return;
      state = AsyncData(s);
    });
    ref.onDispose(() => _sub?.cancel());
    try {
      return await engine.getCurrentState();
    } catch (_) {
      return VpnState.disconnected;
    }
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
    state = const AsyncData(VpnState(status: VpnStatus.connecting));

    try {
      final engine = ref.read(vpnEngineProvider);
      final settings = await ref.read(storageProvider).getSettings();
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
      if (Platform.isWindows && connectionMode == ConnectionMode.tun) {
        final elevated = await engine.requestVpnPermission();
        if (!elevated) {
          if (autostartTunFallback) {
            connectionMode = ConnectionMode.proxy;
            AppLogger.instance.warn(
              'Autostart: TUN requires admin rights, falling back to Proxy',
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
      String serverIp = server.address;
      try {
        final addresses = await InternetAddress.lookup(server.address)
            .timeout(const Duration(seconds: 5));
        if (addresses.isNotEmpty) serverIp = addresses.first.address;
      } catch (_) {
        // не вышло — оставляем адрес как есть
      }

      final windowsProxyNoAuth = Platform.isWindows &&
          connectionMode == ConnectionMode.proxy;

      // 3. генерим Xray-конфиг с уже резолвнутым IP
      final xrayConfig = ConfigGeneratorV2.generateConfig(
        server.config,
        settings,
        resolvedServerIp: serverIp,
        localInboundsNoAuth: windowsProxyNoAuth,
      );

      // 4. запуск: Android TUN (Xray+tun2socks) / Windows proxy (Xray) или TUN (Xray→sing-box)
      final session = TunnelSessionBuilder.build(
        settings: settings,
        xrayConfig: xrayConfig,
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

      final sessionState = await engine.getCurrentState();
      if (sessionState.status == VpnStatus.connected) {
        state = AsyncData(sessionState);
      } else if (sessionState.status != VpnStatus.error) {
        state = AsyncData(VpnState(
          status: VpnStatus.connected,
          activeMode: sessionState.activeMode,
        ));
      }
    } catch (e, st) {
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

    final status = state.valueOrNull?.status;
    if (status != VpnStatus.connected && status != VpnStatus.connecting) {
      await connect();
      return;
    }

    _serverSwitchInProgress = true;
    ref.read(vpnServerSwitchInProgressProvider.notifier).state = true;
    try {
      state = const AsyncData(VpnState(status: VpnStatus.disconnecting));
      await ref.read(vpnEngineProvider).stopVpn();
      await _waitForDisconnected();
      await connect();
    } finally {
      _serverSwitchInProgress = false;
      ref.read(vpnServerSwitchInProgressProvider.notifier).state = false;
    }
  }

  Future<void> _waitForDisconnected() async {
    const timeout = Duration(seconds: 4);
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final status = state.valueOrNull?.status;
      if (status == VpnStatus.disconnected || status == null) {
        await Future.delayed(const Duration(milliseconds: 350));
        return;
      }
      await Future.delayed(const Duration(milliseconds: 80));
    }
    await Future.delayed(const Duration(milliseconds: 350));
  }

  Future<void> toggle() async {
    final status = state.valueOrNull?.status ?? VpnStatus.disconnected;
    if (status == VpnStatus.connected || status == VpnStatus.connecting) {
      await disconnect();
    } else {
      await connect();
    }
  }
}

/// true пока переподключаемся при смене сервера — чтобы не показывать ложные ошибки
final vpnServerSwitchInProgressProvider = StateProvider<bool>((ref) => false);

final vpnStateProvider =
    AsyncNotifierProvider<VpnStateNotifier, VpnState>(VpnStateNotifier.new);

class RoutingRulesNotifier extends AsyncNotifier<List<RoutingRule>> {
  @override
  Future<List<RoutingRule>> build() async {
    return ref.read(storageProvider).getRules();
  }

  Future<void> add(RoutingRule rule) async {
    final rules = [...?state.valueOrNull, rule];
    await ref.read(storageProvider).saveRules(rules);
    state = AsyncData(rules);
  }

  Future<void> updateRule(RoutingRule rule) async {
    final rules = (state.valueOrNull ?? [])
        .map((r) => r.id == rule.id ? rule : r)
        .toList();
    await ref.read(storageProvider).saveRules(rules);
    state = AsyncData(rules);
  }

  Future<void> remove(String id) async {
    final rules = (state.valueOrNull ?? []).where((r) => r.id != id).toList();
    await ref.read(storageProvider).saveRules(rules);
    state = AsyncData(rules);
  }

  Future<void> toggle(String id) async {
    final rules = (state.valueOrNull ?? [])
        .map((r) => r.id == id ? r.copyWith(enabled: !r.enabled) : r)
        .toList();
    await ref.read(storageProvider).saveRules(rules);
    state = AsyncData(rules);
  }

  Future<void> resetToDefaults() async {
    final rules = RoutingRule.defaults;
    await ref.read(storageProvider).saveRules(rules);
    state = AsyncData(rules);
  }
}

final routingRulesProvider =
AsyncNotifierProvider<RoutingRulesNotifier, List<RoutingRule>>(
  RoutingRulesNotifier.new,
);

class SplitTunnelingState {
  final Set<String> excludePackages;
  final Set<String> includePackages;

  const SplitTunnelingState({
    this.excludePackages = const {},
    this.includePackages = const {},
  });

  SplitTunnelingState copyWith({
    Set<String>? excludePackages,
    Set<String>? includePackages,
  }) =>
      SplitTunnelingState(
        excludePackages: excludePackages ?? this.excludePackages,
        includePackages: includePackages ?? this.includePackages,
      );
}

class SplitTunnelingNotifier extends Notifier<SplitTunnelingState> {
  @override
  SplitTunnelingState build() {
    final storage = ref.read(storageProvider);
    return SplitTunnelingState(
      excludePackages: storage.getExcludePackages().toSet(),
      includePackages: storage.getIncludePackages().toSet(),
    );
  }

  Future<void> toggleExclude(String pkg) async {
    final set = {...state.excludePackages};
    if (!set.add(pkg)) set.remove(pkg);
    await ref.read(storageProvider).setExcludePackages(set.toList());
    await ref.read(storageProvider).setIncludePackages([]);
    state = state.copyWith(excludePackages: set, includePackages: const {});
  }

  Future<void> toggleInclude(String pkg) async {
    final set = {...state.includePackages};
    if (!set.add(pkg)) set.remove(pkg);
    await ref.read(storageProvider).setIncludePackages(set.toList());
    await ref.read(storageProvider).setExcludePackages([]);
    state = state.copyWith(includePackages: set, excludePackages: const {});
  }

  /// добавляет пачку пакетов в excludePackages одним обновлением state
  /// (вместо цикла toggleExclude, иначе ловим race condition)
  Future<void> addAllExcludes(List<String> packages) async {
    final set = {...state.excludePackages, ...packages};
    await ref.read(storageProvider).setExcludePackages(set.toList());
    await ref.read(storageProvider).setIncludePackages([]);
    state = state.copyWith(excludePackages: set, includePackages: const {});
  }

  Future<void> clearExcludes() async {
    await ref.read(storageProvider).setExcludePackages([]);
    state = state.copyWith(excludePackages: const {});
  }

  Future<void> clearIncludes() async {
    await ref.read(storageProvider).setIncludePackages([]);
    state = state.copyWith(includePackages: const {});
  }

  Future<void> clearAll() async {
    await ref.read(storageProvider).setExcludePackages([]);
    await ref.read(storageProvider).setIncludePackages([]);
    state = const SplitTunnelingState();
  }

  /// ручное добавление exe/пути (Windows и произвольные записи)
  Future<void> addCustomProcess(String raw, {required bool asInclude}) async {
    final name = normalizeProcessName(raw);
    if (name.isEmpty) return;
    if (asInclude) {
      await toggleInclude(name);
    } else {
      await toggleExclude(name);
    }
  }
}

final splitTunnelingProvider =
NotifierProvider<SplitTunnelingNotifier, SplitTunnelingState>(
  SplitTunnelingNotifier.new,
);

final installedAppsProvider = FutureProvider.family<List<AppInfo>, bool>(
      (ref, includeSystem) async {
    ref.keepAlive();
    final engine = ref.read(vpnEngineProvider);
    final rawList = await engine.getInstalledApps(includeSystem: includeSystem);
    return rawList.map(AppInfo.fromJson).toList()
      ..sort((a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));
  },
);

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    return ref.read(storageProvider).getSettings();
  }

  Future<void> save(AppSettings settings) async {
    await ref.read(storageProvider).saveSettings(settings);
    state = AsyncData(settings);
  }

  Future<void> reset() async {
    await save(const AppSettings());
  }
}

final settingsNotifierProvider =
AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);