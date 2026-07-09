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
import '../tunnel/vpn_backend.dart';
import '../utils/awg_profile.dart';
import '../utils/config_gen.dart';
import '../utils/error_messages.dart';
import '../utils/local_vpn_proxy.dart';
import '../utils/process_name_utils.dart';
import '../utils/socks5_credentials.dart';
import '../utils/split_tunnel_routing.dart';
import '../utils/subscription_diff.dart';
import '../utils/subscription_url.dart';
import 'ui_state_providers.dart';

export 'ui_state_providers.dart';

/// Резолвит первый IP-адрес хоста (таймаут 5с), либо null если не вышло.
/// direct-правило роутинга и URL/speed-пинг хотят идти по IP, а не по домену,
/// когда DNS сам уходит через прокси.
Future<String?> _resolveFirstAddress(String host) async {
  try {
    final addresses =
        await InternetAddress.lookup(host).timeout(const Duration(seconds: 5));
    if (addresses.isNotEmpty) return addresses.first.address;
  } catch (_) {}
  return null;
}

final storageProvider = Provider<StorageService>((ref) {
  throw UnimplementedError('Override storageProvider before runApp');
});

/// Режим сортировки серверов внутри группы (ключ = id подписки / '__manual__',
/// значение = ServerSortMode.name). Персистится, чтобы выбор переживал
/// перезапуск приложения (в отличие от сворачивания групп).
class ServerSortModesNotifier extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() =>
      ref.read(storageProvider).getServerSortModes();

  void update(Map<String, String> Function(Map<String, String> state) fn) {
    state = fn(state);
    unawaited(ref.read(storageProvider).setServerSortModes(state));
  }
}

final serverSortModesProvider =
    NotifierProvider<ServerSortModesNotifier, Map<String, String>>(
  ServerSortModesNotifier.new,
);

final subscriptionServiceProvider = Provider<SubscriptionService>((ref) {
  return SubscriptionService(ref.read(storageProvider));
});

final vpnEngineProvider = Provider<VpnEngine>((ref) {
  final engine = VpnEngine();
  engine.init();
  // Окно скрыто/свёрнуто (десктоп неделями живёт в трее) — секундный опрос
  // счётчиков трафика никому не виден, глушим его, чтобы не жечь CPU в фоне.
  // Два входа: (1) Flutter-lifecycle (`hidden`/`paused` — реальное сворачивание/
  // фон), (2) нативный трей на Windows через desktopWindowVisibleProvider — трей
  // SW_HIDE движок отдаёт лишь как `inactive`, поэтому lifecycle его не ловит.
  // Опрашиваем, только когда окно и на переднем плане, и реально видимо.
  // `inactive` на десктопе = окно видимо, но без фокуса — опрос продолжается.
  // Статус-события (ошибка, disconnect от вотчдога) идут независимо от этого.
  var lifecycleForeground = true;
  var uiVisible = true;
  void applyPolling() =>
      engine.setTrafficStatsPollingEnabled(lifecycleForeground && uiVisible);
  final lifecycle = AppLifecycleListener(
    onStateChange: (state) {
      final hidden = state == AppLifecycleState.hidden ||
          state == AppLifecycleState.paused ||
          state == AppLifecycleState.detached;
      lifecycleForeground = !hidden;
      applyPolling();
    },
  );
  ref.listen<bool>(desktopUiVisibleProvider, (_, next) {
    uiVisible = next;
    applyPolling();
  });
  ref.onDispose(lifecycle.dispose);
  ref.onDispose(engine.dispose);
  return engine;
});

/// Пока приложение запущено, обновления перепроверяются сами с этим
/// интервалом — раньше чек жил от запуска до запуска, и на долгоживущем
/// десктопе (окно в трее неделями) новый релиз было видно только вручную.
const _updateRecheckInterval = Duration(hours: 6);

// ВАЖНО: подписываемся ТОЛЬКО на факт «подключён ли VPN» через select, а не на
// весь VpnState. Раньше тут был `ref.watch(vpnStateProvider).value`, из-за чего
// провайдер перезапускался на КАЖДЫЙ эмит состояния — телеметрия (скорость/время)
// обновляется раз в секунду — и checkForUpdate долбил GitHub примерно раз в 3 c,
// исчерпывая анонимный лимит в 60 запросов/час (после чего обновление вообще не
// скачать). select даёт ре-ран только при реальной смене connected↔disconnected.
// От спама сетью при частых ре-ранах защищает in-memory троттлинг в
// UpdateService (не чаще раза в 30 минут).
final updateInfoProvider = FutureProvider<UpdateInfo?>((ref) async {
  // периодический ре-чек; таймер перевзводится на каждый ре-ран провайдера
  final timer = Timer(_updateRecheckInterval, ref.invalidateSelf);
  ref.onDispose(timer.cancel);

  // после заморозки процесса (Android в фоне) таймеры не тикают — на resume
  // проверяем давность последнего чека
  final lifecycle = AppLifecycleListener(
    onResume: () {
      final last = UpdateService.lastAutoCheckAt;
      if (last == null ||
          DateTime.now().difference(last) >= _updateRecheckInterval) {
        ref.invalidateSelf();
      }
    },
  );
  ref.onDispose(lifecycle.dispose);

  final vpnConnected = ref.watch(
    vpnStateProvider.select((s) => s.value?.status == VpnStatus.connected),
  );
  // Android+AWG — единственный случай без локального HTTP-прокси (Dio тогда
  // идёт напрямую, но пакет приложения включён в TUN и трафик всё равно в
  // туннеле). select — чтобы ре-ран был только при смене awg↔xray.
  final awgActive = ref.watch(
    serversProvider.select((s) {
      final srv = s.activeServer;
      return srv != null && AwgProfile.isAwgConfig(srv.config);
    }),
  );
  final settings = await ref.read(storageProvider).getSettings();
  return UpdateService.checkForUpdate(
    force: false,
    viaLocalProxy: tunnelHasLocalHttpProxy(
      vpnConnected: vpnConnected,
      awgBackend: awgActive,
    ),
    httpPort: settings.httpPort,
  );
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
      // Окно скрыто (десктоп в трее) — перечитывать storage с диска незачем:
      // UI не виден, а onResume выше и так делает полный синк при возврате.
      final ls = WidgetsBinding.instance.lifecycleState;
      if (ls == AppLifecycleState.hidden ||
          ls == AppLifecycleState.paused ||
          ls == AppLifecycleState.detached) {
        return;
      }
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
    final current = state.value;
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

      // батчами по 3 (как updateAll): залп по всем due-подпискам разом
      // упирается в сеть и rate-limit панелей
      final results = <UpdateResult>[];
      for (var i = 0; i < due.length; i += 3) {
        final batch = due.skip(i).take(3).toList();
        results.addAll(await Future.wait(
          batch.map(service.updateSubscription),
          eagerError: false,
        ));
      }
      final hasSuccess = results.any((r) => r.success);
      if (!hasSuccess) return;

      final latest = await ref.read(storageProvider).getSubscriptions();
      state = AsyncData(latest);
      await ref.read(serversProvider.notifier).reloadPreservingActive();
    } finally {
      _autoUpdateRunning = false;
    }
  }

  bool _hasSubscriptionsChanged(List<Subscription> a, List<Subscription> b) =>
      subscriptionsDiffer(a, b);

  Future<void> add(Subscription sub) async {
    final existing = state.value ?? await ref.read(storageProvider).getSubscriptions();
    final newUrl = _normalizeSubscriptionUrl(sub.url);
    final duplicate = existing.any(
      (s) => _normalizeSubscriptionUrl(s.url) == newUrl,
    );
    if (duplicate) {
      throw Exception('Subscription with this URL is already added');
    }

    await ref.read(storageProvider).upsertSubscription(sub);
    state = AsyncData([...?state.value, sub]);
    try {
      await refresh(sub);
    } catch (e) {
      // первое обновление упало — откатываем add, чтобы не висели пустые подписки
      await ref.read(storageProvider).deleteSubscription(sub.id);
      state = AsyncData(
        (state.value ?? []).where((s) => s.id != sub.id).toList(),
      );
      await ref.read(serversProvider.notifier).reloadPreservingActive();
      rethrow;
    }
  }

  static String _normalizeSubscriptionUrl(String url) =>
      normalizeSubscriptionUrl(url);

  Future<void> remove(String id) async {
    await ref.read(storageProvider).deleteSubscription(id);
    state = AsyncData(
      (state.value ?? []).where((s) => s.id != id).toList(),
    );
    await ref.read(serversProvider.notifier).reloadPreservingActive();
  }

  Future<void> refresh(Subscription sub) async {
    final result = await ref.read(subscriptionServiceProvider).updateSubscription(sub);

    if (result.success) {
      final subs = (state.value ?? [])
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

  static String _shortError(Object e) {
    return explainError(e).short;
  }

  Future<void> updateInterval(String id, int hours) async {
    final subs = state.value ?? [];
    final idx = subs.indexWhere((s) => s.id == id);
    if (idx == -1) return;
    final updated = subs[idx].copyWith(updateIntervalHours: hours);
    await ref.read(storageProvider).upsertSubscription(updated);
    final newList = [...subs]..[idx] = updated;
    state = AsyncData(newList);
  }

  Future<void> toggleAutoUpdate(String id) async {
    final subs = state.value ?? [];
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
    final subs = <Subscription>[...(state.value ?? [])];
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
    final subs = state.value ?? [];
    final idx = subs.indexWhere((s) => s.id == id);
    if (idx == -1) return;
    var urlChanged = false;
    if (url != null) {
      final newUrl = _normalizeSubscriptionUrl(url);
      final duplicate = subs.any(
        (s) => s.id != id && _normalizeSubscriptionUrl(s.url) == newUrl,
      );
      if (duplicate) {
        throw Exception('Subscription with this URL is already added');
      }
      urlChanged = newUrl != _normalizeSubscriptionUrl(subs[idx].url);
    }
    final updated = subs[idx].copyWith(
      name: name ?? subs[idx].name,
      url: url ?? subs[idx].url,
    );
    await ref.read(storageProvider).upsertSubscription(updated);
    final newList = [...subs]..[idx] = updated;
    state = AsyncData(newList);

    // Сменили ссылку → перетягиваем серверы с нового URL. Иначе подписка
    // молча оставалась со старыми серверами. Делаем в фоне (как ручной
    // refresh): на карточке крутится спиннер, ошибка нового URL ложится в
    // subscriptionRefreshErrorsProvider, а не роняет диалог редактирования.
    if (urlChanged) {
      unawaited(refreshTracked(updated).catchError((_) {}));
    }
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

  /// Индекс серверов по id — считается один раз на состояние. Раньше каждый
  /// `_ServerTile` линейно искал себя в `servers` (O(N) на тайл → O(N²) на
  /// список), что заметно тормозило построение/обновление длинных списков.
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
    final config = rawConfig.trim();
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

    if (AwgProfile.isAwgConfig(rawConfig)) {
      try {
        AwgProfile.parse(rawConfig);
      } catch (e) {
        return 'Invalid AmneziaWG config: $e';
      }
      return null;
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
    final vpnState = ref.read(vpnStateProvider).value;
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
    }

    if (pending.isNotEmpty) {
      // Мержим результаты в актуальный список из storage: снапшот провайдера
      // мог устареть, если за время пинга обновилась подписка — прежний
      // saveServers(state.servers) откатывал её серверы к старым.
      final merged = await ref
          .read(storageProvider)
          .applyPingUpdates(pending, DateTime.now());
      state = state.copyWith(servers: merged);
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
      final vpnState = ref.read(vpnStateProvider).value;
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

class VpnStateNotifier extends AsyncNotifier<VpnState> {
  StreamSubscription<VpnState>? _sub;
  bool _connectInFlight = false;
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
    if (_serverSwitchInProgress && s.status == VpnStatus.error) return;
    if (_connectInFlight) {
      if (s.status == VpnStatus.error ||
          s.status == VpnStatus.connected ||
          s.status == VpnStatus.disconnected) {
        state = AsyncData(s);
        if (s.status == VpnStatus.connected ||
            s.status == VpnStatus.disconnected) {
          _connectInFlight = false;
        }
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

      final vpnBackend = isAwg ? VpnBackend.awg : VpnBackend.xray;

      // AmneziaWG поднимается из сырого .conf своим ядром — xray-конфиг не нужен.
      final xrayConfig = isAwg
          ? ''
          : ConfigGeneratorV2.generateConfig(
              server.config,
              settings,
              resolvedServerIp: serverIp,
              localInboundsNoAuth: desktopProxyNoAuth,
            );

      final session = TunnelSessionBuilder.build(
        settings: settings,
        xrayConfig: xrayConfig,
        vpnBackend: vpnBackend,
        awgConfig: isAwg ? server.config : null,
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
        // движок не прислал disconnected за таймаут — продолжаем как раньше
      } finally {
        if (identical(_disconnectWaiter, waiter)) _disconnectWaiter = null;
      }
    }
    // даём ядру/туннелю осесть перед повторным connect (как было)
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

class RoutingRulesNotifier extends AsyncNotifier<List<RoutingRule>> {
  @override
  Future<List<RoutingRule>> build() async {
    return ref.read(storageProvider).getRules();
  }

  Future<void> add(RoutingRule rule) async {
    final rules = [...?state.value, rule];
    await ref.read(storageProvider).saveRules(rules);
    state = AsyncData(rules);
  }

  Future<void> updateRule(RoutingRule rule) async {
    final rules = (state.value ?? [])
        .map((r) => r.id == rule.id ? rule : r)
        .toList();
    await ref.read(storageProvider).saveRules(rules);
    state = AsyncData(rules);
  }

  Future<void> remove(String id) async {
    final rules = (state.value ?? []).where((r) => r.id != id).toList();
    await ref.read(storageProvider).saveRules(rules);
    state = AsyncData(rules);
  }

  Future<void> toggle(String id) async {
    final rules = (state.value ?? [])
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
  /// (вместо цикла toggleExclude, иначе ловим race condition).
  /// Возвращает, сколько пакетов реально добавилось (без дублей); при пустом
  /// результате не трогает storage вообще (иначе зря стирали includePackages).
  Future<int> addAllExcludes(List<String> packages) async {
    if (packages.isEmpty) return 0;
    final set = {...state.excludePackages, ...packages};
    final added = set.length - state.excludePackages.length;
    if (added == 0) return 0;
    await ref.read(storageProvider).setExcludePackages(set.toList());
    await ref.read(storageProvider).setIncludePackages([]);
    state = state.copyWith(excludePackages: set, includePackages: const {});
    return added;
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

final installedAppsProvider =
    FutureProvider.autoDispose.family<List<AppInfo>, bool>(
      (ref, includeSystem) async {
    // Список тяжёлый: у каждого приложения base64-иконка, на телефоне это
    // мегабайты строк. Раньше keepAlive держал его в памяти до перезапуска
    // приложения. Теперь кэш живёт, пока экран открыт, плюс 3 минуты после
    // ухода последнего слушателя (быстрый повторный вход — без перезагрузки),
    // затем освобождается; следующее открытие экрана перезагрузит список.
    final link = ref.keepAlive();
    Timer? release;
    ref.onCancel(() {
      release?.cancel();
      release = Timer(const Duration(minutes: 3), link.close);
    });
    ref.onResume(() => release?.cancel());
    ref.onDispose(() => release?.cancel());
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