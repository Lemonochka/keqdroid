part of 'providers.dart';

class SubscriptionsNotifier extends AsyncNotifier<List<Subscription>> {
  Timer? _syncTimer;
  bool _autoUpdateRunning = false;
  DateTime _lastAutoUpdateCheck = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Future<List<Subscription>> build() async {
    // WorkManager пишет в SharedPreferences из другого изолята, без reloadFromDisk кэш устаревший
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
      final ls = WidgetsBinding.instance.lifecycleState;
      if (ls == AppLifecycleState.hidden ||
          ls == AppLifecycleState.paused ||
          ls == AppLifecycleState.detached) {
        return;
      }
      await _syncSubscriptionsFromStorage();
    });
    ref.onDispose(() {
      _syncTimer?.cancel();
      _syncTimer = null;
    });

    final subs = await ref.read(storageProvider).getSubscriptions();
    unawaited(notifyExpired(subs));
    if (Platform.isAndroid) unawaited(Future(_migrateCardGifs));
    return subs;
  }

  // гифки шапок, выбранные до перехода на видео, перекодируются один раз в фоне
  Future<void> _migrateCardGifs() async {
    for (final sub in [...?state.value]) {
      if (!sub.cardThemeId.toLowerCase().endsWith('.gif')) continue;
      try {
        final id = await CardImageService.migrateGif(sub.cardThemeId, sub.id);
        if (id != null) await editMeta(sub.id, cardThemeId: id);
      } catch (_) {}
    }
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
      // обновил фоновый воркер: пингуем то, что он принёс
      final before = {for (final s in current) s.id: s.lastUpdatedAt};
      for (final s in latest) {
        if (s.lastUpdatedAt != null && s.lastUpdatedAt != before[s.id]) {
          _autoPing(s.id);
        }
      }
    }
    await notifyExpired(latest);
  }

  Future<void> notifyExpired(List<Subscription> subs) async {
    final expired = subs
        .where((s) => s.expiresAt != null && s.isExpired)
        .toList();
    if (expired.isEmpty) return;

    final storage = ref.read(storageProvider);
    final notified = storage.getExpiryNotified();
    final pending = expired
        .where((s) => notified[s.id] != s.expiresAt!.toIso8601String())
        .toList();
    if (pending.isEmpty) return;

    final l10n = await _resolveLocalizations();
    for (final sub in pending) {
      final expiredAt = sub.expiresAt!;
      await NotificationService.showSubscriptionExpired(
        subscriptionId: sub.id,
        title: l10n.subscriptionsExpiredNotifTitle,
        body: l10n.subscriptionsExpiredNotifBody(
          sub.name,
          '${expiredAt.day.toString().padLeft(2, '0')}.'
              '${expiredAt.month.toString().padLeft(2, '0')}.'
              '${expiredAt.year}',
        ),
      );
      notified[sub.id] = expiredAt.toIso8601String();
      AppLogger.instance.info(
        'Subscription "${sub.name}" expired at $expiredAt — user notified',
      );
    }
    await storage.setExpiryNotified(notified);
  }

  Future<AppLocalizations> _resolveLocalizations() async {
    final settings = await ref.read(storageProvider).getSettings();
    final candidates = <Locale>[
      if (localeFromSettings(settings) != null) localeFromSettings(settings)!,
      WidgetsBinding.instance.platformDispatcher.locale,
      const Locale('en'),
    ];
    for (final locale in candidates) {
      if (AppLocalizations.delegate.isSupported(locale)) {
        return AppLocalizations.delegate.load(locale);
      }
    }
    return AppLocalizations.delegate.load(const Locale('en'));
  }

  Future<void> _runInAppAutoUpdateTick({bool force = false}) async {
    if (ref.read(subscriptionReorderInProgressProvider)) return;
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
      for (final r in results) {
        if (r.success) _autoPing(r.subscription.id);
      }
      await notifyExpired(latest);
    } finally {
      _autoUpdateRunning = false;
    }
  }

  void _autoPing(String subscriptionId) => unawaited(
        ref.read(serversProvider.notifier).autoPingSubscription(subscriptionId),
      );

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
    unawaited(CardImageService.remove(id).catchError((_) {}));
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
      _autoPing(sub.id);
      await notifyExpired(subs);
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

  // одной записью: парой toggleAutoUpdate и updateInterval второй затирал первый
  Future<void> setUpdateSchedule(
    String id, {
    required bool autoUpdate,
    int? hours,
  }) async {
    final subs = state.value ?? [];
    final idx = subs.indexWhere((s) => s.id == id);
    if (idx == -1) return;
    final updated = subs[idx].copyWith(
      autoUpdate: autoUpdate,
      updateIntervalHours: hours,
    );
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

  Future<void> reorder(
      int oldIndex,
      int newIndex, {
        bool fromReorderableList = true,
      }) async {
    final subs = <Subscription>[...(state.value ?? [])];
    if (oldIndex < 0 || oldIndex >= subs.length) return;

    if (fromReorderableList && newIndex > oldIndex) newIndex -= 1;

    final item = subs.removeAt(oldIndex);
    final clampedNew = newIndex.clamp(0, subs.length);
    subs.insert(clampedNew, item);
    state = AsyncData(subs);

    await ref.read(storageProvider).saveSubscriptions(subs);
  }

  Future<void> handAutoSelectTo(String? ownerId) async {
    await AutoSelectHomeStore.save(null);
    final subs = state.value ?? [];
    bool owns(Subscription s) => s.id == ownerId && s.autoSelectVisible;
    final next = [
      for (final s in subs)
        s.autoSelect == owns(s) ? s : s.copyWith(autoSelect: owns(s)),
    ];
    state = AsyncData(next);
    final storage = ref.read(storageProvider);
    for (var i = 0; i < next.length; i++) {
      if (!identical(next[i], subs[i])) {
        await storage.upsertSubscription(next[i]);
      }
    }
  }

  Future<void> editMeta(
    String id, {
    String? name,
    String? url,
    bool resetName = false,
    SubscriptionFetchIdentity? fetchIdentity,
    String? cardThemeId,
    bool? cardThemeInServers,
    Set<SubscriptionCardElement>? hiddenCardElements,
    CardVeil? cardVeil,
    bool? autoSelectVisible,
    bool? autoSelect,
  }) async {
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
    final current = subs[idx];
    final effectiveUrl = url ?? current.url;
    final autoName = current.providerTitle?.trim().isNotEmpty == true
        ? current.providerTitle!.trim()
        : (Uri.tryParse(effectiveUrl)?.host ?? current.name);
    final identityChanged =
        fetchIdentity != null && fetchIdentity != current.fetchIdentity;
    final updated = current.copyWith(
      name: resetName ? autoName : (name ?? current.name),
      url: url ?? current.url,
      nameIsAuto: resetName ? true : (name != null ? false : null),
      fetchIdentity: fetchIdentity,
      cardThemeId: cardThemeId,
      cardThemeInServers: cardThemeInServers,
      hiddenCardElements: hiddenCardElements,
      cardVeil: cardVeil,
      autoSelectVisible: autoSelectVisible,
      autoSelect: autoSelectVisible == false ? false : autoSelect,
    );
    await ref.read(storageProvider).upsertSubscription(updated);
    final newList = [...subs]..[idx] = updated;
    state = AsyncData(newList);

    unawaited(
      CardImageService.prune(id, updated.cardThemeId).catchError((_) {}),
    );

    if (urlChanged || identityChanged) {
      unawaited(refreshTracked(updated).catchError((_) {}));
    }
  }
}

final subscriptionsProvider =
AsyncNotifierProvider<SubscriptionsNotifier, List<Subscription>>(
  SubscriptionsNotifier.new,
);
