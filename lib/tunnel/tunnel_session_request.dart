import 'connection_mode.dart';
import 'vpn_backend.dart';

class TunnelSessionRequest {
  final ConnectionMode mode;
  final VpnBackend vpnBackend;
  final String xrayConfig;

  final String? mihomoConfig;
  final int socksPort;
  final int httpPort;
  final List<String> excludePackages;
  final List<String> includePackages;
  final List<String> excludeProcesses;
  final List<String> includeProcesses;
  final String? serverName;
  final bool systemProxy;

  final String coreEngine;

  final bool debugMode;

  const TunnelSessionRequest({
    required this.mode,
    this.vpnBackend = VpnBackend.xray,
    required this.xrayConfig,
    this.mihomoConfig,
    this.socksPort = 2080,
    this.httpPort = 2081,
    this.excludePackages = const [],
    this.includePackages = const [],
    this.excludeProcesses = const [],
    this.includeProcesses = const [],
    this.serverName,
    this.systemProxy = true,
    this.coreEngine = 'chain',
    this.debugMode = false,
  });

  Map<String, dynamic> toMethodChannelArgs({
    required String socksUsername,
    required String socksPassword,
  }) => {
    'connectionMode': mode.storageValue,
    'vpnBackend': vpnBackend.wireValue,
    'xrayConfig': xrayConfig,
    if (mihomoConfig != null && mihomoConfig!.isNotEmpty)
      'mihomoConfig': mihomoConfig,
    'socksPort': socksPort,
    'socksUsername': socksUsername,
    'socksPassword': socksPassword,
    'excludePackages': excludePackages,
    'includePackages': includePackages,
    'excludeProcesses': excludeProcesses,
    'includeProcesses': includeProcesses,
    'systemProxy': systemProxy,
    'coreEngine': coreEngine,
    if (serverName != null && serverName!.isNotEmpty) 'serverName': serverName,
  };
}
