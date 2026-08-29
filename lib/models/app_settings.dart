import 'dart:convert';

import '../tunnel/connection_mode.dart';
import '../utils/routing_presets.dart';
import 'ping_test_config.dart';
import 'tun_settings.dart';
import 'xray_core_settings.dart';

class AppSettings {
  final int localPort;
  final int httpPort;
  /// Mixed routing lists: each may hold domains, IP/CIDR ranges and prefixed
  /// rules (geosite:/geoip:/full:/regexp:). Split by the config generators.
  final String directRules;
  final String proxyRules;
  final String blockedRules;
  /// Финальное действие (catch-all) для трафика, не попавшего ни в одно правило:
  /// `proxy` — глобальный прокси (дефолт), `direct` — обход (bypass, как выключение
  /// глобал-прокси в Happ), `block` — блокировать. Прошивается в catch-all обоих
  /// генераторов конфига (xray и sing-box TUN).
  final String finalOutbound;
  final bool autoConnectLastServer;
  final String pingType;
  /// [PingTestConfig.targetGstatic] | cloudflare | microsoft | custom
  final String pingTestTarget;
  final String pingTestUrlCustom;

  /// Прокси-пинг делает два запроса по одному соединению и берёт лучший: первый
  /// оплачивает DNS и TLS-рукопожатие, второй меряет чистое время ответа.
  /// Выключенный — один запрос, то есть задержка вместе со стоимостью
  /// установки соединения. Числа получаются в разы больше, зато привычнее.
  final bool pingKeepAlive;
  final bool killSwitch;
  final bool darkTheme;
  final bool followSystemTheme;
  final String themePresetId;

  /// Форма кружков под иконками: id из [IconShape] (`circle` по умолчанию).
  final String iconShapeId;

  /// Шрифт интерфейса: id из [kAppFonts] (`system` по умолчанию).
  final String fontId;
  final bool debugMode;
  final bool lanSharing;
  final int lanSocksPort;
  final int lanHttpPort;
  /// Креды LAN-инбаундов (socks-lan/http-lan). Обе строки непустые — инбаунды
  /// требуют пароль; иначе noauth (открытый прокси в локальной сети).
  final String lanUsername;
  final String lanPassword;
  final bool shareDeviceHwid; // слать ли hwid при запросе подписок
  final XrayCoreSettings xrayCore;
  /// Desktop TUN: стек (system/gvisor/mixed), MTU и прочие опции sing-box-инбаунда.
  final TunSettings tun;
  /// `proxy` (только локальный прокси) или `tun` (полноценный туннель).
  /// См. [ConnectionMode].
  ///
  /// Дефолт `proxy` — десктопный: там TUN требует прав администратора, и первое
  /// подключение не должно упираться в UAC.
  final String connectionMode;

  /// Режим выбран человеком, а не достался от дефолта.
  ///
  /// Нужен из-за истории поля. На Android режим до 0.13.0 не читался вовсе —
  /// [TunnelSessionBuilder.resolveMode] возвращал `tun` не глядя, — поэтому у
  /// КАЖДОЙ установки в настройках лежит десктопный дефолт `proxy`, который
  /// никто не выбирал. Начни мы просто уважать сохранённое значение, и всё
  /// обновившееся стадо разом переехало бы в режим «только прокси»: туннель не
  /// поднимается, трафик мимо VPN, и с виду приложение сломалось.
  ///
  /// Поэтому на Android «не выбирали» читается как VPN, а флаг ставится ровно
  /// тогда, когда режим переключили руками.
  final bool connectionModeChosen;

  /// Требовать логин с паролем у локального прокси в режиме «Прокси».
  ///
  /// Выключается ради потребителей, которым креды вписать некуда: системное
  /// поле прокси у Wi-Fi знает только адрес и порт.
  final bool proxyModeAuth;

  /// Креды локального прокси. Хранятся, а не генерируются на каждый старт, как
  /// сессионные: их вписывают в чужое приложение руками, и меняться под ним они
  /// не должны. Пустые — ещё не создавались.
  final String proxyModeUser;
  final String proxyModePass;
  /// Desktop proxy: включать системный прокси Windows.
  final bool systemProxyEnabled;
  /// `system` — язык ОС, иначе `en` / `ru`.
  final String appLanguageCode;
  /// Windows: сворачивать в трей при закрытии окна.
  final bool minimizeToTray;
  /// Windows: запуск вместе с системой.
  final bool launchAtStartup;
  /// Ядро: `keqrnel` (единое ядро со встроенным xray, дефолт) или `chain`
  /// (связка xray → sing-box; только если явно сохранён в настройках).
  final String coreEngine;

  /// Ядро, исполняющее сервер: `xray` (дефолт) или `mihomo`.
  final String vpnCore;

  /// mihomo: отдавать системе подменные адреса вместо настоящих (`fake-ip`).
  ///
  /// Значимо только там, где туннелем владеет само ядро и есть перехват DNS:
  /// TUN-режим на десктопе и Android. В прокси-режиме десктопа запросы системы
  /// до ядра не доходят вовсе, и подменять нечего.
  ///
  /// Выключено по умолчанию не из осторожности вообще, а по конкретной причине:
  /// с fake-ip назначение соединения перестаёт быть настоящим адресом, и
  /// IP-правила пользователя приходится доразрешать (см.
  /// [MihomoConfigGen.buildUserRules]) — то есть одни и те же списки ведут себя
  /// не так, как на xray. Взамен резолв становится мгновенным, а доменные
  /// правила перестают зависеть от снифера.
  final bool mihomoFakeIp;
  /// Desktop: хоткеи (HotkeyAction.id → токен сочетания, напр. `ctrl+shift+keyT`).
  /// Пустая карта = все хоткеи выключены (дефолт).
  final Map<String, String> hotkeys;
  /// Список серверов в две колонки.
  final bool serversTwoColumns;
  /// Чёрный AMOLED-фон в тёмной теме: на OLED-экране выключенный пиксель не
  /// светится вовсе. На светлую тему не влияет.
  final bool amoledBlack;
  /// Тактильная отдача на нажатия. На десктопе значения не имеет.
  final bool hapticFeedback;
  /// Чипы скорости и объёма трафика под кнопкой подключения.
  final bool showTrafficStats;
  /// Чип времени подключения под кнопкой подключения.
  final bool showConnectionTime;
  /// Показывать скорость (↓/↑) в системном уведомлении VPN.
  final bool showSpeedInNotification;
  /// Показывать время подключения (аптайм) в системном уведомлении VPN.
  final bool showUptimeInNotification;
  /// Слать локальное уведомление после фонового обновления подписок.
  final bool notifySubscriptionUpdates;
  /// Linux: пользователь уже ответил на предложение сделать TUN беспарольным
  /// (установка polkit-правила) — окно больше не показываем.
  final bool linuxTunRememberDismissed;

  /// Множитель размера интерфейса поверх системного.
  ///
  /// Именно ПОВЕРХ, а не вместо: системный масштаб — это настройка доступности,
  /// и заменять его своим значением значит отобрать крупный шрифт у того, кто
  /// выставил его в системе и до этой настройки не дошёл. Здесь 1.0 = «как
  /// система», а всё остальное — поправка к ней.
  ///
  /// Масштабируется ТЕКСТ. Иконки и отступы заданы числами в полутора сотнях
  /// мест и на этот множитель не смотрят; строки списка при этом подстроятся —
  /// их высота считается через `MediaQuery.textScalerOf` (см. `servers_tab`).
  final double uiScale;

  /// Границы множителя. Снизу — читаемость, сверху — вёрстка: дальше строки
  /// списка и чипы под кнопкой начинают переноситься и обрезаться.
  static const minUiScale = 0.8;
  static const maxUiScale = 1.4;

  static double clampUiScale(double v) =>
      v.isFinite ? v.clamp(minUiScale, maxUiScale) : 1.0;

  const AppSettings({
    this.localPort = 2080,
    this.httpPort = 2081,
    this.directRules = RoutingPresets.defaultDirectRules,
    this.proxyRules = RoutingPresets.defaultProxyRules,
    this.blockedRules = RoutingPresets.defaultBlockedRules,
    this.finalOutbound = finalOutboundProxy,
    this.autoConnectLastServer = false,
    this.pingType = 'url',
    this.pingTestTarget = PingTestConfig.targetGstatic,
    this.pingTestUrlCustom = '',
    this.pingKeepAlive = true,
    this.killSwitch = false,
    this.darkTheme = false,
    this.followSystemTheme = true,
    this.themePresetId = 'ocean',
    this.iconShapeId = 'circle',
    this.fontId = 'system',
    this.debugMode = false,
    this.lanSharing = false,
    this.lanSocksPort = 1080,
    this.lanHttpPort = 8080,
    this.lanUsername = '',
    this.lanPassword = '',
    this.shareDeviceHwid = true,
    this.xrayCore = const XrayCoreSettings(),
    this.tun = const TunSettings(),
    this.connectionMode = 'proxy',
    this.connectionModeChosen = false,
    this.proxyModeAuth = true,
    this.proxyModeUser = '',
    this.proxyModePass = '',
    this.systemProxyEnabled = true,
    this.appLanguageCode = 'system',
    this.minimizeToTray = true,
    this.launchAtStartup = false,
    this.coreEngine = coreEngineKeqrnel,
    this.vpnCore = vpnCoreAuto,
    this.mihomoFakeIp = false,
    this.hotkeys = const {},
    this.serversTwoColumns = false,
    this.amoledBlack = false,
    this.hapticFeedback = true,
    this.showTrafficStats = true,
    this.showConnectionTime = true,
    this.showSpeedInNotification = true,
    this.showUptimeInNotification = true,
    this.notifySubscriptionUpdates = true,
    this.linuxTunRememberDismissed = false,
    this.uiScale = 1.0,
  });

  Map<String, dynamic> toJson() => {
    'localPort': localPort,
    'httpPort': httpPort,
    'directRules': directRules,
    'proxyRules': proxyRules,
    'blockedRules': blockedRules,
    'finalOutbound': finalOutbound,
    'autoConnectLastServer': autoConnectLastServer,
    'pingType': pingType,
    'pingTestTarget': pingTestTarget,
    'pingTestUrlCustom': pingTestUrlCustom,
    'pingKeepAlive': pingKeepAlive,
    'killSwitch': killSwitch,
    'darkTheme': darkTheme,
    'followSystemTheme': followSystemTheme,
    'themePresetId': themePresetId,
    'iconShapeId': iconShapeId,
    'fontId': fontId,
    'debugMode': debugMode,
    'lanSharing': lanSharing,
    'lanSocksPort': lanSocksPort,
    'lanHttpPort': lanHttpPort,
    'lanUsername': lanUsername,
    'lanPassword': lanPassword,
    'shareDeviceHwid': shareDeviceHwid,
    'xrayCore': xrayCore.toJson(),
    'tun': tun.toJson(),
    'connectionMode': connectionMode,
    'connectionModeChosen': connectionModeChosen,
    'proxyModeAuth': proxyModeAuth,
    'proxyModeUser': proxyModeUser,
    'proxyModePass': proxyModePass,
    'systemProxyEnabled': systemProxyEnabled,
    'appLanguageCode': appLanguageCode,
    'minimizeToTray': minimizeToTray,
    'launchAtStartup': launchAtStartup,
    'coreEngine': coreEngine,
    'vpnCore': vpnCore,
    'mihomoFakeIp': mihomoFakeIp,
    'hotkeys': hotkeys,
    'serversTwoColumns': serversTwoColumns,
    'amoledBlack': amoledBlack,
    'hapticFeedback': hapticFeedback,
    'showTrafficStats': showTrafficStats,
    'showConnectionTime': showConnectionTime,
    'showSpeedInNotification': showSpeedInNotification,
    'showUptimeInNotification': showUptimeInNotification,
    'notifySubscriptionUpdates': notifySubscriptionUpdates,
    'linuxTunRememberDismissed': linuxTunRememberDismissed,
    'uiScale': uiScale,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    int port(String key, int fallback) {
      final v = (json[key] as num?)?.toInt() ?? fallback;
      return _validPort(v) ? v : fallback;
    }
    return AppSettings(
      localPort: port('localPort', 2080),
      httpPort: port('httpPort', 2081),
      directRules: _migrateRules(
        json,
        newKey: 'directRules',
        legacyKeys: const ['directDomains', 'directIps'],
        fallback: 'ru, yandex.ru, vk.com',
      ),
      proxyRules: _migrateRules(
        json,
        newKey: 'proxyRules',
        legacyKeys: const ['proxyDomains'],
        fallback: '',
      ),
      blockedRules: _migrateRules(
        json,
        newKey: 'blockedRules',
        legacyKeys: const ['blockedDomains'],
        fallback: '',
      ),
      finalOutbound: normalizeFinalOutbound(json['finalOutbound'] as String?),
      autoConnectLastServer: json['autoConnectLastServer'] as bool? ?? false,
      pingType: _normalizePingType(json['pingType'] as String?),
      pingTestTarget: PingTestConfig.normalizeTarget(
        json['pingTestTarget'] as String?,
      ),
      pingTestUrlCustom: json['pingTestUrlCustom'] as String? ?? '',
      pingKeepAlive: json['pingKeepAlive'] as bool? ?? true,
      killSwitch: json['killSwitch'] as bool? ?? false,
      darkTheme: json['darkTheme'] as bool? ?? false,
      followSystemTheme: json['followSystemTheme'] as bool? ?? true,
      themePresetId: json['themePresetId'] as String? ?? 'ocean',
      iconShapeId: json['iconShapeId'] as String? ?? 'circle',
      fontId: json['fontId'] as String? ?? 'system',
      debugMode: json['debugMode'] as bool? ?? false,
      lanSharing: json['lanSharing'] as bool? ?? false,
      lanSocksPort: port('lanSocksPort', 1080),
      lanHttpPort: port('lanHttpPort', 8080),
      lanUsername: json['lanUsername'] as String? ?? '',
      lanPassword: json['lanPassword'] as String? ?? '',
      shareDeviceHwid: json['shareDeviceHwid'] as bool? ?? true,
      xrayCore: XrayCoreSettings.fromJson(
        json['xrayCore'] as Map<String, dynamic>?,
      ),
      tun: TunSettings.fromJson(json['tun'] as Map<String, dynamic>?),
      connectionMode: ConnectionMode.fromStorage(
        json['connectionMode'] as String?,
      ).storageValue,
      connectionModeChosen: json['connectionModeChosen'] as bool? ?? false,
      proxyModeAuth: json['proxyModeAuth'] as bool? ?? true,
      proxyModeUser: json['proxyModeUser'] as String? ?? '',
      proxyModePass: json['proxyModePass'] as String? ?? '',
      systemProxyEnabled: json['systemProxyEnabled'] as bool? ?? true,
      appLanguageCode: _normalizeLanguageCode(
        json['appLanguageCode'] as String?,
      ),
      minimizeToTray: json['minimizeToTray'] as bool? ?? true,
      launchAtStartup: json['launchAtStartup'] as bool? ?? false,
      coreEngine: normalizeCoreEngine(json['coreEngine'] as String?),
      vpnCore: normalizeVpnCore(json['vpnCore'] as String?),
      mihomoFakeIp: json['mihomoFakeIp'] as bool? ?? false,
      hotkeys: _readHotkeys(json['hotkeys']),
      serversTwoColumns: json['serversTwoColumns'] as bool? ?? false,
      amoledBlack: json['amoledBlack'] as bool? ?? false,
      hapticFeedback: json['hapticFeedback'] as bool? ?? true,
      showTrafficStats: json['showTrafficStats'] as bool? ?? true,
      showConnectionTime: json['showConnectionTime'] as bool? ?? true,
      showSpeedInNotification: json['showSpeedInNotification'] as bool? ?? true,
      showUptimeInNotification:
          json['showUptimeInNotification'] as bool? ?? true,
      notifySubscriptionUpdates:
          json['notifySubscriptionUpdates'] as bool? ?? true,
      linuxTunRememberDismissed:
          json['linuxTunRememberDismissed'] as bool? ?? false,
      // Через clamp и проверку типа, а не приведением: значение приезжает и из
      // бэкапа, который правят руками, — там и строка возможна, и границы у
      // соседней версии могли быть шире.
      uiScale: clampUiScale(
        json['uiScale'] is num ? (json['uiScale'] as num).toDouble() : 1.0,
      ),
    );
  }

  static Map<String, String> _readHotkeys(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, String>{};
    raw.forEach((k, v) {
      if (k is String && v is String && v.isNotEmpty) out[k] = v;
    });
    return out;
  }

  /// Допустимые значения [finalOutbound].
  static const finalOutboundProxy = 'proxy';
  static const finalOutboundDirect = 'direct';
  static const finalOutboundBlock = 'block';
  static const finalOutbounds = [
    finalOutboundProxy,
    finalOutboundDirect,
    finalOutboundBlock,
  ];

  static String normalizeFinalOutbound(String? raw) {
    final v = raw?.trim().toLowerCase();
    return finalOutbounds.contains(v) ? v! : finalOutboundProxy;
  }

  /// Допустимые значения [vpnCore] — какое ядро исполняет сервер.
  ///
  /// Это НЕ [coreEngine]: тот про связку внутри xray-пути (`chain` против
  /// `keqrnel`) и на Android всегда `chain`. Здесь выбирается само ядро.
  /// AmneziaWG-серверы выбор игнорируют: их формат исполняет только своё ядро.
  /// «Само»: ядро выбирает ФОРМАТ сервера. Ссылку берёт xray, готовый конфиг —
  /// то ядро, на языке которого он написан. Умолчание: пользователю не нужно
  /// знать, чем отличается json от yaml, чтобы подписка заработала.
  static const vpnCoreAuto = 'auto';
  static const vpnCoreXray = 'xray';
  static const vpnCoreMihomo = 'mihomo';
  static const vpnCores = [vpnCoreAuto, vpnCoreXray, vpnCoreMihomo];

  static String normalizeVpnCore(String? raw) {
    final v = raw?.trim().toLowerCase();
    return vpnCores.contains(v) ? v! : vpnCoreAuto;
  }

  /// Допустимые значения [coreEngine].
  static const coreEngineChain = 'chain';
  static const coreEngineKeqrnel = 'keqrnel';
  static const coreEngines = [coreEngineChain, coreEngineKeqrnel];

  static String normalizeCoreEngine(String? raw) {
    final v = raw?.trim().toLowerCase();
    // keqrnel is the default; only an explicitly saved "chain" keeps the old path.
    return v == coreEngineChain ? coreEngineChain : coreEngineKeqrnel;
  }

  static String _normalizeLanguageCode(String? raw) {
    final v = raw?.trim().toLowerCase();
    if (v == 'en' || v == 'ru' || v == 'de' || v == 'zh') return v!;
    return 'system';
  }

  static bool _validPort(int p) => p > 0 && p <= 65535;

  /// Reads a mixed routing list, migrating from the old split domain/ip keys.
  /// Prefers [newKey]; otherwise merges any present [legacyKeys] (deduped),
  /// falling back to [fallback] when nothing was stored.
  static String _migrateRules(
    Map<String, dynamic> json, {
    required String newKey,
    required List<String> legacyKeys,
    required String fallback,
  }) {
    final fresh = json[newKey] as String?;
    if (fresh != null) return fresh;

    final hasLegacy = legacyKeys.any(json.containsKey);
    if (!hasLegacy) return fallback;

    final seen = <String>{};
    final merged = <String>[];
    for (final key in legacyKeys) {
      final raw = json[key] as String?;
      if (raw == null) continue;
      for (final token in raw.split(RegExp(r'[\n,]'))) {
        final v = token.trim();
        if (v.isEmpty) continue;
        if (seen.add(v.toLowerCase())) merged.add(v);
      }
    }
    return merged.join(', ');
  }

  static const pingTypes = ['tcp', 'url', 'speed', 'icmp'];

  static String _normalizePingType(String? raw) {
    final v = raw?.trim().toLowerCase();
    if (v == 'url' || v == 'http' || v == 'proxy') return 'url';
    if (v == 'speed' || v == 'download' || v == 'throughput') return 'speed';
    if (v == 'icmp' || v == 'ping') return 'icmp';
    if (v == 'tcp') return 'tcp';
    // Дефолт — прокси-пинг: он единственный меряет путь до сервера так, как им
    // потом пойдёт трафик. Raw tcp вдобавок неизмерим при поднятом TUN.
    return 'url';
  }

  AppSettings copyWith({
    int? localPort,
    int? httpPort,
    String? directRules,
    String? proxyRules,
    String? blockedRules,
    String? finalOutbound,
    bool? autoConnectLastServer,
    String? pingType,
    String? pingTestTarget,
    String? pingTestUrlCustom,
    bool? pingKeepAlive,
    bool? killSwitch,
    bool? darkTheme,
    bool? followSystemTheme,
    String? themePresetId,
    String? iconShapeId,
    String? fontId,
    bool? debugMode,
    bool? lanSharing,
    int? lanSocksPort,
    int? lanHttpPort,
    String? lanUsername,
    String? lanPassword,
    bool? shareDeviceHwid,
    XrayCoreSettings? xrayCore,
    TunSettings? tun,
    String? connectionMode,
    bool? connectionModeChosen,
    bool? proxyModeAuth,
    String? proxyModeUser,
    String? proxyModePass,
    bool? systemProxyEnabled,
    String? appLanguageCode,
    bool? minimizeToTray,
    bool? launchAtStartup,
    String? coreEngine,
    String? vpnCore,
    bool? mihomoFakeIp,
    Map<String, String>? hotkeys,
    bool? serversTwoColumns,
    bool? amoledBlack,
    bool? hapticFeedback,
    bool? showTrafficStats,
    bool? showConnectionTime,
    bool? showSpeedInNotification,
    bool? showUptimeInNotification,
    bool? notifySubscriptionUpdates,
    bool? linuxTunRememberDismissed,
    double? uiScale,
  }) =>
      AppSettings(
        localPort: localPort ?? this.localPort,
        httpPort: httpPort ?? this.httpPort,
        directRules: directRules ?? this.directRules,
        proxyRules: proxyRules ?? this.proxyRules,
        blockedRules: blockedRules ?? this.blockedRules,
        finalOutbound: finalOutbound ?? this.finalOutbound,
        autoConnectLastServer: autoConnectLastServer ?? this.autoConnectLastServer,
        pingType: pingType ?? this.pingType,
        pingTestTarget: pingTestTarget ?? this.pingTestTarget,
        pingTestUrlCustom: pingTestUrlCustom ?? this.pingTestUrlCustom,
        pingKeepAlive: pingKeepAlive ?? this.pingKeepAlive,
        killSwitch: killSwitch ?? this.killSwitch,
        darkTheme: darkTheme ?? this.darkTheme,
        followSystemTheme: followSystemTheme ?? this.followSystemTheme,
        themePresetId: themePresetId ?? this.themePresetId,
        iconShapeId: iconShapeId ?? this.iconShapeId,
        fontId: fontId ?? this.fontId,
        debugMode: debugMode ?? this.debugMode,
        lanSharing: lanSharing ?? this.lanSharing,
        lanSocksPort: lanSocksPort ?? this.lanSocksPort,
        lanHttpPort: lanHttpPort ?? this.lanHttpPort,
        lanUsername: lanUsername ?? this.lanUsername,
        lanPassword: lanPassword ?? this.lanPassword,
        shareDeviceHwid: shareDeviceHwid ?? this.shareDeviceHwid,
        xrayCore: xrayCore ?? this.xrayCore,
        tun: tun ?? this.tun,
        connectionMode: connectionMode ?? this.connectionMode,
        connectionModeChosen: connectionModeChosen ?? this.connectionModeChosen,
        proxyModeAuth: proxyModeAuth ?? this.proxyModeAuth,
        proxyModeUser: proxyModeUser ?? this.proxyModeUser,
        proxyModePass: proxyModePass ?? this.proxyModePass,
        systemProxyEnabled: systemProxyEnabled ?? this.systemProxyEnabled,
        appLanguageCode: appLanguageCode ?? this.appLanguageCode,
        minimizeToTray: minimizeToTray ?? this.minimizeToTray,
        launchAtStartup: launchAtStartup ?? this.launchAtStartup,
        coreEngine: coreEngine ?? this.coreEngine,
        vpnCore: vpnCore ?? this.vpnCore,
        mihomoFakeIp: mihomoFakeIp ?? this.mihomoFakeIp,
        hotkeys: hotkeys ?? this.hotkeys,
        serversTwoColumns: serversTwoColumns ?? this.serversTwoColumns,
        amoledBlack: amoledBlack ?? this.amoledBlack,
        hapticFeedback: hapticFeedback ?? this.hapticFeedback,
        showTrafficStats: showTrafficStats ?? this.showTrafficStats,
        showConnectionTime: showConnectionTime ?? this.showConnectionTime,
        showSpeedInNotification:
            showSpeedInNotification ?? this.showSpeedInNotification,
        showUptimeInNotification:
            showUptimeInNotification ?? this.showUptimeInNotification,
        notifySubscriptionUpdates:
            notifySubscriptionUpdates ?? this.notifySubscriptionUpdates,
        linuxTunRememberDismissed:
            linuxTunRememberDismissed ?? this.linuxTunRememberDismissed,
        uiScale: clampUiScale(uiScale ?? this.uiScale),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is AppSettings &&
              runtimeType == other.runtimeType &&
              localPort == other.localPort &&
              httpPort == other.httpPort &&
              directRules == other.directRules &&
              proxyRules == other.proxyRules &&
              blockedRules == other.blockedRules &&
              finalOutbound == other.finalOutbound &&
              autoConnectLastServer == other.autoConnectLastServer &&
              pingType == other.pingType &&
              pingTestTarget == other.pingTestTarget &&
              pingTestUrlCustom == other.pingTestUrlCustom &&
              pingKeepAlive == other.pingKeepAlive &&
              killSwitch == other.killSwitch &&
              darkTheme == other.darkTheme &&
              followSystemTheme == other.followSystemTheme &&
              themePresetId == other.themePresetId &&
              iconShapeId == other.iconShapeId &&
              fontId == other.fontId &&
              debugMode == other.debugMode &&
              lanSharing == other.lanSharing &&
              lanSocksPort == other.lanSocksPort &&
              lanHttpPort == other.lanHttpPort &&
              lanUsername == other.lanUsername &&
              lanPassword == other.lanPassword &&
              shareDeviceHwid == other.shareDeviceHwid &&
              xrayCore == other.xrayCore &&
              tun == other.tun &&
              connectionMode == other.connectionMode &&
              connectionModeChosen == other.connectionModeChosen &&
              proxyModeAuth == other.proxyModeAuth &&
              proxyModeUser == other.proxyModeUser &&
              proxyModePass == other.proxyModePass &&
              systemProxyEnabled == other.systemProxyEnabled &&
              appLanguageCode == other.appLanguageCode &&
              minimizeToTray == other.minimizeToTray &&
              launchAtStartup == other.launchAtStartup &&
              coreEngine == other.coreEngine &&
              vpnCore == other.vpnCore &&
              mihomoFakeIp == other.mihomoFakeIp &&
              serversTwoColumns == other.serversTwoColumns &&
              amoledBlack == other.amoledBlack &&
              hapticFeedback == other.hapticFeedback &&
              showTrafficStats == other.showTrafficStats &&
              showConnectionTime == other.showConnectionTime &&
              showSpeedInNotification == other.showSpeedInNotification &&
              showUptimeInNotification == other.showUptimeInNotification &&
              notifySubscriptionUpdates == other.notifySubscriptionUpdates &&
              linuxTunRememberDismissed == other.linuxTunRememberDismissed &&
              uiScale == other.uiScale &&
              _hotkeysEqual(hotkeys, other.hotkeys);

  static bool _hotkeysEqual(Map<String, String> a, Map<String, String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll([
    localPort,
    httpPort,
    directRules,
    proxyRules,
    blockedRules,
    finalOutbound,
    autoConnectLastServer,
    pingType,
    pingTestTarget,
    pingTestUrlCustom,
    pingKeepAlive,
    killSwitch,
    darkTheme,
    followSystemTheme,
    themePresetId,
    iconShapeId,
    fontId,
    debugMode,
    lanSharing,
    lanSocksPort,
    lanHttpPort,
    lanUsername,
    lanPassword,
    shareDeviceHwid,
    xrayCore,
    tun,
    connectionMode,
    connectionModeChosen,
    proxyModeAuth,
    proxyModeUser,
    proxyModePass,
    systemProxyEnabled,
    appLanguageCode,
    minimizeToTray,
    launchAtStartup,
    coreEngine,
    vpnCore,
    mihomoFakeIp,
    serversTwoColumns,
    amoledBlack,
    hapticFeedback,
    showTrafficStats,
    showConnectionTime,
    showSpeedInNotification,
    showUptimeInNotification,
    notifySubscriptionUpdates,
    linuxTunRememberDismissed,
    uiScale,
    // порядок ключей в Map не влияет: хэшируем отсортированные записи
    Object.hashAll(
      (hotkeys.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key)))
          .map((e) => Object.hash(e.key, e.value)),
    ),
  ]);

  ConnectionMode get connectionModeEnum =>
      ConnectionMode.fromStorage(connectionMode);

  String toJsonString() => jsonEncode(toJson());

  factory AppSettings.fromJsonString(String s) =>
      AppSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);
}