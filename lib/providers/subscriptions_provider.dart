part of 'providers.dart';

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

    final subs = await ref.read(storageProvider).getSubscriptions();
    // Проверяем сразу на старте: подписка могла истечь, пока приложение не
    // запускали, и тогда никакого обновления, которое бы это заметило, не будет.
    unawaited(notifyExpired(subs));
    return subs;
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
    await notifyExpired(latest);
  }

  /// Разовое уведомление по каждой истёкшей подписке.
  ///
  /// Панель после окончания срока обычно продолжает отдавать те же серверы (или
  /// просто перестаёт обновлять список) и НЕ сообщает клиенту, что подписка
  /// кончилась — обновление молча «ничего не меняет». Пользователь узнавал об
  /// этом только когда серверы отваливались, поэтому говорим сами: один раз на
  /// каждую дату окончания (продлили → expiresAt поменялся → скажем снова).
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

  /// Локализация вне дерева виджетов: уведомление уходит из провайдера, где
  /// BuildContext'а нет. Язык — из настроек, иначе системный, иначе английский.
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
      await notifyExpired(latest);
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
    // Своя картинка карточки — файл в каталоге приложения, и запись о подписке
    // его не уносит: без этого удалённые подписки копили бы картинки на диске
    // до переустановки. Ошибку глушим — подписку удаляем в любом случае.
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

  /// Ставит расписание автообновления одной записью.
  ///
  /// Раньше выбор интервала при выключенном автообновлении делался парой
  /// вызовов `toggleAutoUpdate` + `updateInterval`. Оба читают список из
  /// состояния, меняют элемент и пишут обратно; без ожидания между ними второй
  /// успевал прочитать список ДО записи первого и затирал включение — интервал
  /// вставал, а подписка оставалась выключенной. Одна операция такую гонку
  /// исключает по построению.
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
  /// [resetName] — поле имени очистили: это не «не менять», а «вернуть
  /// автоматическое». Отдельный флаг нужен потому, что `name: null` уже занято
  /// смыслом «не трогать» — без него очистка поля молча ничего не делала.
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
    // Сброшенное имя сразу занимает название провайдера, если оно известно;
    // иначе — хост, как при добавлении подписки.
    final autoName = current.providerTitle?.trim().isNotEmpty == true
        ? current.providerTitle!.trim()
        : (Uri.tryParse(effectiveUrl)?.host ?? current.name);
    final identityChanged =
        fetchIdentity != null && fetchIdentity != current.fetchIdentity;
    final updated = current.copyWith(
      name: resetName ? autoName : (name ?? current.name),
      url: url ?? current.url,
      // Имя, введённое руками, перестаёт быть автоматическим: с этого момента
      // название от провайдера его больше не перетирает. Очистка поля —
      // обратный переход.
      nameIsAuto: resetName ? true : (name != null ? false : null),
      fetchIdentity: fetchIdentity,
      cardThemeId: cardThemeId,
      cardThemeInServers: cardThemeInServers,
      hiddenCardElements: hiddenCardElements,
      cardVeil: cardVeil,
    );
    await ref.read(storageProvider).upsertSubscription(updated);
    final newList = [...subs]..[idx] = updated;
    state = AsyncData(newList);

    // Выбор своей картинки копирует файл сразу, а подтверждается только здесь:
    // до сохранения на диске лежат обе — старая и новая. Сохранились — лишняя
    // больше не нужна.
    unawaited(
      CardImageService.prune(id, updated.cardThemeId).catchError((_) {}),
    );

    // Сменили ссылку или идентичность → перетягиваем серверы заново: с нового
    // URL, а под новой идентичностью панель и по старому может отдать другой
    // набор. Иначе подписка молча оставалась со старыми серверами. Делаем в
    // фоне (как ручной refresh): на карточке крутится спиннер, ошибка ложится
    // в subscriptionRefreshErrorsProvider, а не роняет шторку редактирования.
    if (urlChanged || identityChanged) {
      unawaited(refreshTracked(updated).catchError((_) {}));
    }
  }
}

final subscriptionsProvider =
AsyncNotifierProvider<SubscriptionsNotifier, List<Subscription>>(
  SubscriptionsNotifier.new,
);
