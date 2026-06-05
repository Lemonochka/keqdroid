import 'connection_mode.dart';

/// параметры запуска туннеля (android tun и desktop proxy/tun)
class TunnelSessionRequest {
  final ConnectionMode mode;
  final String xrayConfig;
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

  const TunnelSessionRequest({
    required this.mode,
    required this.xrayConfig,
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
  });

  Map<String, dynamic> toMethodChannelArgs({
    required String socksUsername,
    required String socksPassword,
  }) =>
      {
        'connectionMode': mode.storageValue,
        'xrayConfig': xrayConfig,
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
        if (serverName != null && serverName!.isNotEmpty) 'serverName': serverName,
      };
}
