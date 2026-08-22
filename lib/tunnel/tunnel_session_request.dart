import 'connection_mode.dart';
import 'vpn_backend.dart';

/// параметры запуска туннеля (android tun и desktop proxy/tun)
class TunnelSessionRequest {
  final ConnectionMode mode;
  final VpnBackend vpnBackend;
  final String xrayConfig;

  /// Сырой AmneziaWG `.conf` (когда [vpnBackend] == awg).
  final String? awgConfig;

  /// Конфиг mihomo (когда [vpnBackend] == mihomo). JSON — ядро читает его как
  /// YAML, тот надмножество; см. MihomoConfigGen.
  final String? mihomoConfig;
  final int socksPort;
  final int httpPort;
  final String? singboxConfig;
  final List<String> excludePackages;
  final List<String> includePackages;
  final List<String> excludeProcesses;
  final List<String> includeProcesses;
  final String? serverName;
  final bool systemProxy;
  final bool killSwitch;

  /// Ядро: `chain` (xray → sing-box) или `keqrnel` (единое ядро). Дефолт `chain`.
  final String coreEngine;

  /// Дебаг-режим приложения. Включает то, что стоит денег в рантайме и нужно
  /// только для диагностики: поиск процесса-владельца соединения в sing-box
  /// (`find_process`) для дебаг-экрана «Соединения».
  final bool debugMode;

  const TunnelSessionRequest({
    required this.mode,
    this.vpnBackend = VpnBackend.xray,
    required this.xrayConfig,
    this.awgConfig,
    this.mihomoConfig,
    this.socksPort = 2080,
    this.httpPort = 2081,
    this.singboxConfig,
    this.excludePackages = const [],
    this.includePackages = const [],
    this.excludeProcesses = const [],
    this.includeProcesses = const [],
    this.serverName,
    this.systemProxy = true,
    this.killSwitch = false,
    this.coreEngine = 'chain',
    this.debugMode = false,
  });

  Map<String, dynamic> toMethodChannelArgs({
    required String socksUsername,
    required String socksPassword,
  }) =>
      {
        'connectionMode': mode.storageValue,
        'vpnBackend': vpnBackend.wireValue,
        'xrayConfig': xrayConfig,
        if (awgConfig != null && awgConfig!.isNotEmpty) 'awgConfig': awgConfig,
        if (mihomoConfig != null && mihomoConfig!.isNotEmpty)
          'mihomoConfig': mihomoConfig,
        'socksPort': socksPort,
        if (singboxConfig != null && singboxConfig!.isNotEmpty)
          'singboxConfig': singboxConfig,
        'socksUsername': socksUsername,
        'socksPassword': socksPassword,
        'excludePackages': excludePackages,
        'includePackages': includePackages,
        'excludeProcesses': excludeProcesses,
        'includeProcesses': includeProcesses,
        'systemProxy': systemProxy,
        'killSwitch': killSwitch,
        'coreEngine': coreEngine,
        if (serverName != null && serverName!.isNotEmpty) 'serverName': serverName,
      };
}
