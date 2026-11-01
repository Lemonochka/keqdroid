import '../models/routing_profile.dart';
import '../models/server_item.dart';
import '../models/traffic_route.dart';
import 'provider_routing.dart';

// null значит «Основной»: свои серверы, подписки без профиля и выключенные профили
RoutingProfile? profileForServer(
  List<RoutingProfile> profiles,
  ServerItem server,
) =>
    profileForSubscription(profiles, server.subscriptionId);

RoutingProfile? profileForSubscription(
  List<RoutingProfile> profiles,
  String? subscriptionId,
) {
  if (subscriptionId == null) return null;
  for (final p in profiles) {
    if (p.enabled && p.subscriptionIds.contains(subscriptionId)) return p;
  }
  return null;
}

// у подписки один профиль: отмеченная в этом уходит из прежнего
List<RoutingProfile> withSubscriptions(
  List<RoutingProfile> profiles,
  String profileId,
  List<String> subscriptionIds,
) =>
    [
      for (final p in profiles)
        if (p.id == profileId)
          p.copyWith(subscriptionIds: subscriptionIds)
        else
          p.copyWith(subscriptionIds: [
            for (final s in p.subscriptionIds)
              if (!subscriptionIds.contains(s)) s,
          ]),
    ];

// свой профиль у подписки провайдеру не уступает: его профиль тогда не нужен и уходит
List<RoutingProfile> withProviderRouting(
  List<RoutingProfile> profiles, {
  required String subscriptionId,
  required String fallbackName,
  required ProviderRouting routing,
}) {
  final rest = withoutProviderProfileOf(profiles, subscriptionId);
  final hasOwn = rest.any((p) => p.subscriptionIds.contains(subscriptionId));
  if (hasOwn || routing is! ProviderRoutingRules) return rest;
  final profile = RoutingProfile(
    id: 'provider-$subscriptionId',
    name: routing.name ?? fallbackName,
    subscriptionIds: [subscriptionId],
    finalOutbound: routing.finalOutbound,
    routes: routing.routes,
    providerSubscriptionId: subscriptionId,
  );
  final at = profiles.indexWhere(
    (p) => p.providerSubscriptionId == subscriptionId,
  );
  if (at < 0) return [...rest, profile];
  return [
    for (var i = 0; i < profiles.length; i++)
      if (i == at)
        profile
      else if (profiles[i].providerSubscriptionId != subscriptionId)
        profiles[i],
  ];
}

List<RoutingProfile> withoutProviderProfileOf(
  List<RoutingProfile> profiles,
  String subscriptionId,
) =>
    [
      for (final p in profiles)
        if (p.providerSubscriptionId != subscriptionId) p,
    ];

List<TrafficRoute> withRoute(List<TrafficRoute> routes, TrafficRoute route) {
  final exists = routes.any((r) => r.id == route.id);
  return [
    if (exists)
      for (final r in routes) r.id == route.id ? route : r
    else ...[...routes, route],
  ];
}

List<TrafficRoute> withoutRoute(List<TrafficRoute> routes, String id) => [
      for (final r in routes)
        if (r.id != id) r,
    ];
