import 'dart:convert';

import '../tunnel/connection_mode.dart';
import 'ping_test_config.dart';
import 'xray_core_settings.dart';

class AppSettings {
  final int localPort;
  final int httpPort;
  final String directDomains;
  final String blockedDomains;
  final String directIps;
  final String proxyDomains;
  final bool autoConnectLastServer;
  final String pingType;
  /// [PingTestConfig.targetGstatic] | cloudflare | microsoft | custom
  final String pingTestTarget;
  final String pingTestUrlCustom;
  final bool killSwitch;
  final bool darkTheme;
  final bool followSystemTheme;
  final String themePresetId;
  final bool debugMode;
  final bool lanSharing;
  final int lanSocksPort;
  final int lanHttpPort;
  final bool shareDeviceHwid; // слать ли hwid при запросе подписок
  final XrayCoreSettings xrayCore;
  /// Desktop: `proxy` (только Xray) или `tun` (Xray → sing-box). См. [ConnectionMode].
  final String connectionMode;
  /// Desktop proxy: включать системный прокси Windows.
  final bool systemProxyEnabled;
  /// `system` — язык ОС, иначе `en` / `ru`.
  final String appLanguageCode;

  const AppSettings({
    this.localPort = 2080,
    this.httpPort = 2081,
    this.directDomains = 'ru, yandex.ru, vk.com',
    this.blockedDomains = '',
    this.directIps = '192.168.0.0/16, 10.0.0.0/8, 127.0.0.0/8',
    this.proxyDomains = '',
    this.autoConnectLastServer = false,
    this.pingType = 'tcp',
    this.pingTestTarget = PingTestConfig.targetGstatic,
    this.pingTestUrlCustom = '',
    this.killSwitch = false,
    this.darkTheme = false,
    this.followSystemTheme = true,
    this.themePresetId = 'ocean',
    this.debugMode = false,
    this.lanSharing = false,
    this.lanSocksPort = 1080,
    this.lanHttpPort = 8080,
    this.shareDeviceHwid = true,
    this.xrayCore = const XrayCoreSettings(),
    this.connectionMode = 'proxy',
    this.systemProxyEnabled = true,
    this.appLanguageCode = 'system',
  });

  Map<String, dynamic> toJson() => {
    'localPort': localPort,
    'httpPort': httpPort,
    'directDomains': directDomains,
    'blockedDomains': blockedDomains,
    'directIps': directIps,
    'proxyDomains': proxyDomains,
    'autoConnectLastServer': autoConnectLastServer,
    'pingType': pingType,
    'pingTestTarget': pingTestTarget,
    'pingTestUrlCustom': pingTestUrlCustom,
    'killSwitch': killSwitch,
    'darkTheme': darkTheme,
    'followSystemTheme': followSystemTheme,
    'themePresetId': themePresetId,
    'debugMode': debugMode,
    'lanSharing': lanSharing,
    'lanSocksPort': lanSocksPort,
    'lanHttpPort': lanHttpPort,
    'shareDeviceHwid': shareDeviceHwid,
    'xrayCore': xrayCore.toJson(),
    'connectionMode': connectionMode,
    'systemProxyEnabled': systemProxyEnabled,
    'appLanguageCode': appLanguageCode,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    int port(String key, int fallback) {
      final v = (json[key] as num?)?.toInt() ?? fallback;
      return _validPort(v) ? v : fallback;
    }
    return AppSettings(
      localPort: port('localPort', 2080),
      httpPort: port('httpPort', 2081),
      directDomains: json['directDomains'] as String? ?? 'ru, yandex.ru, vk.com',
      blockedDomains: json['blockedDomains'] as String? ?? '',
      directIps: json['directIps'] as String? ?? '192.168.0.0/16, 10.0.0.0/8, 127.0.0.0/8',
      proxyDomains: json['proxyDomains'] as String? ?? '',
      autoConnectLastServer: json['autoConnectLastServer'] as bool? ?? false,
      pingType: _normalizePingType(json['pingType'] as String?),
      pingTestTarget: PingTestConfig.normalizeTarget(
        json['pingTestTarget'] as String?,
      ),
      pingTestUrlCustom: json['pingTestUrlCustom'] as String? ?? '',
      killSwitch: json['killSwitch'] as bool? ?? false,
      darkTheme: json['darkTheme'] as bool? ?? false,
      followSystemTheme: json['followSystemTheme'] as bool? ?? true,
      themePresetId: json['themePresetId'] as String? ?? 'ocean',
      debugMode: json['debugMode'] as bool? ?? false,
      lanSharing: json['lanSharing'] as bool? ?? false,
      lanSocksPort: port('lanSocksPort', 1080),
      lanHttpPort: port('lanHttpPort', 8080),
      shareDeviceHwid: json['shareDeviceHwid'] as bool? ?? true,
      xrayCore: XrayCoreSettings.fromJson(
        json['xrayCore'] as Map<String, dynamic>?,
      ),
      connectionMode: ConnectionMode.fromStorage(
        json['connectionMode'] as String?,
      ).storageValue,
      systemProxyEnabled: json['systemProxyEnabled'] as bool? ?? true,
      appLanguageCode: _normalizeLanguageCode(
        json['appLanguageCode'] as String?,
      ),
    );
  }

  static String _normalizeLanguageCode(String? raw) {
    final v = raw?.trim().toLowerCase();
    if (v == 'en' || v == 'ru' || v == 'de' || v == 'zh') return v!;
    return 'system';
  }

  static bool _validPort(int p) => p > 0 && p <= 65535;

  static const pingTypes = ['tcp', 'url', 'speed'];

  static String _normalizePingType(String? raw) {
    final v = raw?.trim().toLowerCase();
    if (v == 'url' || v == 'http' || v == 'proxy') return 'url';
    if (v == 'speed' || v == 'download' || v == 'throughput') return 'speed';
    return 'tcp';
  }

  AppSettings copyWith({
    int? localPort,
    int? httpPort,
    String? directDomains,
    String? blockedDomains,
    String? directIps,
    String? proxyDomains,
    bool? autoConnectLastServer,
    String? pingType,
    String? pingTestTarget,
    String? pingTestUrlCustom,
    bool? killSwitch,
    bool? darkTheme,
    bool? followSystemTheme,
    String? themePresetId,
    bool? debugMode,
    bool? lanSharing,
    int? lanSocksPort,
    int? lanHttpPort,
    bool? shareDeviceHwid,
    XrayCoreSettings? xrayCore,
    String? connectionMode,
    bool? systemProxyEnabled,
    String? appLanguageCode,
  }) =>
      AppSettings(
        localPort: localPort ?? this.localPort,
        httpPort: httpPort ?? this.httpPort,
        directDomains: directDomains ?? this.directDomains,
        blockedDomains: blockedDomains ?? this.blockedDomains,
        directIps: directIps ?? this.directIps,
        proxyDomains: proxyDomains ?? this.proxyDomains,
        autoConnectLastServer: autoConnectLastServer ?? this.autoConnectLastServer,
        pingType: pingType ?? this.pingType,
        pingTestTarget: pingTestTarget ?? this.pingTestTarget,
        pingTestUrlCustom: pingTestUrlCustom ?? this.pingTestUrlCustom,
        killSwitch: killSwitch ?? this.killSwitch,
        darkTheme: darkTheme ?? this.darkTheme,
        followSystemTheme: followSystemTheme ?? this.followSystemTheme,
        themePresetId: themePresetId ?? this.themePresetId,
        debugMode: debugMode ?? this.debugMode,
        lanSharing: lanSharing ?? this.lanSharing,
        lanSocksPort: lanSocksPort ?? this.lanSocksPort,
        lanHttpPort: lanHttpPort ?? this.lanHttpPort,
        shareDeviceHwid: shareDeviceHwid ?? this.shareDeviceHwid,
        xrayCore: xrayCore ?? this.xrayCore,
        connectionMode: connectionMode ?? this.connectionMode,
        systemProxyEnabled: systemProxyEnabled ?? this.systemProxyEnabled,
        appLanguageCode: appLanguageCode ?? this.appLanguageCode,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is AppSettings &&
              runtimeType == other.runtimeType &&
              localPort == other.localPort &&
              httpPort == other.httpPort &&
              directDomains == other.directDomains &&
              blockedDomains == other.blockedDomains &&
              directIps == other.directIps &&
              proxyDomains == other.proxyDomains &&
              autoConnectLastServer == other.autoConnectLastServer &&
              pingType == other.pingType &&
              pingTestTarget == other.pingTestTarget &&
              pingTestUrlCustom == other.pingTestUrlCustom &&
              killSwitch == other.killSwitch &&
              darkTheme == other.darkTheme &&
              followSystemTheme == other.followSystemTheme &&
              themePresetId == other.themePresetId &&
              debugMode == other.debugMode &&
              lanSharing == other.lanSharing &&
              lanSocksPort == other.lanSocksPort &&
              lanHttpPort == other.lanHttpPort &&
              shareDeviceHwid == other.shareDeviceHwid &&
              xrayCore == other.xrayCore &&
              connectionMode == other.connectionMode &&
              systemProxyEnabled == other.systemProxyEnabled &&
              appLanguageCode == other.appLanguageCode;

  @override
  int get hashCode => Object.hashAll([
    localPort,
    httpPort,
    directDomains,
    blockedDomains,
    directIps,
    proxyDomains,
    autoConnectLastServer,
    pingType,
    pingTestTarget,
    pingTestUrlCustom,
    killSwitch,
    darkTheme,
    followSystemTheme,
    themePresetId,
    debugMode,
    lanSharing,
    lanSocksPort,
    lanHttpPort,
    shareDeviceHwid,
    xrayCore,
    connectionMode,
    systemProxyEnabled,
    appLanguageCode,
  ]);

  ConnectionMode get connectionModeEnum =>
      ConnectionMode.fromStorage(connectionMode);

  String toJsonString() => jsonEncode(toJson());

  factory AppSettings.fromJsonString(String s) =>
      AppSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);
}