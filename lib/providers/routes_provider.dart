part of 'providers.dart';

// состояние меняется раньше записи на диск, как у настроек. порядок записей держит очередь StorageService
class RoutesNotifier extends AsyncNotifier<List<TrafficRoute>> {
  @override
  Future<List<TrafficRoute>> build() => ref.read(storageProvider).getRoutes();

  Future<void> _save(List<TrafficRoute> routes) async {
    state = AsyncData(routes);
    await ref.read(storageProvider).saveRoutes(routes);
  }

  Future<void> upsert(TrafficRoute route) async =>
      _save(withRoute(await future, route));

  Future<void> remove(String id) async => _save(withoutRoute(await future, id));

  Future<void> moveInAllApps(int from, int to) async =>
      _save(withAllAppsMoved(await future, from, to));

  Future<void> replaceAll(List<TrafficRoute> routes) => _save(routes);
}

final routesProvider =
    AsyncNotifierProvider<RoutesNotifier, List<TrafficRoute>>(
  RoutesNotifier.new,
);

class RoutingProfilesNotifier extends AsyncNotifier<List<RoutingProfile>> {
  @override
  Future<List<RoutingProfile>> build() =>
      ref.read(storageProvider).getRoutingProfiles();

  Future<void> _save(List<RoutingProfile> profiles) async {
    state = AsyncData(profiles);
    await ref.read(storageProvider).saveRoutingProfiles(profiles);
  }

  // правленый профиль провайдера становится своим, иначе следующее обновление подписки затёрло бы правку
  Future<void> _update(
    String id,
    RoutingProfile Function(RoutingProfile p) change,
  ) async =>
      _save([for (final p in await future) p.id == id ? change(p).asOwn() : p]);

  Future<void> add(RoutingProfile profile) async => _save(
        withSubscriptions(
          [...await future, profile],
          profile.id,
          profile.subscriptionIds,
        ),
      );

  // профиль из вставленной ссылки свой: правится сразу, подписки к нему человек привяжет сам
  Future<RoutingProfile> addFromRules(
    ProviderRoutingRules rules,
    String fallbackName,
  ) async {
    final profile = RoutingProfile.create(
      name: rules.name ?? fallbackName,
      finalOutbound: rules.finalOutbound,
      routes: rules.routes,
    );
    await add(profile);
    return profile;
  }

  Future<void> remove(String id) async =>
      _save([for (final p in await future) if (p.id != id) p]);

  Future<void> rename(String id, String name) =>
      _update(id, (p) => p.copyWith(name: name));

  Future<void> setEnabled(String id, bool enabled) =>
      _update(id, (p) => p.copyWith(enabled: enabled));

  Future<void> setSubscriptions(String id, List<String> subscriptionIds) async =>
      _save([
        for (final p in withSubscriptions(await future, id, subscriptionIds))
          p.id == id ? p.asOwn() : p,
      ]);

  Future<void> dropProviderProfileOf(String subscriptionId) async {
    final profiles = await future;
    final next = withoutProviderProfileOf(profiles, subscriptionId);
    if (next.length != profiles.length) await _save(next);
  }

  Future<void> setFinalOutbound(String id, String value) =>
      _update(id, (p) => p.copyWith(finalOutbound: value));

  Future<void> upsertRoute(String id, TrafficRoute route) =>
      _update(id, (p) => p.copyWith(routes: withRoute(p.routes, route)));

  Future<void> removeRoute(String id, String routeId) =>
      _update(id, (p) => p.copyWith(routes: withoutRoute(p.routes, routeId)));

  Future<void> moveRouteInAllApps(String id, int from, int to) => _update(
        id,
        (p) => p.copyWith(routes: withAllAppsMoved(p.routes, from, to)),
      );
}

final routingProfilesProvider =
    AsyncNotifierProvider<RoutingProfilesNotifier, List<RoutingProfile>>(
  RoutingProfilesNotifier.new,
);

// чего ядро не умеет, того в шторках нет, а заведённый маршрут с этим показывает причину на карточке
class RouteCapabilities {
  const RouteCapabilities({
    this.apps = false,
    this.appsNeedTun = false,
    this.servers = false,
    this.core = VpnBackend.xray,
  });

  final bool apps;

  // сессия в режиме прокси: маршрут заработает в TUN, поэтому выбор приложений не прячем
  final bool appsNeedTun;

  final bool servers;

  final VpnBackend core;

  bool get appsOffered => apps || appsNeedTun;
}

final routeCapabilitiesProvider = Provider<RouteCapabilities>((ref) {
  final core = ref.watch(activeVpnBackendProvider);
  final mode = ref.watch(
    settingsNotifierProvider.select(
      (a) => TunnelSessionBuilder.resolveMode(a.value ?? const AppSettings()),
    ),
  );
  return RouteCapabilities(
    apps: appRoutesRun(mode),
    appsNeedTun: !appRoutesRun(mode),
    servers: true,
    core: core,
  );
});

class RoutesHintNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(storageProvider).routesHintPending;

  Future<void> dismiss() async {
    state = false;
    await ref.read(storageProvider).dismissRoutesHint();
  }
}

final routesHintProvider =
    NotifierProvider<RoutesHintNotifier, bool>(RoutesHintNotifier.new);
