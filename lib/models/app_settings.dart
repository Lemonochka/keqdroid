import 'dart:convert';

import '../tunnel/connection_mode.dart';
import '../utils/routing_presets.dart';
import 'ping_test_config.dart';
import 'tun_settings.dart';
import 'xray_core_settings.dart';

class AppSettings {
  final int localPort;
  final int httpPort;
  final String directRules;
  final String proxyRules;
  final String blockedRules;
  final String finalOutbound;
  final bool ignoreProviderRules;
  final bool autoConnectLastServer;
  final String pingType;
  final String pingTestTarget;
  final String pingTestUrlCustom;

  final bool pingKeepAlive;

  // при запуске и после обновления подписки, без кнопки
  final bool autoPing;
  final bool darkTheme;
  final bool followSystemTheme;
  final String themePresetId;

  final String customThemeSeed;

  final String customThemeVariant;

  final String iconShapeId;

  final String fontId;
  final bool debugMode;
  final bool lanSharing;
  final int lanSocksPort;
  final int lanHttpPort;
  final String lanUsername;
  final String lanPassword;
  final bool shareDeviceHwid;
  final XrayCoreSettings xrayCore;
  final TunSettings tun;
  final String connectionMode;

  // на Android до 0.13.0 режим не читался и у всех лежит десктопный proxy,
  // поэтому без флага там считаем VPN
  final bool connectionModeChosen;

  final bool proxyModeAuth;

  final String proxyModeUser;
  final String proxyModePass;
  final bool systemProxyEnabled;
  final String appLanguageCode;
  final bool minimizeToTray;
  final bool launchAtStartup;

  final bool launchAtStartupElevated;
  final bool autostartInTray;
  final bool serverIconThemeColors;

  final String coreEngine;

  final String vpnCore;

  final bool fakeIp;
  final Map<String, String> hotkeys;
  final bool serversTwoColumns;
  final int serversColumns;
  final bool modernConnectPanel;
  final String bottomBarStyle;
  final bool amoledBlack;
  final bool seasonalDecor;
  final bool hapticFeedback;
  final bool showTrafficStats;
  final bool showConnectionTime;
  final bool showTrafficSplit;

  final bool waveLatencyColor;
  final bool showSpeedInNotification;
  final bool showUptimeInNotification;
  final bool notifySubscriptionUpdates;
  final bool linuxTunRememberDismissed;

  final double uiScale;

  static const minUiScale = 0.7;
  static const maxUiScale = 1.4;

  static double clampUiScale(double v) =>
      v.isFinite ? v.clamp(minUiScale, maxUiScale) : 1.0;

  static int normalizeServersColumns(Object? v) => v == 3 ? 3 : 2;

  const AppSettings({
    this.localPort = 2080,
    this.httpPort = 2081,
    this.directRules = RoutingPresets.defaultDirectRules,
    this.proxyRules = RoutingPresets.defaultProxyRules,
    this.blockedRules = RoutingPresets.defaultBlockedRules,
    this.finalOutbound = finalOutboundProxy,
    this.ignoreProviderRules = false,
    this.autoConnectLastServer = false,
    this.pingType = 'url',
    this.pingTestTarget = PingTestConfig.targetGstatic,
    this.pingTestUrlCustom = '',
    this.pingKeepAlive = true,
    this.autoPing = false,
    this.darkTheme = false,
    this.followSystemTheme = true,
    this.themePresetId = 'ocean',
    this.customThemeSeed = '',
    this.customThemeVariant = 'tonalSpot',
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
    this.launchAtStartupElevated = false,
    this.autostartInTray = false,
    this.serverIconThemeColors = true,
    this.coreEngine = coreEngineKeqrnel,
    this.vpnCore = vpnCoreXray,
    this.fakeIp = false,
    this.hotkeys = const {},
    this.serversTwoColumns = false,
    this.serversColumns = 2,
    this.modernConnectPanel = false,
    this.bottomBarStyle = bottomBarModern,
    this.amoledBlack = false,
    this.seasonalDecor = true,
    this.hapticFeedback = true,
    this.showTrafficStats = true,
    this.showConnectionTime = true,
    this.showTrafficSplit = false,
    this.waveLatencyColor = true,
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
    'ignoreProviderRules': ignoreProviderRules,
    'autoConnectLastServer': autoConnectLastServer,
    'pingType': pingType,
    'pingTestTarget': pingTestTarget,
    'pingTestUrlCustom': pingTestUrlCustom,
    'pingKeepAlive': pingKeepAlive,
    'autoPing': autoPing,
    'darkTheme': darkTheme,
    'followSystemTheme': followSystemTheme,
    'themePresetId': themePresetId,
    'customThemeSeed': customThemeSeed,
    'customThemeVariant': customThemeVariant,
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
    'launchAtStartupElevated': launchAtStartupElevated,
    'autostartInTray': autostartInTray,
    'serverIconThemeColors': serverIconThemeColors,
    'coreEngine': coreEngine,
    'vpnCore': vpnCore,
    'fakeIp': fakeIp,
    'hotkeys': hotkeys,
    'serversTwoColumns': serversTwoColumns,
    'serversColumns': serversColumns,
    'modernConnectPanel': modernConnectPanel,
    'bottomBarStyle': bottomBarStyle,
    'amoledBlack': amoledBlack,
    'seasonalDecor': seasonalDecor,
    'hapticFeedback': hapticFeedback,
    'showTrafficStats': showTrafficStats,
    'showConnectionTime': showConnectionTime,
    'showTrafficSplit': showTrafficSplit,
    'waveLatencyColor': waveLatencyColor,
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
      ignoreProviderRules: json['ignoreProviderRules'] as bool? ?? false,
      autoConnectLastServer: json['autoConnectLastServer'] as bool? ?? false,
      pingType: _normalizePingType(json['pingType'] as String?),
      pingTestTarget: PingTestConfig.normalizeTarget(
        json['pingTestTarget'] as String?,
      ),
      pingTestUrlCustom: json['pingTestUrlCustom'] as String? ?? '',
      pingKeepAlive: json['pingKeepAlive'] as bool? ?? true,
      autoPing: json['autoPing'] as bool? ?? false,
      darkTheme: json['darkTheme'] as bool? ?? false,
      followSystemTheme: json['followSystemTheme'] as bool? ?? true,
      themePresetId: json['themePresetId'] as String? ?? 'ocean',
      customThemeSeed: json['customThemeSeed'] as String? ?? '',
      customThemeVariant:
          json['customThemeVariant'] as String? ?? 'tonalSpot',
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
      launchAtStartupElevated:
          json['launchAtStartupElevated'] as bool? ?? false,
      autostartInTray: json['autostartInTray'] as bool? ?? false,
      serverIconThemeColors: json['serverIconThemeColors'] as bool? ?? true,
      coreEngine: normalizeCoreEngine(json['coreEngine'] as String?),
      vpnCore: normalizeVpnCore(json['vpnCore'] as String?),
      // mihomoFakeIp: старое имя ключа, до 26.09.2026
      fakeIp: json['fakeIp'] as bool? ?? json['mihomoFakeIp'] as bool? ?? false,
      hotkeys: _readHotkeys(json['hotkeys']),
      serversTwoColumns: json['serversTwoColumns'] as bool? ?? false,
      serversColumns: normalizeServersColumns(json['serversColumns']),
      modernConnectPanel: json['modernConnectPanel'] as bool? ?? false,
      bottomBarStyle: json['bottomBarStyle'] as String? ?? bottomBarModern,
      amoledBlack: json['amoledBlack'] as bool? ?? false,
      seasonalDecor: json['seasonalDecor'] as bool? ?? true,
      hapticFeedback: json['hapticFeedback'] as bool? ?? true,
      // у старых настроек бывают включены обе, тогда побеждает разбивка
      showTrafficStats: (json['showTrafficStats'] as bool? ?? true) &&
          !(json['showTrafficSplit'] as bool? ?? false),
      showConnectionTime: json['showConnectionTime'] as bool? ?? true,
      showTrafficSplit: json['showTrafficSplit'] as bool? ?? false,
      waveLatencyColor: json['waveLatencyColor'] as bool? ?? true,
      showSpeedInNotification: json['showSpeedInNotification'] as bool? ?? true,
      showUptimeInNotification:
          json['showUptimeInNotification'] as bool? ?? true,
      notifySubscriptionUpdates:
          json['notifySubscriptionUpdates'] as bool? ?? true,
      linuxTunRememberDismissed:
          json['linuxTunRememberDismissed'] as bool? ?? false,
      // из отредактированного руками бэкапа может приехать и строка
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

  static const vpnCoreXray = 'xray';
  static const vpnCoreMihomo = 'mihomo';
  static const vpnCores = [vpnCoreXray, vpnCoreMihomo];

  // нижняя панель: legacy или стиль Модерна strip, brightPlus, islands
  static const bottomBarLegacy = 'legacy';
  static const bottomBarModern = 'strip';

  // прежнее auto выбирало то же, что xray, и в сохранённых настройках становится им
  static String normalizeVpnCore(String? raw) {
    final v = raw?.trim().toLowerCase();
    return vpnCores.contains(v) ? v! : vpnCoreXray;
  }

  static const coreEngineChain = 'chain';
  static const coreEngineKeqrnel = 'keqrnel';
  static const coreEngines = [coreEngineChain, coreEngineKeqrnel];

  static String normalizeCoreEngine(String? raw) {
    final v = raw?.trim().toLowerCase();
    return v == coreEngineChain ? coreEngineChain : coreEngineKeqrnel;
  }

  static String _normalizeLanguageCode(String? raw) {
    final v = raw?.trim().toLowerCase();
    // новый язык добавлять и сюда, иначе после перезапуска он станет системным
    if (v == 'en' || v == 'ru' || v == 'de' || v == 'zh' || v == 'fa') {
      return v!;
    }
    return 'system';
  }

  static bool _validPort(int p) => p > 0 && p <= 65535;

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
    return 'url';
  }

  AppSettings copyWith({
    int? localPort,
    int? httpPort,
    String? directRules,
    String? proxyRules,
    String? blockedRules,
    String? finalOutbound,
    bool? ignoreProviderRules,
    bool? autoConnectLastServer,
    String? pingType,
    String? pingTestTarget,
    String? pingTestUrlCustom,
    bool? pingKeepAlive,
    bool? autoPing,
    bool? darkTheme,
    bool? followSystemTheme,
    String? themePresetId,
    String? customThemeSeed,
    String? customThemeVariant,
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
    bool? launchAtStartupElevated,
    bool? autostartInTray,
    bool? serverIconThemeColors,
    String? coreEngine,
    String? vpnCore,
    bool? fakeIp,
    Map<String, String>? hotkeys,
    bool? serversTwoColumns,
    int? serversColumns,
    bool? modernConnectPanel,
    String? bottomBarStyle,
    bool? amoledBlack,
    bool? seasonalDecor,
    bool? hapticFeedback,
    bool? showTrafficStats,
    bool? showConnectionTime,
    bool? showTrafficSplit,
    bool? waveLatencyColor,
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
        ignoreProviderRules: ignoreProviderRules ?? this.ignoreProviderRules,
        autoConnectLastServer: autoConnectLastServer ?? this.autoConnectLastServer,
        pingType: pingType ?? this.pingType,
        pingTestTarget: pingTestTarget ?? this.pingTestTarget,
        pingTestUrlCustom: pingTestUrlCustom ?? this.pingTestUrlCustom,
        pingKeepAlive: pingKeepAlive ?? this.pingKeepAlive,
        autoPing: autoPing ?? this.autoPing,
        darkTheme: darkTheme ?? this.darkTheme,
        followSystemTheme: followSystemTheme ?? this.followSystemTheme,
        themePresetId: themePresetId ?? this.themePresetId,
        customThemeSeed: customThemeSeed ?? this.customThemeSeed,
        customThemeVariant: customThemeVariant ?? this.customThemeVariant,
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
        launchAtStartupElevated:
            launchAtStartupElevated ?? this.launchAtStartupElevated,
        autostartInTray: autostartInTray ?? this.autostartInTray,
        serverIconThemeColors:
            serverIconThemeColors ?? this.serverIconThemeColors,
        coreEngine: coreEngine ?? this.coreEngine,
        vpnCore: vpnCore ?? this.vpnCore,
        fakeIp: fakeIp ?? this.fakeIp,
        hotkeys: hotkeys ?? this.hotkeys,
        serversTwoColumns: serversTwoColumns ?? this.serversTwoColumns,
        serversColumns:
            normalizeServersColumns(serversColumns ?? this.serversColumns),
        modernConnectPanel: modernConnectPanel ?? this.modernConnectPanel,
        bottomBarStyle: bottomBarStyle ?? this.bottomBarStyle,
        amoledBlack: amoledBlack ?? this.amoledBlack,
        seasonalDecor: seasonalDecor ?? this.seasonalDecor,
        hapticFeedback: hapticFeedback ?? this.hapticFeedback,
        showTrafficStats: showTrafficStats ?? this.showTrafficStats,
        showConnectionTime: showConnectionTime ?? this.showConnectionTime,
        showTrafficSplit: showTrafficSplit ?? this.showTrafficSplit,
        waveLatencyColor: waveLatencyColor ?? this.waveLatencyColor,
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

  AppSettings withTrafficStats(bool on) => copyWith(
        showTrafficStats: on,
        showTrafficSplit: on ? false : showTrafficSplit,
      );

  AppSettings withTrafficSplit(bool on) => copyWith(
        showTrafficSplit: on,
        showTrafficStats: on ? false : showTrafficStats,
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
              ignoreProviderRules == other.ignoreProviderRules &&
              autoConnectLastServer == other.autoConnectLastServer &&
              pingType == other.pingType &&
              pingTestTarget == other.pingTestTarget &&
              pingTestUrlCustom == other.pingTestUrlCustom &&
              pingKeepAlive == other.pingKeepAlive &&
              autoPing == other.autoPing &&
              darkTheme == other.darkTheme &&
              followSystemTheme == other.followSystemTheme &&
              themePresetId == other.themePresetId &&
              customThemeSeed == other.customThemeSeed &&
              customThemeVariant == other.customThemeVariant &&
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
              launchAtStartupElevated == other.launchAtStartupElevated &&
              autostartInTray == other.autostartInTray &&
              serverIconThemeColors == other.serverIconThemeColors &&
              coreEngine == other.coreEngine &&
              vpnCore == other.vpnCore &&
              fakeIp == other.fakeIp &&
              serversTwoColumns == other.serversTwoColumns &&
              serversColumns == other.serversColumns &&
              modernConnectPanel == other.modernConnectPanel &&
              bottomBarStyle == other.bottomBarStyle &&
              amoledBlack == other.amoledBlack &&
              seasonalDecor == other.seasonalDecor &&
              hapticFeedback == other.hapticFeedback &&
              showTrafficStats == other.showTrafficStats &&
              showConnectionTime == other.showConnectionTime &&
              showTrafficSplit == other.showTrafficSplit &&
              waveLatencyColor == other.waveLatencyColor &&
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
    ignoreProviderRules,
    autoConnectLastServer,
    pingType,
    pingTestTarget,
    pingTestUrlCustom,
    pingKeepAlive,
    autoPing,
    darkTheme,
    followSystemTheme,
    themePresetId,
    customThemeSeed,
    customThemeVariant,
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
    launchAtStartupElevated,
    autostartInTray,
    serverIconThemeColors,
    coreEngine,
    vpnCore,
    fakeIp,
    serversTwoColumns,
    serversColumns,
    modernConnectPanel,
    bottomBarStyle,
    amoledBlack,
    seasonalDecor,
    hapticFeedback,
    showTrafficStats,
    showConnectionTime,
    showTrafficSplit,
    waveLatencyColor,
    showSpeedInNotification,
    showUptimeInNotification,
    notifySubscriptionUpdates,
    linuxTunRememberDismissed,
    uiScale,
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
