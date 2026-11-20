part of 'providers.dart';

final ruleListServiceProvider = Provider<RuleListService>((ref) {
  final storage = ref.read(storageProvider);
  return RuleListService(
    localProxyPort: () => _activeLocalHttpProxyPort(ref, storage),
  );
});

// новая ссылка качается сразу при сохранении маршрута, дальше раз в сутки, уже через туннель;
// до ядра список доезжает на следующем подключении
class RuleListsNotifier extends Notifier<Map<String, RuleListStatus>> {
  final _lastAttempt = <String, DateTime>{};
  Timer? _syncDebounce;
  bool _pruned = false;
  bool _refreshing = false;
  bool _pending = false;
  bool _pendingRetryFailed = false;

  static const _retryAfter = Duration(minutes: 10);

  @override
  Map<String, RuleListStatus> build() {
    final lifecycle = AppLifecycleListener(
      onResume: () => unawaited(refreshStale()),
    );
    ref.onDispose(lifecycle.dispose);
    ref.onDispose(() => _syncDebounce?.cancel());

    ref.listen<bool>(
      vpnStateProvider.select((a) => a.value?.status == VpnStatus.connected),
      (previous, connected) {
        if (connected && previous != true) {
          unawaited(refreshStale(retryFailed: true));
        }
      },
    );

    // поле сохраняется на паузе в наборе, без ожидания ушла бы недопечатанная ссылка
    ref.listen<String?>(_routeListUrlsProvider, (_, urls) {
      _syncDebounce?.cancel();
      if (urls == null) return;
      if (urls.isEmpty) {
        unawaited(_sync());
        return;
      }
      _syncDebounce = Timer(const Duration(milliseconds: 1500), () {
        unawaited(_sync());
      });
    }, fireImmediately: true);
    return const {};
  }

  Future<void> _sync() async {
    final routes = await ref.read(routesProvider.future);
    final profiles = await ref.read(routingProfilesProvider.future);
    if (!ref.mounted) return;
    final urls = routeListUrls(_allRoutes(routes, profiles));
    final service = ref.read(ruleListServiceProvider);
    final next = <String, RuleListStatus>{};
    for (final url in urls) {
      next[url] = state[url] ?? await service.status(url);
    }
    if (!ref.mounted) return;
    state = next;
    if (!_pruned) {
      _pruned = true;
      await service.prune(urls.toSet());
    }
    await refreshStale();
  }

  Future<void> refreshStale({bool retryFailed = false}) async {
    _pendingRetryFailed = _pendingRetryFailed || retryFailed;
    if (_refreshing) {
      _pending = true;
      return;
    }
    _refreshing = true;
    try {
      do {
        _pending = false;
        final retry = _pendingRetryFailed;
        _pendingRetryFailed = false;
        await _refreshPass(retryFailed: retry);
      } while (_pending && ref.mounted);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _refreshPass({required bool retryFailed}) async {
    for (final url in state.keys.toList()) {
      if (!ref.mounted) return;
      final current = state[url];
      if (current == null) continue;
      final now = DateTime.now();
      final updated = current.updatedAt;
      if (updated != null &&
          now.difference(updated) < RuleListService.staleAfter) {
        continue;
      }
      final last = _lastAttempt[url];
      if (!retryFailed && last != null && now.difference(last) < _retryAfter) {
        continue;
      }
      _lastAttempt[url] = now;
      state = {...state, url: current.copyWith(loading: true)};
      final result = await ref.read(ruleListServiceProvider).refresh(url);
      if (!ref.mounted) return;
      if (state.containsKey(url)) state = {...state, url: result};
    }
  }
}

final ruleListsProvider =
    NotifierProvider<RuleListsNotifier, Map<String, RuleListStatus>>(
      RuleListsNotifier.new,
    );

// списки профилей тоже: prune стёр бы скачанное для них при первой синхронизации
List<TrafficRoute> _allRoutes(
  List<TrafficRoute> main,
  List<RoutingProfile> profiles,
) => [...main, for (final p in profiles) ...p.routes];

final _routeListUrlsProvider = Provider<String?>((ref) {
  final main = ref.watch(routesProvider).value;
  final profiles = ref.watch(routingProfilesProvider).value;
  if (main == null || profiles == null) return null;
  return routeListUrls(_allRoutes(main, profiles)).join('\n');
});
