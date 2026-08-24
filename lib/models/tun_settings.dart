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

  /// Не выпускать IPv6 мимо туннеля.
  ///
  /// TUN-интерфейс с одним лишь IPv4-адресом IPv6-маршрутов не получает, и на
  /// двухстековой машине весь IPv6-трафик идёт мимо туннеля — то есть мимо
  /// правил роутинга и мимо прокси. Наш DNS отдаёт только A-записи, но браузеры
  /// ходят своим DoH и AAAA получают, поэтому «сайт открывается в обход VPN» и
  /// «мой IP не сменился» на дуалстеке — это оно.
  ///
  /// Включённая опция добавляет интерфейсу IPv6-адрес (ядро тогда забирает и
  /// IPv6-маршруты) и закрывает выход IPv6 наружу — приложения мгновенно
  /// откатываются на IPv4, который уже в туннеле. Адрес заводится ТОЛЬКО когда
  /// у машины есть настоящий глобальный IPv6: на машине с выключенным IPv6
  /// sing-box падает на настройке адаптера, и TUN не поднимается вовсе.
  final bool blockIpv6Leak;

  const TunSettings({
    this.stack = defaultStack,
    this.mtu = defaultMtu,
    this.strictRoute = strictRouteAuto,
    this.endpointIndependentNat = false,
    this.udpTimeoutSec = defaultUdpTimeoutSec,
    this.autoRoute = true,
    this.blockIpv6Leak = true,
  });

  static const stackSystem = 'system';
  static const stackGvisor = 'gvisor';
  static const stackMixed = 'mixed';
  static const stacks = [stackSystem, stackGvisor, stackMixed];

  /// Стек по умолчанию.
  ///
  /// `system` терминирует TCP не в процессе, а листенером на адресе самого
  /// TUN-интерфейса, и на Windows требует правила Windows Firewall — sing-tun
  /// заводит его сам (`fixWindowsFirewall`), но ошибку глотает. Не завелось —
  /// входящие к листенеру режет фаервол, TUN поднялся, ошибок нет, а трафика
  /// нет вовсе. Отсюда жалоба «на нормальных настройках туннель не работает,
  /// работает только на gvisor». gvisor держит TCP/IP целиком в процессе ядра,
  /// поэтому ни листенера, ни правил фаервола ему не нужно; своё умолчание
  /// (пустая строка) sing-box тоже разрешает в пользу gvisor-стека.
  static const defaultStack = stackGvisor;

  static const strictRouteAuto = 'auto';
  static const strictRouteOn = 'on';
  static const strictRouteOff = 'off';
  static const strictRouteModes = [strictRouteAuto, strictRouteOn, strictRouteOff];

  /// MTU по умолчанию — как у sing-box и у клиентов на нём (v2rayN, Nekoray,
  /// Hiddify). Прежние 1400 — величина из мира физических каналов: TUN здесь
  /// не гоняет байты по проводу, он отдаёт их ядру, и мелкий MTU лишь дробит
  /// один поток на лишние пакеты.
  static const defaultMtu = 9000;
  static const minMtu = 576;
  static const maxMtu = 65535;

  /// Прежняя пара умолчаний (до смены на gvisor/9000). Нужна миграции ниже.
  static const _legacyDefaultStack = stackSystem;
  static const _legacyDefaultMtu = 1400;

  /// Версия набора умолчаний, записанная в json. Отсутствует — настройки
  /// сохранены до миграции.
  static const _defaultsVersion = 2;

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
    return stacks.contains(v) ? v! : defaultStack;
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
        'blockIpv6Leak': blockIpv6Leak,
        'defaultsVersion': _defaultsVersion,
      };

  factory TunSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const TunSettings();
    var stack = normalizeStack(json['stack'] as String?);
    var mtu = clampMtu((json['mtu'] as num?)?.toInt() ?? defaultMtu);

    // Миграция прежних умолчаний. Настройки записываются целиком при любом
    // изменении в приложении, поэтому старая пара `system`/1400 лежит почти у
    // всех — и почти ни у кого не выбрана осознанно. Меняем ровно её и ровно
    // один раз: значения, отличные от прежних умолчаний, — это уже выбор
    // пользователя, и трогать его нельзя.
    final migrated = json['defaultsVersion'] == null;
    if (migrated && stack == _legacyDefaultStack && mtu == _legacyDefaultMtu) {
      stack = defaultStack;
      mtu = defaultMtu;
    }

    return TunSettings(
      stack: stack,
      mtu: mtu,
      strictRoute: normalizeStrictRoute(json['strictRoute'] as String?),
      endpointIndependentNat: json['endpointIndependentNat'] as bool? ?? false,
      udpTimeoutSec: clampUdpTimeout(
        (json['udpTimeoutSec'] as num?)?.toInt() ?? defaultUdpTimeoutSec,
      ),
      autoRoute: json['autoRoute'] as bool? ?? true,
      // Отсутствие ключа — настройки, сохранённые до появления опции. Дефолт
      // тот же, что у новых установок: утечка IPv6 мимо туннеля — это баг, а
      // не выбор пользователя.
      blockIpv6Leak: json['blockIpv6Leak'] as bool? ?? true,
    );
  }

  TunSettings copyWith({
    String? stack,
    int? mtu,
    String? strictRoute,
    bool? endpointIndependentNat,
    int? udpTimeoutSec,
    bool? autoRoute,
    bool? blockIpv6Leak,
  }) =>
      TunSettings(
        stack: stack ?? this.stack,
        mtu: mtu ?? this.mtu,
        strictRoute: strictRoute ?? this.strictRoute,
        endpointIndependentNat:
            endpointIndependentNat ?? this.endpointIndependentNat,
        udpTimeoutSec: udpTimeoutSec ?? this.udpTimeoutSec,
        autoRoute: autoRoute ?? this.autoRoute,
        blockIpv6Leak: blockIpv6Leak ?? this.blockIpv6Leak,
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
          autoRoute == other.autoRoute &&
          blockIpv6Leak == other.blockIpv6Leak;

  @override
  int get hashCode => Object.hash(
        stack,
        mtu,
        strictRoute,
        endpointIndependentNat,
        udpTimeoutSec,
        autoRoute,
        blockIpv6Leak,
      );

  String toJsonString() => jsonEncode(toJson());

  factory TunSettings.fromJsonString(String s) =>
      TunSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
