import 'dart:convert';

/// Расширенные настройки sing-box TUN-инбаунда. Только desktop
/// (Windows/Linux): на Android TUN держит VpnService + tun2socks,
/// sing-box-инбаунд там не используется.
class TunSettings {
  /// Сетевой стек: [stackSystem] | [stackGvisor] | [stackMixed].
  final String stack;
  final int mtu;
  /// [strictRouteAuto] | [strictRouteOn] | [strictRouteOff].
  /// Auto = on везде, кроме Windows: там strict_route ломает маршруты при
  /// активном другом VPN (например, Tailscale).
  final String strictRoute;
  /// Full-cone NAT для UDP. sing-box применяет только на gvisor/mixed стеке.
  final bool endpointIndependentNat;
  /// Таймаут NAT-записей UDP в секундах (дефолт sing-box — 5 минут).
  final int udpTimeoutSec;
  /// Автоматические маршруты в TUN. Выключать только при ручном управлении
  /// маршрутами: без auto_route трафик в туннель не попадает.
  final bool autoRoute;

  const TunSettings({
    this.stack = stackSystem,
    this.mtu = defaultMtu,
    this.strictRoute = strictRouteAuto,
    this.endpointIndependentNat = false,
    this.udpTimeoutSec = defaultUdpTimeoutSec,
    this.autoRoute = true,
  });

  static const stackSystem = 'system';
  static const stackGvisor = 'gvisor';
  static const stackMixed = 'mixed';
  static const stacks = [stackSystem, stackGvisor, stackMixed];

  static const strictRouteAuto = 'auto';
  static const strictRouteOn = 'on';
  static const strictRouteOff = 'off';
  static const strictRouteModes = [strictRouteAuto, strictRouteOn, strictRouteOff];

  static const defaultMtu = 1400;
  static const minMtu = 576;
  static const maxMtu = 65535;

  static const defaultUdpTimeoutSec = 300;
  static const minUdpTimeoutSec = 10;
  static const maxUdpTimeoutSec = 86400;

  bool get isDefault => this == const TunSettings();

  /// Итоговое значение strict_route для конфига.
  bool strictRouteEnabled({required bool windows}) => switch (strictRoute) {
        strictRouteOn => true,
        strictRouteOff => false,
        _ => !windows,
      };

  static String normalizeStack(String? raw) {
    final v = raw?.trim().toLowerCase();
    return stacks.contains(v) ? v! : stackSystem;
  }

  static String normalizeStrictRoute(String? raw) {
    final v = raw?.trim().toLowerCase();
    return strictRouteModes.contains(v) ? v! : strictRouteAuto;
  }

  static int clampMtu(int v) => v.clamp(minMtu, maxMtu);

  static int clampUdpTimeout(int v) =>
      v.clamp(minUdpTimeoutSec, maxUdpTimeoutSec);

  Map<String, dynamic> toJson() => {
        'stack': stack,
        'mtu': mtu,
        'strictRoute': strictRoute,
        'endpointIndependentNat': endpointIndependentNat,
        'udpTimeoutSec': udpTimeoutSec,
        'autoRoute': autoRoute,
      };

  factory TunSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const TunSettings();
    return TunSettings(
      stack: normalizeStack(json['stack'] as String?),
      mtu: clampMtu((json['mtu'] as num?)?.toInt() ?? defaultMtu),
      strictRoute: normalizeStrictRoute(json['strictRoute'] as String?),
      endpointIndependentNat: json['endpointIndependentNat'] as bool? ?? false,
      udpTimeoutSec: clampUdpTimeout(
        (json['udpTimeoutSec'] as num?)?.toInt() ?? defaultUdpTimeoutSec,
      ),
      autoRoute: json['autoRoute'] as bool? ?? true,
    );
  }

  TunSettings copyWith({
    String? stack,
    int? mtu,
    String? strictRoute,
    bool? endpointIndependentNat,
    int? udpTimeoutSec,
    bool? autoRoute,
  }) =>
      TunSettings(
        stack: stack ?? this.stack,
        mtu: mtu ?? this.mtu,
        strictRoute: strictRoute ?? this.strictRoute,
        endpointIndependentNat:
            endpointIndependentNat ?? this.endpointIndependentNat,
        udpTimeoutSec: udpTimeoutSec ?? this.udpTimeoutSec,
        autoRoute: autoRoute ?? this.autoRoute,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TunSettings &&
          runtimeType == other.runtimeType &&
          stack == other.stack &&
          mtu == other.mtu &&
          strictRoute == other.strictRoute &&
          endpointIndependentNat == other.endpointIndependentNat &&
          udpTimeoutSec == other.udpTimeoutSec &&
          autoRoute == other.autoRoute;

  @override
  int get hashCode => Object.hash(
        stack,
        mtu,
        strictRoute,
        endpointIndependentNat,
        udpTimeoutSec,
        autoRoute,
      );

  String toJsonString() => jsonEncode(toJson());

  factory TunSettings.fromJsonString(String s) =>
      TunSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
