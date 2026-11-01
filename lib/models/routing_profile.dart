import 'package:uuid/uuid.dart';

import 'app_settings.dart';
import 'traffic_route.dart';

// «Основной» профиль не здесь: это маршруты из keqdis_routes и finalOutbound настроек
class RoutingProfile {
  const RoutingProfile({
    required this.id,
    required this.name,
    this.enabled = true,
    this.subscriptionIds = const [],
    this.finalOutbound = AppSettings.finalOutboundProxy,
    this.routes = const [],
    this.providerSubscriptionId,
  });

  factory RoutingProfile.create({
    required String name,
    List<String> subscriptionIds = const [],
    String finalOutbound = AppSettings.finalOutboundProxy,
    List<TrafficRoute> routes = const [],
  }) =>
      RoutingProfile(
        id: const Uuid().v4(),
        name: name,
        subscriptionIds: subscriptionIds,
        finalOutbound: finalOutbound,
        routes: routes,
      );

  final String id;
  final String name;
  final bool enabled;
  final List<String> subscriptionIds;
  final String finalOutbound;
  final List<TrafficRoute> routes;

  // профиль принесла эта подписка: обновляется с ней и правится, только пока правила провайдера не слушаем
  final String? providerSubscriptionId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'enabled': enabled,
        'subscriptionIds': subscriptionIds,
        'finalOutbound': finalOutbound,
        'routes': [for (final r in routes) r.toJson()],
        if (providerSubscriptionId != null) 'providerSubscription': providerSubscriptionId,
      };

  factory RoutingProfile.fromJson(Map<String, dynamic> json) => RoutingProfile(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        enabled: json['enabled'] as bool? ?? true,
        subscriptionIds: [
          for (final s in (json['subscriptionIds'] as List? ?? const []))
            s.toString(),
        ],
        finalOutbound: json['finalOutbound'] as String? ??
            AppSettings.finalOutboundProxy,
        routes: [
          for (final r in (json['routes'] as List? ?? const []))
            TrafficRoute.fromJson(r as Map<String, dynamic>),
        ],
        providerSubscriptionId: json['providerSubscription'] as String?,
      );

  RoutingProfile copyWith({
    String? name,
    bool? enabled,
    List<String>? subscriptionIds,
    String? finalOutbound,
    List<TrafficRoute>? routes,
  }) =>
      RoutingProfile(
        id: id,
        name: name ?? this.name,
        enabled: enabled ?? this.enabled,
        subscriptionIds: subscriptionIds ?? this.subscriptionIds,
        finalOutbound: finalOutbound ?? this.finalOutbound,
        routes: routes ?? this.routes,
        providerSubscriptionId: providerSubscriptionId,
      );

  RoutingProfile asOwn() => RoutingProfile(
        id: id,
        name: name,
        enabled: enabled,
        subscriptionIds: subscriptionIds,
        finalOutbound: finalOutbound,
        routes: routes,
      );
}
